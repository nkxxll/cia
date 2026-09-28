# Lazy, shared file analysis

Historical exploration. The selected approach is now documented in
[the report design](core-info-design.md): share temporary analysis within each
request and defer persistent caching. The lazy getters, cache ownership and
invalidation below are not the current implementation plan.

## Goal

Compute file and function metrics on demand while reusing the same source buffer,
AST, line information, and function index. Reading a file or parsing it should
happen at most once per cached file snapshot, unless its analysis data is evicted.

Initial metrics:

- File physical and nonblank lines of code (LOC).
- Function physical and nonblank LOC.
- Function and file cyclomatic complexity (CC).

## Architecture

Introduce a `FileAnalysis` object for each loaded, immutable file snapshot:

```text
FileAnalysis
├── source                  read once; owned by the snapshot
├── line index              built on first line-based request
├── AST                     parsed on first AST-based request
├── function index          extracted on first function-based request
└── metric results          computed and cached on demand
    ├── file LOC
    ├── function LOC
    └── cyclomatic complexity
```

Move parsing out of `CCInfo.compute()`. Metric implementations consume shared
analysis data rather than independently reading and parsing files.

### Dependencies

| Requested metric | Required data |
| --- | --- |
| File physical LOC | Source / line index |
| File nonblank LOC | Source / line index |
| Function source ranges | AST → function index |
| Function LOC | Function index + line index |
| Function CC | AST + function index |
| File CC | Function CC results |

Requesting file LOC must not parse the AST. Requesting function LOC followed by
CC must reuse the AST and function index.

## Lazy getters and cache state

Start with optional cached fields and fallible getters rather than a generic
metric dependency framework. The following is an interface sketch; supporting
types and computation functions still need implementation:

```zig
pub const FileAnalysis = struct {
    gpa: std.mem.Allocator,
    source: [:0]const u8,

    ast: ?std.zig.Ast = null,
    line_index: ?LineIndex = null,
    functions: ?FunctionIndex = null,
    cc: ?CCResults = null,

    pub fn getAst(self: *FileAnalysis) !*const std.zig.Ast {
        if (self.ast == null) {
            self.ast = try std.zig.Ast.parse(
                self.gpa,
                self.source,
                .zig,
            );
        }

        if (self.ast.?.errors.len != 0) {
            return error.InvalidSyntax;
        }

        return &self.ast.?;
    }

    pub fn getCC(self: *FileAnalysis) !*const CCResults {
        if (self.cc == null) {
            const ast = try self.getAst();
            const functions = try self.getFunctions();
            self.cc = try computeCC(self.gpa, ast, functions);
        }
        return &self.cc.?;
    }
};
```

Getter behavior:

- Initialize a missing dependency before computing the requested result.
- Publish a cache value only after successful computation; clean up partial
  allocations on failure.
- Retain an AST containing syntax errors so subsequent requests return
  `error.InvalidSyntax` without reparsing. File line metrics remain available.
- Leave the relevant cache unset after allocation failure so it can be retried.
- Return borrowed, read-only results valid until snapshot destruction or eviction.

Initially, give each snapshot one owner and serialize calls to its getters. If
background workers later share snapshots, add synchronization around lazy
initialization or publish completed immutable results from a single owner.

## Line index: one scan, reusable range queries

On the first line-based request, scan the source once and collect:

- Byte offsets of line starts.
- Total physical lines.
- Prefix counts of nonblank lines.

An initial representation could be:

```zig
const LineIndex = struct {
    starts: []u32,
    nonblank_prefix: []u32,
};
```

For a nonempty function byte range `[start, end)`:

1. Binary-search line starts to locate `start`.
2. Binary-search line starts to locate `end - 1`.
3. Count the intersected physical lines.
4. Subtract prefix counts to obtain the number of nonblank lines.

This requires one source scan to build the index, `O(log lines)` to locate a
range, and `O(1)` to calculate its counts afterward. Handle empty ranges
explicitly rather than subtracting one from an empty end offset.

Define and test the counting conventions before implementation:

- Empty files and a final newline.
- LF and CRLF line endings.
- Whether function LOC includes signatures and documentation comments.
- Whether outer functions include lines occupied by nested declarations.
- Whether a partially intersected line is classified using the whole line or
  only the selected bytes. Whole-line classification supports the prefix index
  directly; exact byte-range classification needs boundary-line handling.

Keep physical LOC, nonblank LOC, and lines containing code distinct. If code-only
LOC is added, use Zig tokenization to distinguish comments from strings rather
than searching raw text for `//`. Cache those classifications as another shared
dependency when needed.

## Shared function index

Move function discovery and source ranges out of `CCInfo` into a reusable index:

```zig
const FunctionInfo = struct {
    node: std.zig.Ast.Node.Index,
    name: []const u8,
    declaration_start: u32,
    body_start: u32,
    end: u32,
};
```

- Use byte ranges with exclusive end offsets.
- Discover root functions, container methods, and local container functions.
- Exclude prototypes without bodies from function-definition metrics.
- Preserve source order and identify functions by index within the snapshot;
  names alone are not unique.
- Allow LOC and CC to share the same entries.

Names borrow from the owned source. AST node indexes are valid only for the
snapshot's AST and must not be reused across file revisions.

## CC: lazy per-file computation

On the first CC request, compute and cache results for all functions in that
file. File CC is their sum. This is a useful initial tradeoff because file-level
CC requires all function results anyway.

Replace the current decision-to-function range search with an AST traversal
that tracks the current function. Attribute decisions directly to their owning
function, keeping nested function bodies independent and distinguishing local
container declarations from expressions executed by the enclosing function.

Preserve and document the current metric convention unless deliberately revised:

- Baseline of 1 per function.
- Add 1 for each `if`, loop, non-`else` switch prong, `and`, `or`, `catch`,
  `orelse`, and `try`.
- Grouped switch values count as one prong.
- Include comptime branches.

Additional AST-derived metrics can share a traversal when they naturally use
the same work. Do not eagerly compute unrelated expensive metrics merely because
an AST is available.

## Snapshot ownership and invalidation

`FileAnalysis` owns the sentinel-terminated source buffer. Its AST and borrowed
names refer to that buffer, so the buffer must remain alive for their lifetimes.
Provide a `deinit` that releases cached allocations and the AST before freeing
the source.

Treat source as immutable:

```text
file changes → invalidate old analysis → load new snapshot
```

Use a consistently normalized path to locate a cache entry. Modification time
and size are inexpensive indicators of likely changes; a content hash provides
stronger identity after reading. Do not mutate a source buffer in place while
retaining its AST, ranges, or metric results.

If asynchronous jobs are introduced, tag each result with its snapshot revision
and discard stale results rather than attaching them to a newer file version.
Keep an old snapshot alive until its consumers have released it.

## Memory budget and eviction

Start with snapshot-lifetime caching. For large repositories, introduce a memory
budget and retain compact metric results longer than source buffers and ASTs.

- Evict heavyweight analysis data when it is no longer borrowed.
- Retain numeric LOC and CC results where useful.
- Copy names or other source-backed data that must survive source eviction.
- Rebuild evicted dependencies on a later request, checking that they still
  belong to the expected file revision.

“Parse once” is therefore the common case for a resident snapshot, not a promise
to keep every AST in memory indefinitely.

## Suggested module structure

Within the analysis library, use:

```text
analysis/
    FileAnalysis.zig    source ownership and lazy caches
    LineIndex.zig       line offsets and line statistics
    FunctionIndex.zig   function discovery and ranges
    CCInfo.zig          complexity calculation and results
```

The existing `zig-compiler-internals` library is the initial integration point.
Its CLI should create a snapshot, request its metrics, print the results, and
release the snapshot.

## Implementation sequence

1. **Introduce snapshot ownership and lazy AST access.** Move parsing from
   `CCInfo` into `FileAnalysis`; adapt CC and its CLI caller to consume it.
2. **Extract the function index.** Reuse it for CC, preserving current outputs
   and independently attributed nested functions.
3. **Implement the line index and LOC queries.** Build offsets and nonblank
   prefix counts in one scan; expose file and function queries.
4. **Cache metric results.** Compute all function CC values on the first CC
   request and reuse them for later function and file requests.
5. **Improve CC traversal.** Attribute decisions during AST traversal rather
   than searching function ranges for every decision.
6. **Integrate revision invalidation.** Replace snapshots when files change;
   add bounded eviction when repository-scale memory usage warrants it.

## Verification

- File LOC requests do not initialize the AST.
- Function LOC followed by CC parses once and reuses the function index.
- Repeated requests reuse cached results and do not duplicate entries.
- Invalid syntax is cached while source-only LOC remains available.
- Line counts cover empty input, trailing newlines, CRLF, blank lines, and
  multiline signatures.
- Nested functions have independent CC and documented LOC range behavior.
- Allocation failures and destruction release all owned memory.
- A new file revision cannot reuse stale ranges or metrics.
- Run the library's `zig build test`, `zig build`, and a CLI smoke test after
  integration.
