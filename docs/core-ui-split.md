# Core / UI package boundary

The repository contains two Zig 0.16 packages:

```text
cia-core/                  independently buildable analysis package
  build.zig                exports cia-core module and shared library
  build.zig.zon
  include/cia_core.h        C / C++ API
  src/root.zig             public Zig analysis API
  src/countlines.zig
  src/lines_model.zig
  src/scanner.zig
  src/c_api.zig             shared-library adapter
  tests/                   C ABI integration test and fixture
cia-opengl/                 GTK 4 / OpenGL application package
  build.zig                depends on cia-core; exports pure layout module
  build.zig.zon            local ../cia-core dependency
  src/layout/              pure treemap geometry and tests
  src/application.zig      scan jobs, ownership handoff, UI state
  src/main.zig, cli.zig     executable adapter
  src/renderer.zig, opengl.zig, gtk.zig, ui/window.ui
build.zig                  workspace build / run / test convenience commands
```

The root manifest is workspace wiring, not a third implementation package.
`zig build` at the root installs `cia`, the core shared library, and its C
header. `zig build run -- lines` preserves the application's invocation.
`zig build test` runs core, C ABI, CLI, and layout tests headlessly. Each child
package also supports independent `zig build` and `zig build test` commands.
The frontend uses the Zig module directly; it does not require the C adapter.

## Dependency direction

```text
cia-core (standard library only) -> owned analysis result -> cia-opengl
                                                              |
                                               weights -> layout -> renderer
```

Analysis exports `LinesModel`, `FileLines`, `LineCounter`, `scan`, and
`scanCancelable`. The scanner has no knowledge of GTK, OpenGL, treemap tiles,
or application state. The layout module stays separate from source analysis:
it converts ordered weights to rectangles and imports only the standard
library. Its tests do not link GTK or libepoxy.

The application owns directory selection/opening, `ScanJob`, the worker
thread, cancellation flag, polling, and result installation. Workers never
call GTK. The UI retains the zero-line display policy (`@max(file.lines, 1)`),
hover state, and rendering resources.

## Ownership and behavior

- Zig callers supply an allocator, IO implementation, and caller-owned root
  directory opened with `.iterate = true`. Returned models own their paths
  and storage and must be released with `LinesModel.deinit()`.
- Results are complete before publication. The worker transfers ownership to
  the application under its mutex. Cancellation returns `error.Cancelled`,
  not a partial result; per-file failures increment `warning_count`.
- File order remains breadth-first, lexically sorted within each directory.
  Tiles refer to model files by index. Derived tiles and hover state must be
  cleared before replacing or freeing the model.
- Physical lines are newline count plus an unterminated final line; empty
  input has zero lines. Currently only regular `.zig` files are analyzed.

## Shared library and other frontends

`cia-core` builds a dynamic library and installs `cia_core.h`. Its C ABI uses
an opaque result, explicit destruction, borrowed path bytes with lengths,
line counts, warning counts, and integer status codes. It never exposes Zig
slices, allocators, error unions, or `std.Io`. A C++/Qt frontend can link the
library and scan on its own worker thread. The C scan API is synchronous and
does not yet expose the Zig API's cancellation or progress reporting.

See [cia-core usage](../cia-core/README.md) and
[frontend build instructions](../cia-opengl/README.md) for commands and examples.
For publishing the packages separately, replace the frontend's sibling path
dependency with a published core URL and hash.

`zig-compiler-internals/` remains an independent experiment. Integrating its
AST analysis should follow the request and report design in
[core-info-design.md](core-info-design.md); today's streaming LOC
scan does not require AST parsing. Future hierarchy and metric work is
described in [REQUIREMENTS.md](REQUIREMENTS.md).
