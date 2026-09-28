# cia-opengl

GTK 4 / OpenGL frontend for CIA, using Zig 0.16 and the sibling `cia-core`
package through a local dependency in `build.zig.zon` and `b.dependency` in
`build.zig`. Requires GTK 4 and libepoxy development files plus pkg-config.

From this directory:

```sh
zig build
zig build run -- lines
zig build test
```

The executable remains named `cia`. `lines` scans the working directory;
without arguments the application opens its home screen.
Tests cover CLI parsing and pure treemap layout without linking GTK or OpenGL.
Run `zig build test` in `../cia-core` for analysis and shared-library tests,
or at the repository root for both suites.

`src/layout` exports the pure `layout` module (`Rect`, `Tile`, `layout`).
Application code owns scan threads, cancellation and result handoff, LOC-to-weight
conversion, interaction, and rendering. Core analysis never imports UI code.

The local dependency expects the two package directories to remain siblings.
For separate distribution, publish cia-core and replace the dependency path
with its package URL and hash.
