# Lines Treemap Implementation Plan

This document describes how to translate the ordered pivot treemap prototype in
`treemapstudy/main.py` into the GTK lines screen using Zig and OpenGL. The
layout mathematics are specified separately in `docs/treemap.md`.

The implementation has three independent parts:

1. Background filesystem scanning and line counting.
2. A pure Zig treemap layout algorithm.
3. GTK/OpenGL rendering on the main thread.

Filesystem traversal and line counting must not happen in OpenGL callbacks.
GTK and OpenGL calls must not happen on the scanning worker.

## Current State

- `src/countlines.zig` provides the low-level `LineCounter`.
- `src/ui/window.ui` contains `lines_gl_area`, a `GtkGLArea` with
  `auto-render=false`.
- `src/application.zig` does not yet retrieve or configure `lines_gl_area`.
- `src/opengl.zig` exposes basic shader functions, but no treemap renderer is
  connected.
- The Python prototype uses byte size as each item's weight. The lines screen
  will use each file's line count instead.

`LineCounter` currently counts newline bytes rather than logical lines. A file
containing `hello` without a trailing newline counts as zero lines. LOC
semantics must be decided before exposing the value as a user-facing metric.

## Data Model

Introduce model types independent of GTK and OpenGL:

```zig
const FileEntry = struct {
    path: []const u8,
    lines: usize,
};

const Rect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

const Tile = struct {
    entry_index: usize,
    rect: Rect,
};
```

The completed scan model owns:

- All file paths.
- An ordered list of `FileEntry` values.
- The total line count.
- Optionally, skipped-file and error counts.

Sort entries by project-relative path before layout. Filesystem iteration order
is not guaranteed, and the ordered treemap result depends on input order. Do
not sort entries by line count.

The first implementation should use one tile per source file. Top-level
directory aggregation can follow later. A hierarchical, drill-down treemap
requires a tree model and additional navigation state.

## Background Scan

Start scanning from `Application.activate` after the window and widgets have
been initialized. Spawning the worker is fast and returns control to the GTK
main loop immediately.

The worker performs these steps:

1. Open the selected project directory, initially the current directory.
2. Recursively walk regular files without following symlinks.
3. Skip generated, dependency, cache, and VCS directories such as `.git`,
   `.jj`, `.zig-cache`, `zig-out`, and `.venv`.
4. Apply an explicit source-file filter.
5. Create one `LineCounter` owned exclusively by the worker.
6. Open each included file and call `LineCounter.countFile`.
7. Record the project-relative path and line count.
8. Treat per-file read failures as warnings and continue scanning.
9. Sort the completed entries by path.
10. Publish an immutable completed model.

`LineCounter` is not thread-safe, but one worker can safely own and reuse a
single instance. The worker must never call GTK or OpenGL.

Use an explicit scan state:

```zig
const ScanState = enum {
    idle,
    loading,
    ready,
    failed,
};
```

Store the state and result in a `ScanJob` protected by `std.Thread.Mutex`.

## Delivering Results To GTK

The initial implementation should use a GLib timeout source:

1. Start `g_timeout_add` when scanning begins.
2. Every 50 to 100 milliseconds, inspect `ScanJob` under its mutex.
3. While loading, show `Counting lines...` in a GTK status label.
4. When ready, transfer the completed model to `Application`.
5. Update the summary and warning labels.
6. Call `gtk_gl_area_queue_render`.
7. Return `G_SOURCE_REMOVE` to stop polling.

Polling keeps GTK access on the main thread and avoids complicated callback
lifetime management in the first implementation. A thread-safe message queue
and main-context wakeup can replace it later if progress reporting requires it.

`Application` will need fields equivalent to:

```zig
lines_gl_area: ?*gtk.GtkGLArea = null,
scan_job: ?*ScanJob = null,
scan_thread: ?std.Thread = null,
lines_model: ?LinesModel = null,
poll_source: gtk.guint = 0,
```

On shutdown:

- Remove the timeout source if it still exists.
- Join the scanning worker, even if the window was closed during a scan.
- Free scan and model allocations.
- Clear GTK widget pointers in `windowDestroyed`.

The `Application` and `ScanJob` storage must remain alive until the worker is
joined and no GLib callback can reference it.

## Pure Zig Layout

Port the following functions from `treemapstudy/main.py` into
`src/treemap.zig`:

- `valid_splits`
- `split_two`
- `split_regions`
- `layout_treemap`

Use these substitutions:

```text
Python entry["size"] -> FileEntry.lines
raylib Rectangle     -> Zig Rect
Python output tuple  -> Tile
```

The layout API can initially be:

```zig
pub fn layout(
    allocator: std.mem.Allocator,
    entries: []const FileEntry,
    bounds: Rect,
) ![]Tile
```

Handle these cases explicitly:

- No entries.
- All entries have zero lines.
- One entry.
- Two entries.
- A zero-width or zero-height viewport.
- Rectangles too small to draw after visual padding.

Keep floating-point layout rectangles separate from visual gaps and borders.
The direct Python translation is sufficient initially. If large file counts
make layout expensive, replace repeated range sums with prefix sums.

## GtkGLArea Lifecycle

In `Application.activate`:

1. Retrieve `lines_gl_area` from the builder.
2. Set the required OpenGL version before realization.
3. Connect its `realize` signal.
4. Connect its `render` signal.
5. Connect its `unrealize` signal.
6. Optionally connect `resize`, or detect changed dimensions during rendering.

### Realize

The realize callback must:

- Call `gtk_gl_area_make_current`.
- Check for context-creation errors.
- Compile and link the rectangle shaders.
- Create the vertex array object.
- Store OpenGL handles in application or renderer state.

### Render

The render callback must:

- Clear the background.
- Read the widget's logical width and height.
- Recalculate layout only if the model or dimensions changed.
- Draw every visible tile.
- Return false because the view is not continuously animated.

Because `auto-render=false`, model, size, hover, and selection changes must call
`gtk_gl_area_queue_render`.

### Unrealize

The unrealize callback must:

- Make the GL context current.
- Delete the shader program and vertex array object.
- Reset the stored OpenGL handles.

All OpenGL calls must happen while the `GtkGLArea` context is current.

## Initial Rectangle Renderer

The simplest renderer can draw each rectangle using `gl_VertexID`, avoiding
dynamic vertex-buffer management for the first working version. The six local
vertices are:

```text
(0, 0), (1, 0), (1, 1)
(0, 0), (1, 1), (0, 1)
```

Pass uniforms for:

- Rectangle position and size.
- Widget width and height.
- Tile color.

The vertex shader transforms the unit rectangle into logical pixel coordinates
and then normalized device coordinates. It must invert Y because treemap and
GTK coordinates start at the top-left while OpenGL starts at the bottom-left:

```glsl
vec2 pixel = rect.xy + unit_position * rect.zw;
vec2 ndc = vec2(
    pixel.x / viewport.x * 2.0 - 1.0,
    1.0 - pixel.y / viewport.y * 2.0
);
```

Draw each tile with `glDrawArrays(GL_TRIANGLES, 0, 6)`. `src/opengl.zig` will
need any missing APIs, including a four-component uniform function for the
rectangle and color.

Apply visual padding only when constructing render data:

```zig
const tile = Rect{
    .x = rect.x + 2,
    .y = rect.y + 2,
    .width = @max(0, rect.width - 4),
    .height = @max(0, rect.height - 4),
};
```

One draw call per tile is acceptable to establish the end-to-end path. Move to
an instanced GPU buffer before targeting very large repositories.

## Labels And Hover

Raylib provides text rendering, but OpenGL does not. For the first version:

- Draw colored rectangles with OpenGL.
- Show the project total, loading state, and errors with normal GTK labels.
- Attach `GtkEventControllerMotion` to `lines_gl_area`.
- Show the hovered path and line count in a GTK overlay label or tooltip.

Replace the current placeholder overlay in `src/ui/window.ui` with named status
and tooltip labels that `application.zig` can update and hide. Rendering labels
inside every tile would require Pango/Cairo textures or a font atlas and is out
of scope for the first implementation.

On pointer movement:

1. Read the pointer coordinates.
2. Search the cached tiles for the containing rectangle.
3. Update the tooltip or overlay label.
4. Store the hovered tile index.
5. Queue a render to draw a border or brighter hover color.

Keep layout and pointer coordinates in GTK logical pixels. The shader converts
logical coordinates to normalized device coordinates.

## Implementation Order

1. Add `src/treemap.zig` and test it with the Python study's inputs.
2. Implement recursive scanning and produce a sorted `LinesModel`.
3. Start the worker during activation and publish through a GTK timeout.
4. Add loading, summary, error, and tooltip labels to `window.ui`.
5. Connect the `GtkGLArea` lifecycle callbacks.
6. Render static colored rectangles.
7. Recalculate and redraw after resize.
8. Add hover highlighting and GTK tooltip text.
9. Add instanced rendering, OpenGL text, or hierarchical navigation only after
   the end-to-end version works and profiling justifies the complexity.

The complete flow is:

```text
GTK activate
    |
    +-- create and show window
    +-- initialize GtkGLArea callbacks
    +-- spawn scan worker
             |
             +-- walk files
             +-- count lines
             +-- sort entries
             +-- publish immutable model
                       |
GTK timeout polls -----+
    |
    +-- take model
    +-- calculate treemap
    +-- queue GtkGLArea render
             |
             +-- clear
             +-- draw one rectangle per file
```

## Verification

- Unit-test the wide and tall layout paths and all base cases.
- Verify output rectangles remain inside their parent bounds.
- Verify rectangles do not overlap and approximately cover the parent area.
- Verify rectangle areas are proportional to line counts.
- Verify deterministic output from path-sorted entries.
- Test empty files and files without a trailing newline according to the chosen
  LOC semantics.
- Close the window during a large scan and verify clean worker shutdown.
- Resize the lines screen and verify the layout is rebuilt correctly.
- Run `zig build test` and `zig build` after each implementation stage.
