# Separating the analysis core from the UI

## Recommended boundary

Make the scanner and its result a Zig module that can be used without GTK,
OpenGL, or a running application. Keep the treemap layout in a separate pure
visualization module: it computes rectangles from weights, but does not analyze
source. The GTK executable composes the two modules and owns rendering and
background-job delivery.

```text
analysis module -> owned result -> GTK application -> weights/IDs
                                          |                 |
                                          |                 v
                                          |           layout module
                                          |           (rectangles)
                                          +---------> OpenGL renderer
```

The dependency direction is one-way: analysis imports only Zig's standard
library (and, later, analysis-specific dependencies); the layout imports only
standard-library types; UI may import both. Neither module imports `gtk.zig`,
`opengl.zig`, or `application.zig`.

## Where today's code belongs

| Current file                                                            | Destination / responsibility                                                                                                                                    |
| ----------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `src/countlines.zig`                                                    | **Core:** reusable line-counting metric; its `std.Io` and allocator parameters already make it independently usable.                                            |
| `src/scanner.zig`                                                       | **Core:** traversal, filtering, cancellation checks, file reads and warnings. `scan` / `scanCancelable` already take an opened root and return an owned result. |
| `src/lines_model.zig`                                                   | **Core:** `LinesModel` owns relative paths and metric values; it is the current result type.                                                                    |
| `src/treemap.zig`                                                       | **Layout:** pure ordered-weight-to-`Tile` geometry; `entry_index` refers to the order of input weights, not to a GTK widget.                                    |
| `src/application.zig`                                                   | **UI/composition:** `ScanJob`, thread, polling, status, layout selection, hover, GTK callbacks and result installation.                                         |
| `src/renderer.zig`, `src/opengl.zig`, `src/gtk.zig`, `src/ui/window.ui` | **UI:** GL resources, drawing, C bindings and widgets. `renderer.zig` reads layout tiles but does not compute metrics.                                          |
| `src/cli.zig`, `src/main.zig`                                           | **Executable adapter:** parse `lines`, choose the initial screen, construct and run the GTK application; no CLI parser is needed by the library.                |
| `src/tests.zig`                                                         | **Build/test wiring:** split its imports so core and layout have their own headless test roots.                                                                 |

`src/application.zig` currently opens `.` in `scanCurrentDirectory`, passes a
cancel flag to `scanner.scanCancelable`, and transfers the returned `LinesModel`
under a mutex in `pollScan`. Keep opening the chosen directory and the thread
handoff in the application; the library should accept a caller-owned directory
and return a caller-owned result. The worker must not call GTK. The current
`rebuildLayout` converts file LOC to weights with `@max(file.lines, 1)`: that
zero-value display policy stays with the UI/layout adapter, not the metric.

## Proposed source and build layout

```text
src/
  analysis/
    root.zig          exports the small public API
    scanner.zig
    countlines.zig
    lines_model.zig
  layout/
    root.zig          exports Rect, Tile, layout
    treemap.zig
  main.zig
  cli.zig
  application.zig
  renderer.zig
  opengl.zig
  gtk.zig
  ui/window.ui
```

Initially `analysis/root.zig` can re-export `LinesModel`, `LineCounter`,
`scan`, and `scanCancelable`; `layout/root.zig` can re-export the treemap API.
Avoid exporting GTK-facing state or the internal traversal helpers. In the
top-level `build.zig`, declare the two modules with `b.addModule` and attach
them to the executable's `root_module` with `addImport`. Change the imports in
`application.zig` and `renderer.zig` to use those module names. Give analysis
and layout separate `b.addTest` targets so their tests run without GTK or
libepoxy; the executable alone links `gtk4` and `epoxy`. The current test root
already imports only headless files, but it does not enforce the module
boundary. A module in the existing package is sufficient for the first split;
there is no need to create another package or duplicate the source tree.

## API and ownership contract

- Keep `scan(allocator, io, root)` and `scanCancelable(allocator, io, root,
cancelled)` as the starting API. `root` remains caller-owned and must support
  iteration. The result owns its paths and is released via `LinesModel.deinit()`.
- The result is complete before publication. The worker transfers ownership to
  `Application` under `ScanJob.mutex`; after transfer, only the UI reads it.
  Cancellation returns `error.Cancelled` rather than a partial result; per-file
  read failures currently increment `warning_count`.
- File order is deterministic today (breadth-first traversal with lexically
  sorted entries inside each directory). Tiles refer to `files.items` by index;
  keep the result alive while tiles, tooltips, or selections refer to it. Clear
  derived tiles/hover before replacing or deinitializing a result.
- `LineCounter` defines physical lines as newline count plus an unterminated
  final line; empty input is zero. Keep this semantic in the analysis API so a
  headless client and the GUI report the same metric.

## Migration sequence

1. Move the three core files under `src/analysis/`, add its module root, wire
   the module in `build.zig`, and import it from `application.zig`. Keep
   `scanCurrentDirectory` and the `ScanJob` handoff on the UI side. Run the
   core tests independently.
2. Move `treemap.zig` under `src/layout/`, expose its pure API and update the
   renderer and application imports and build wiring. Keep the LOC-to-weight
   conversion in the application. Run the layout tests independently.
3. Keep `zig build` and `zig build test` exercising the GUI build and headless
   tests respectively. A small headless executable can then open a directory,
   call `analysis.scan`, print paths/LOC,
   and deinit the result without linking GTK.
4. When the result grows beyond today's flat Zig-only LOC list, evolve the
   core model to hold file/directory IDs, aggregate metrics, classifications,
   and diagnostics. The UI should choose metric weights and translate IDs to
   hover/selection; the layout should only accept IDs/weights and bounds.

`zig-compiler-internals/` is currently a **separate** Zig package with its own
`build.zig`, module root, CLI, and AST-based `CCInfo`; the GTK app does not
import it. It is a candidate to integrate _into_ analysis for Zig-specific
complexity, rather than part of the UI split. Its `CCInfo.compute()` reparses
source and borrows its content, so align its ownership/caching with the
`FileAnalysis` proposal in [lazy-metrics-analysis.md](lazy-metrics-analysis.md)
before presenting it as a shared metric API. Do not require AST parsing to
obtain today's streaming LOC metric.

This extraction establishes the headless boundary now while leaving room for
the richer hierarchy and metrics described in [REQUIREMENTS.md](REQUIREMENTS.md).
