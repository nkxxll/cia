# Design: data-only analysis reports

Proposal only; the report API described here is not implemented yet.
This is the selected direction for future core analysis. It replaces the earlier
persistent information graph and its lazy getters, generations and invalidation.

## Architecture

Core defines requests, common report types and the language adapter contract.
Gatherers compute requested facts from explicit inputs; adapters normalize those
facts into reports. Displays consume completed reports independently of gatherers.

```text
request + configuration
          |
     discover / read                 explicit I/O boundary
          |
     immutable source inputs
          |
     language gatherers              compute requested facts
          |
     core adapters + aggregation     normalize into common records
          |
     owned ProjectReport
          |
     CSV / GUI / TUI / C adapter
```

The initial implementation has no persistent analysis session. Temporary source
buffers, ASTs and indexes live only as long as needed within one request. Reading
a report field never performs I/O, parses source or computes a missing metric.

## Requests and computation

The conceptual public operation is `analyze(request) -> ProjectReport`. Zig
callers also supply an allocator, IO, a borrowed root directory and optional
cancellation. The exact API and supporting types remain to be implemented.

A request explicitly selects scope, entity collections and metrics, for example
project/file physical LOC plus structs and functions with their own LOC. Core
validates the request and coordinates only the dependencies needed to fulfill it:

| Requested information | Required work |
| --- | --- |
| File membership/count | Discover supported paths |
| File/project physical LOC | Read source, count lines, aggregate |
| Struct/function membership | Read, parse, extract declarations |
| Struct/function LOC | Extract declarations and build a shared line index |
| Function/file complexity | Reuse syntax and declaration analysis |

Within a request, read each needed file once and parse it at most once for syntax
analysis. Share temporary syntax, declarations and line indexes across requested
metrics. Process files and release heavy temporary data as soon as possible;
there is no requirement to retain every source and AST for the whole project.
Internal dependencies need not appear as requested fields in the returned report.
A later request recomputes its required work initially.

Discovery, source reading and any future compiler invocation are explicit effects.
Source analysis and aggregation are deterministic functions of immutable inputs,
configuration and metric policy, with allocation failures handled explicitly.
Gatherers do not read hidden global state, call displays or mutate prior reports.
Temporary allocation and local computation state are allowed.

## Common report and language extensions

Use a common `ProjectReport` struct rather than a top-level union of complete
language reports. This supports mixed-language projects and lets ordinary
consumers access common fields without switching on language.

Conceptual shape, not a concrete Zig declaration:

```text
ProjectReport
  files: Result([]FileReport)
  totals
  diagnostics[]

FileReport
  id
  path
  language
  metrics
  structs: Result([]StructReport)
  functions: Result([]FunctionReport)
  extras: none | zig | rust | go | ...

StructReport / FunctionReport
  id
  name: anonymous | named
  range: [start, end) byte offsets
  lexical_parent: optional report-local entity ID
  metrics
  extras: none | language-specific data
```

A file owns its declaration collections structurally. Parent IDs express lexical
nesting without duplicating declarations in multiple collections. A function may
also have an optional direct container owner; lexical containment and method
ownership are different relationships. IDs are unique within a report and have
no identity or validity guarantee across analyses. Names are not identities.

Core defines the meaning of every common field. Each adapter maps native language
concepts to those definitions or reports that a requested concept is unsupported.
Do not equate all language containers with structs merely to fill a common field.
Native AST nodes, compiler handles and parser references never cross into reports.

Language-specific data uses optional tagged unions on the relevant records.
Common consumers may ignore these extensions. Start with Zig and common fields;
Rust, Go and extension payloads are later additions when needed, not empty
backends or speculative extension frameworks to implement now.

## Result states, diagnostics and totals

A requested value must distinguish these conceptual outcomes:

- `not_requested`: absent because the request did not select it.
- `value(T)`: successfully computed, including zero or an empty collection.
- `unsupported`: the language adapter cannot provide the requested information.
- `failed`: requested analysis failed, with an associated diagnostic.
- `partial(T)`: available data covers only part of the requested scope, with
  diagnostics describing omissions.

Apply the same distinction to collections and aggregates. These are report
outcomes, not mutable cache states. A consumer never retries computation by
accessing an outcome. Diagnostics contain owned paths/messages and source ranges
where available; they must not borrow parser storage.

Recoverable file failures may produce a completed report containing partial
results. For example, an unreadable discovered file remains represented with a
failed LOC outcome; the project LOC total is partial. Discovery failures make
membership and dependent totals partial as well. Invalid syntax can fail
syntax-based metrics while physical LOC remains available. Unsupported inputs
must not silently contribute zero to a supposedly complete total.

Project physical LOC sums file LOC using checked arithmetic. Struct/function
ranges may overlap and are never summed to obtain project physical LOC. File
complexity sums independently attributed function complexity under a documented
policy. Common metric definitions must remain consistent across adapters;
language-specific conventions belong in extensions or explicitly named policies.

Allocation failure, cancellation and fatal setup errors return an error after
cleaning up temporary allocations. Cancellation publishes no report. A completed
report with partial outcomes is distinct from exposing an unfinished computation.

## Ownership and displays

The caller owns the returned report and releases it through a single `deinit`.
All retained paths, names, diagnostics and extension payloads are report-owned.
The report survives destruction of source buffers, ASTs and gatherer temporaries.
An arena is a possible implementation detail, not a required public representation.

Treat published reports as immutable. They contain data and lifetime management,
with no analysis getters, invalidation hooks or formatting methods. CSV export,
GUI, TUI and other consumers depend on common report types and implement their own
formatting, projection and presentation. A display may opt into language extras
without requiring other displays to support them. Consumers handle non-value
outcomes explicitly instead of presenting missing or failed metrics as zero.

The application runs analysis on a worker and owns cancellation and publication.
The GUI installs a completed report atomically and releases the previous report
only after its readers finish. Selection, layout and other view state belong to
the frontend. Any job sequencing used to reject obsolete completions also belongs
to the application, not to report entities.

## Initial Zig extraction and counting

Preserve current regular `.zig` filtering, skipped directories, symlink exclusion
and breadth-first ordering with lexical ordering within each directory. Include
build/test files. Paths remain owned bytes relative to the scan root; do not
require all filesystem paths to be UTF-8. Identical inputs, requests and policies
produce deterministically ordered report data. Reads are per-file snapshots, not
an atomic snapshot of a changing project directory.

Use shared syntax analysis to discover explicit struct expressions and function
definitions in source order, including nested declarations. Exclude implicit file
structs, bodyless function prototypes and test declarations from those collections.
Represent unnamed declarations explicitly. Derive lexical parents from containment
and direct method owners from container membership, respecting enum/union boundaries.

Use exclusive byte ranges and a shared line-start index. Function ranges include
modifiers, signature and body, excluding preceding documentation. Struct ranges
include the layout modifier, expression and braces, excluding the binding prefix
and trailing semicolon. Physical LOC includes comments and blanks; empty input is
zero, CRLF is one line break and a final newline adds no extra line. Nested source
ranges overlap by design. Reject inputs exceeding parser/index limits safely.

Define the complexity counting policy before exposing it as a common metric.
Nested function bodies contribute to their own complexity, not their enclosing
function's complexity. Reuse the same temporary parse for declarations, range LOC
and complexity requested together.

## Caching and semantic analysis later

First implement and measure the stateless request-to-report pipeline. Persistent
caching can later wrap or live inside gatherers without changing report semantics.
Cache keys must include source identity, request/policy and relevant configuration.
A long-running application may notify a cache about changed inputs; reports already
published remain valid and unchanged. Watchers, eviction, invalidation generations
and persistent handles are not part of the initial contract.

Project-wide semantics and call graphs need explicit project inputs, including
build configuration and dependencies. They cannot generally be computed from one
isolated file. Future compiler backends may maintain native sessions and perform
their own parsing; reuse across unrelated compiler APIs is not promised.

A future call graph can be report-owned data with report-local function IDs,
call sites, resolution outcomes and coverage. Unknown/external targets must stay
visible. Graph computation does not require live getters on function records.
Semantic cache validity must account for project dependencies and configuration,
not merely the file containing a queried function. This work is deferred.

## Implementation sequence

1. Define common request/report records, outcome states, diagnostics and ownership.
2. Separate discovery/loading from source computations; implement requested file
   physical LOC and project totals with the existing scan behavior.
3. Add the Zig adapter and temporary shared parse/index analysis for structs,
   functions and their LOC. Add complexity after defining its policy.
4. Adapt existing `scan`/`scanCancelable`, `LinesModel` and C/GUI integration through
   compatibility conversions, preserving cancellation, ownership and warning behavior.
5. Add independent report consumers such as CSV alongside the GUI. Keep report
   fields free of presentation logic.
6. Add other languages, language extensions, persistent caching and semantic
   metrics only when required by concrete use cases.

## Acceptance checks for implementation

- Requests compute only required dependencies; file LOC does not parse source.
- Multiple syntax metrics in one request reuse one parse per file.
- Repeated stateless requests over identical inputs produce equivalent reports.
- Report paths, names and diagnostics survive destruction of analysis temporaries.
- Empty, zero, unrequested, unsupported, failed and partial outcomes stay distinct.
- Mixed-language fixtures use common fields without language dispatch in consumers.
- Project LOC equals complete file totals; overlapping declaration LOC stays separate.
- Named/anonymous and nested declarations have correct ranges and relationships.
- Cover empty files, final newlines, CRLF, invalid syntax, unreadable files and
  deterministic ordering, along with allocation failure and cancellation cleanup.
- Independent consumers can use the same completed report without invoking gatherers.
- Preserve existing core, C ABI, CLI and GUI integration behavior; run the relevant
  workspace tests and builds when implementing the design.
