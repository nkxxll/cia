# Zig OpenGL Tutorial

A deliberately small Zig 0.16 project that uses GTK4 for a native window and
input events, `GtkGLArea` for the OpenGL context, and libepoxy through
`src/opengl.zig` for OpenGL function loading.

## Run it

Install Zig 0.16, GTK4, and libepoxy. On macOS with Homebrew:

```sh
brew install zig gtk4 libepoxy pkg-config
```

From this directory:

```sh
zig build run
```

Controls:

- Move the mouse to move the white marker.
- Hold any mouse button and drag to pan.
- Scroll to zoom.
- Use arrow keys or WASD to pan.
- Click to change the triangle colors.
- Press Space to change the clear color.
- Press R to reset the view and Escape to quit.

## How the pieces fit

`src/gtk.zig` contains only the GTK declarations needed by this example. GTK
creates the window, owns the event loop, reports input, and makes an OpenGL
context current before the `render` and `resize` signals.

`src/opengl.zig` imports `epoxy/gl.h` and exposes the OpenGL types, constants,
and functions used by the renderer. Libepoxy finds the correct OpenGL function
for the active context, avoiding a hand-written platform-specific loader.

`src/main.zig` demonstrates the normal OpenGL lifecycle:

1. `activate` creates a `GtkGLArea` and connects input signals.
2. The first `render` compiles shaders, links a program, and creates a VAO/VBO.
3. Every `render` uploads vertices, sets uniforms, clears, and draws triangles.
4. `resize` updates `glViewport` for normal and high-DPI displays.
5. `unrealize` makes the context current and deletes every GPU object.

## Drawing basics

OpenGL 3.2 core does not provide `drawRectangle` or `drawCircle`. It draws
primitives from vertex data. This example represents both the triangle and the
rectangle as triangles in `makeVertices`; the rectangle is two triangles (six
vertices). Each `Vertex` contains a 2D position and RGB color.

The vertex shader transforms each point with the `pan` and `zoom` uniforms. The
fragment shader receives the interpolated color and writes a pixel. To add
another shape, append triangle vertices, increase the VBO capacity and draw
count, or use an index buffer (`GL_ELEMENT_ARRAY_BUFFER`) to reuse vertices.

The important coordinate systems are:

- GTK mouse coordinates: origin at the top-left, Y increases downward.
- OpenGL normalized device coordinates: `(-1, -1)` at bottom-left and `(1, 1)`
  at top-right.
- Framebuffer coordinates: pixels passed to `glViewport`; these include the
  GTK scale factor on high-DPI displays.

`mouseMotion` shows the conversion from GTK coordinates to OpenGL coordinates.
It also reverses the pan/zoom transform so the marker stays below the pointer.

## Useful experiments

- Animate a uniform and call `gtk_gl_area_queue_render` from a GTK tick callback.
- Add alpha blending with `glEnable(GL_BLEND)` and `glBlendFunc` bindings.
- Add an element/index buffer to avoid repeating rectangle vertices.
- Pass a projection matrix uniform instead of separate pan/zoom uniforms.
- Generate circle vertices with `sin`/`cos`, forming triangles around a center.
- Add textures using `glTexImage2D`, texture coordinates, and a sampler uniform.

OpenGL calls must only happen while the `GtkGLArea` context is current. GTK
guarantees that in `render` and `resize`; `unrealize` calls
`gtk_gl_area_make_current` explicitly before deleting resources.
