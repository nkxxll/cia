# Code Inspection and Analysis

Requirements and implementation plan for a native GTK application that analyzes
a source tree and presents its metrics as an interactive OpenGL treemap.

## Product Goal

The application should make the structure and relative size of a codebase
immediately visible. A user selects a project directory, the application reads
the files that belong to the project, computes metrics, and displays files and
directories as nested treemap rectangles. Selecting a file should make it
possible to open that file at a useful location in Neovim.

The first release should optimize for a reliable end-to-end workflow rather
than a large number of language-specific analyses.

## Technology Choices

### Implementation language: Zig

Keep Zig as the implementation language. The prototype already targets Zig
0.16.0, has a `build.zig` build, and uses direct GTK/OpenGL bindings. Zig is a
good fit for filesystem traversal, bounded memory use, native binaries, and
the rendering/data-processing boundary.

### Command line parsing: comptime-reflected typed schema

Add a small typed command-line parser implemented in Zig, inspired by the
comptime type-reflection approach used by the TigerBeetle command-line parser.
The parser should take a comptime-declared options struct and derive option
names, value types, defaults, help text, and validation from its fields and
annotations. Prefer a focused in-tree parser or a dependency whose design
provides this reflection model; do not introduce a parser whose primary API is
an untyped map of strings.

The parser must:

- Parse positional arguments and long/short options without shell evaluation.
- Support booleans, strings, paths, enums, and integer values needed by the
  application.
- Produce useful errors for unknown options, missing values, invalid values,
  duplicate options, and unexpected positional arguments.
- Generate `--help` and a usage synopsis from the same comptime schema.
- Expose a typed `StartupOptions` value to the application layer.
- Be independent of GTK so it can be tested with normal unit tests.

The exact implementation should be validated against the TigerBeetle parser's
current source and the Zig 0.16.0 language/toolchain constraints before it is
adopted. The important decision is the comptime schema and typed result, not a
runtime dependency on TigerBeetle.

### UI: GTK 4

Use GTK 4 for the native application shell:

- `GtkApplication` and `GtkApplicationWindow` for lifecycle and windowing.
- `GtkBuilder`/Blueprint or equivalent declarative UI for the non-canvas UI.
- GTK actions and menus for opening projects, rescanning, and preferences.
- GTK input controllers for pointer, keyboard, and accessibility events.
- `GtkProgressBar`, status labels, and an error dialog for scan state.

GTK and GLib must remain the owner of the UI thread and main loop. Do not call
GTK APIs from the scanner or renderer worker threads.

### Rendering: `GtkGLArea` + OpenGL

Use the existing `GtkGLArea` as the OpenGL widget. `GtkGLArea` provides the GTK
integration and context lifecycle; OpenGL renders the treemap itself.

Use a small OpenGL 3.2+ renderer initially, accessed through libepoxy as in the
prototype. The renderer should use GPU buffers rather than one draw call per
file when practical:

- A rectangle instance contains position, size, depth, color, and item ID.
- A shader draws the rectangles, borders, and selection/hover state.
- A second, off-screen ID pass or CPU hit testing maps pointer coordinates to
  the selected item.
- Text labels should initially be rendered by GTK as an overlay or shown in a
  details panel; implementing a complete OpenGL text system is out of scope
  for the first milestone.

### Eventing and concurrency: GLib UI loop with libxev worker integration

GTK 4 uses the GLib main context, so libxev should not replace the GTK event
loop. Use libxev for asynchronous file reads and scan orchestration on a worker
thread, or as an isolated worker event loop. Send immutable scan progress and
result messages to the UI through a thread-safe queue. Schedule a GLib source
or idle callback to drain that queue on the GTK thread.

This keeps the UI responsive while avoiding unsafe cross-thread GTK calls. If
libxev integration proves more complex than the initial analyzer needs, the
scanner boundary must still remain independent so a Zig worker thread or thread
pool can be substituted without changing the UI.

### Project dependencies

- GTK 4, discovered with `pkg-config`.
- libepoxy, discovered with `pkg-config`, for OpenGL function loading.
- libxev, pinned in `build.zig.zon` once its integration API and supported Zig
  version are confirmed.
- OpenGL 3.2 or a compatible implementation supplied by the platform.

Avoid adding a parser framework or database until a concrete metric requires
one. Start with standard-library filesystem and text processing.

## Functional Requirements

### Command line interface

The application must accept a project directory at startup. A minimal initial
interface should support:

```text
cia [OPTIONS] [PROJECT_DIRECTORY]

Options:
  -h, --help                 Show usage and exit.
      --project PATH         Project directory; equivalent to the positional path.
      --dev-state STATE      Start with a deterministic development state.
      --dev-fixture PATH     Load a fixture or state description for development.
      --no-scan              Open the UI without starting an initial scan.
```

Requirements:

1. `.` must be accepted as the project directory and resolved to a normalized
   absolute path before scanning.
2. An explicitly supplied `--project PATH` and positional project path must not
   silently disagree; reject that invocation with a parse error.
3. With no project argument, the application may default to the current working
   directory, but this default must be documented and shown in the UI.
4. CLI parsing must happen before creating the GTK application so `--help` and
   parse errors can exit without opening a window.
5. Parse errors and help text go to the appropriate standard stream and return
   a nonzero status for errors.
6. CLI startup options must be converted into one application startup
   configuration object. GUI actions must use the same object/model rather than
   implementing a second scan-start path.
7. `--dev-state` and `--dev-fixture` are development/testing features. They must
   be clearly marked as unstable, excluded from normal user-facing help if a
   release build supports that distinction, or grouped under a development
   section of the help output.
8. Development state must be deterministic. It may select a metric, zoomed
   directory, selected item, hover item, scan status, or synthetic fixture, but
   it must not depend on pointer timing or live repository contents unless the
   option explicitly requests a real project scan.
9. Development options must not weaken path safety, bypass ownership rules, or
   invoke shell commands.

Example invocations:

```text
cia .
cia --project ~/src/my-project
cia ./fixture-project --dev-state treemap-loc
cia --project ./fixture-project --dev-fixture test-data/large-tree.json
cia --no-scan
```

### Project selection and scanning

1. The user can select a project root with a GTK directory chooser.
2. The application recursively discovers regular files below that root.
3. Symlinks are not followed by default, preventing loops and accidental scans
   outside the project. This may become a preference later.
4. The scan excludes configurable generated, dependency, and VCS directories.
   The initial defaults should include `.git`, `.hg`, `.svn`, `build`, `dist`,
   `target`, `node_modules`, and common cache directories.
5. The user can cancel a scan.
6. A rescan replaces the previous result atomically when complete.
7. Permission errors, disappeared files, invalid text, and unreadable files are
   reported as per-file warnings rather than aborting the entire scan.
8. The UI displays progress, the number of files processed, and a final warning
   count.

### File classification

1. Classify files by extension and, where useful, filename.
2. Provide an "all supported source files" default filter.
3. Treat binary files and very large files as excluded by default, with the
   reason recorded in diagnostics.
4. Make the source-file policy explicit and configurable rather than silently
   treating every file as source code.
5. Preserve normalized project-relative paths for display and absolute paths
   only for operations such as opening an editor.

### Metrics

The first version must calculate, for every included file:

- Byte size.
- Physical lines of code (LOC), including blank and comment line counts as
  separate values.
- A simple line classification: code, blank, comment, and mixed/unknown.
- File type/language classification.

For each directory, calculate aggregate values from descendants:

- Total file count.
- Total bytes.
- Total LOC and code/comment/blank counts.

The metric model must support adding later metrics without changing the
treemap or UI APIs. A metric is selected independently from the hierarchy.
Metric definitions and exclusions must be documented in the details view so
the numbers are understandable.

### Treemap visualization

1. The root project is represented by a rectangle containing directories and
   files.
2. Each directory is recursively subdivided into child rectangles.
3. Rectangle area is proportional to the selected metric, with zero-value items
   still visible through a minimum-size or secondary layout rule.
4. Directories and files are visually distinguishable.
5. The user can choose at least LOC, bytes, and file count as area metrics.
6. The user can zoom into a directory and navigate back to its parent.
7. Hover displays the relative path and metric value.
8. Clicking an item selects it and updates a details panel.
9. Colors have a documented meaning, such as language, file type, or metric
   range; color must not be the only way to distinguish items.
10. Layout and GPU buffers are rebuilt when the scan or selected metric changes,
    not on every frame.

### Neovim integration

1. The selected file can be opened in Neovim from a context menu, button, or
   double click.
2. The command is configurable, defaulting to `nvim`.
3. Launch Neovim without blocking the GTK UI, using a child process API.
4. Pass an absolute file path and optionally a line number when a future metric
   identifies a source location.
5. Display a clear error if Neovim is not found or cannot be started.
6. Do not construct a shell command string from paths; use argv-style process
   spawning so paths containing spaces or shell characters are safe.

## Non-Functional Requirements

- The UI must remain interactive while scanning and processing.
- A scan must not partially replace the currently displayed result.
- All allocations associated with a scan must be released when a new scan
  begins or the application exits.
- Paths must be handled as arbitrary filesystem byte sequences where the
  platform permits; invalid UTF-8 should not crash the scanner.
- Cancellation must be checked during traversal, reading, and processing.
- The renderer must handle at least 10,000 visible items without an obvious
  per-item CPU draw-call bottleneck.
- Results must be deterministic for the same project contents, settings, and
  metric selection.
- Diagnostics must identify skipped files and failures without exposing an
  unsafe path to a shell.
- Unit-testable analyzer and layout code must not depend on GTK or an active GL
  context.

## Proposed Architecture

```text
GTK actions and widgets
          |
          v
Application state <---- UI message queue <---- scanner worker/libxev
          |
          +--> immutable AnalysisResult --> treemap layout
                                             |
                                             v
                                      GtkGLArea renderer
```

Suggested modules:

- `cli.zig`: comptime option schema, parser, help generation, validation, and
  conversion to `StartupOptions`.
- `application.zig`: GTK lifecycle, actions, state transitions, and UI updates.
- `project.zig`: project root, ignore rules, file classification, and path
  normalization.
- `scanner.zig`: traversal, cancellation, file reading, and progress messages.
- `metrics.zig`: line classification and file/directory aggregate metrics.
- `model.zig`: immutable analysis snapshot and item IDs used by the UI.
- `treemap.zig`: hierarchy construction and deterministic rectangle layout.
- `renderer.zig`: GL resource management, buffer uploads, drawing, and picking.
- `editor.zig`: safe Neovim process launching and command configuration.
- `gtk.zig`: progressively expanded C declarations, or a maintained GTK
  binding if one becomes suitable for the project.

Startup flow:

```text
argv -> cli.parse(comptime schema) -> StartupOptions
                                  |
                                  v
                         GTK Application state
                         /                  \
                initial scan          dev-state injection
                         \                  /
                          -> treemap/model/UI
```

`StartupOptions` should contain the normalized project path, scan policy,
optional development state, and editor configuration. It should not contain
GTK pointers. Development fixtures should be translated into the same
`AnalysisResult` and view-state interfaces used by a real scan.

The scanner should publish a completed `AnalysisResult` through ownership-safe
messages. The UI takes ownership only after the result is complete. Progress
messages may be coalesced so a fast scan does not flood the GTK main context.

## Initial Data Model

Each item needs a stable ID for the lifetime of an analysis result and should
contain:

- Item kind: root, directory, or file.
- Project-relative path and display name.
- Parent ID and child range/list.
- File classification and language.
- Direct metrics for files.
- Aggregated metrics for directories.
- Optional diagnostic flags.

The layout output should be separate from this model and contain only render
data: item ID, rectangle, depth, color key, and visibility state. This keeps
layout changes and rendering changes independent from scanning.

## Phased Implementation Plan

### Phase 0: Prototype cleanup

- Apply CIA branding to the application and window.
- Add `cli.zig` with a comptime-reflected options schema, typed parsing, usage
  generation, and `StartupOptions`.
- Support `--help`, a positional project directory, `--project`, `--no-scan`,
  and development-only state/fixture options.
- Ensure parse errors exit before GTK initialization.
- Keep the current `GtkGLArea` wiring but move OpenGL code out of
  `application.zig` into `renderer.zig`.
- Add a basic project chooser and a status area.
- Add analyzer, layout, and renderer tests as separate build test targets.

### Phase 1: End-to-end static scan

- Start a scan from the CLI-selected directory and from the GTK directory
  chooser using the same startup/scan configuration.
- Select a directory and recursively traverse it.
- Implement default ignore rules, cancellation, and per-file diagnostics.
- Compute bytes, physical LOC, blank lines, and comment lines.
- Build the immutable hierarchy and show a simple file list/details panel.
- Add progress reporting and atomic result replacement.

### Phase 2: Treemap MVP

- Implement a deterministic squarified treemap or slice-and-dice layout.
- Add metric selection for LOC, bytes, and file count.
- Upload rectangles to the OpenGL renderer in batches.
- Add hover, selection, directory zoom, breadcrumbs, and a details panel.
- Add CPU hit testing first; add GPU ID picking only if profiling justifies it.

### Phase 3: Responsive asynchronous processing

- Introduce a scanner worker boundary and cancellation token.
- Integrate libxev for asynchronous file operations and worker orchestration if
  it provides a stable benefit on the supported platforms.
- Marshal progress/results to GTK through a thread-safe queue and GLib callback.
- Add stress tests for large trees and verify that the GTK frame rate remains
  usable during scans.

### Phase 4: Neovim and usability

- Add safe configurable Neovim launching.
- Add keyboard navigation and context menus.
- Add preferences for ignore directories, source-file policy, and editor
  command.
- Persist only user preferences initially; do not persist full scan contents.

### Phase 4a: Development workflow

- Add named deterministic development states for common UI scenarios, such as
  empty project, large treemap, selected file, scan failure, and scan in
  progress.
- Add fixture loading that produces the normal model/result types rather than a
  renderer-specific mock path.
- Document stable development invocations for screenshots, manual testing, and
  bug reports.

### Phase 5: Analyzer extensibility

- Add a metric registry interface.
- Add language-aware comment handling where the simple classifier is
  insufficient.
- Consider tree-sitter or language-specific parsers only for metrics that need
  syntax trees, such as function count, cyclomatic complexity, or imports.
- Profile memory, traversal, layout, and rendering before optimizing further.

## Testing and Verification

- Unit tests for path filtering, ignore rules, line classification, aggregation,
  cancellation, and deterministic ordering.
- Parser tests for defaults, positional paths, `--project`, boolean flags,
  enums, invalid values, duplicate project arguments, help generation, and
  development-state options.
- Property tests for treemap invariants: rectangles stay within their parent,
  do not overlap, and area ordering follows metric weights within defined
  tolerances.
- Fixture projects containing nested directories, empty files, comments,
  Unicode names, unreadable files, symlinks, and generated directories.
- Renderer smoke test that creates a GL context and draws an empty and a large
  layout where the platform supports headless testing.
- Manual acceptance test for selecting a project, cancelling, rescanning,
  zooming, selecting a file, and opening it in Neovim.
- CLI acceptance tests for `cia .`, `--help`, invalid options, and each
  documented deterministic development state.
- Run `zig build test` and `zig build` for every milestone; run the application
  with a fixture project before merging UI changes.

## Risks and Decisions to Confirm

- **GTK/libxev integration:** GTK's GLib loop remains authoritative. Confirm
  whether the chosen libxev release supports the required Zig version and file
  APIs before making it a hard dependency.
- **OpenGL portability:** retain a clear unsupported-context error and avoid
  relying on extensions beyond the selected minimum version.
- **LOC semantics:** publish the exact line classification rules and allow the
  classifier to report unknown languages instead of pretending all comments are
  known.
- **Large repositories:** enforce configurable file-size and item-count limits,
  and consider lazy directory expansion if memory or layout time becomes an
  issue.
- **GTK bindings:** the current hand-written declarations are suitable for a
  prototype but need careful expansion or replacement before broad UI use.
- **Comptime parser maintenance:** reflection-heavy parsing must remain readable
  and compatible with Zig 0.16.0. Keep the supported field types small, test
  compile-time diagnostics, and avoid clever generic behavior that obscures
  command semantics.
- **Editor behavior:** decide whether Neovim should open in a new terminal,
  reuse an existing server via `nvim --remote`, or simply launch `nvim` in a
  terminal. The initial implementation should make this a configurable argv
  command.

## MVP Acceptance Criteria

The MVP is complete when a user can launch `cia .` or provide another
project path, see a responsive OpenGL treemap sized by LOC, navigate into
directories, inspect a file's metrics, rescan or cancel safely, and open the
selected file in Neovim. `--help` and invalid CLI input must work without
opening GTK, and documented development states must make representative UI
states reproducible. The analyzer must continue past individual unreadable or
unsupported files and must never freeze the GTK UI during normal scanning.
