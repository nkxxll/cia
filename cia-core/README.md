# cia-core

Headless source analysis for Zig 0.16. No GTK or OpenGL dependencies.
Currently scans regular `.zig` files, skips symlinks and common generated
folders, and counts physical lines (including an unterminated final line).

From this directory:

```sh
zig build       # zig-out/lib/libcia-core.so and zig-out/include/cia_core.h on Linux
zig build test  # analysis tests and a C client linked against the shared library
```

## Zig clients

Add `.cia_core = .{ .path = "../cia-core" }` to your `build.zig.zon`
dependencies (adjust the path for your project). In `build.zig`:

```zig
const core = b.dependency("cia_core", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("cia-core", core.module("cia-core"));
```

Import `@import("cia-core")`. Public exports are `LineCounter`, `FileLines`,
`LinesModel`, `scan`, and `scanCancelable`. The caller supplies an allocator,
`std.Io`, and a directory opened with `.iterate = true`. The caller keeps
ownership of that directory and must call `model.deinit()` on the returned
result. Cancellation uses `?*const std.atomic.Value(bool)` and returns
`error.Cancelled`, without publishing a partial result. Per-file failures
increment `warning_count`; paths are owned, relative to the scan root, and
ordered breadth-first with lexical ordering within each directory.

Importing the Zig module does not require building or linking the C library.

## C, C++, and Qt clients

Include `cia_core.h` and link `-lcia-core` using the installed include/library
directories. Make the shared library available to the runtime loader through
your application's installation or rpath. The header supports C++ directly.

```cpp
cia_core_result *result = nullptr;
if (cia_core_scan("/path/to/project", &result) == CIA_CORE_OK) {
    for (size_t i = 0; i < cia_core_result_file_count(result); ++i) {
        cia_core_file file;
        if (cia_core_result_file(result, i, &file) == CIA_CORE_OK) {
            // file.path contains file.path_length bytes, not a C string.
            // Copy the bytes if they must outlive result.
        }
    }
    cia_core_result_destroy(result);
}
```

Scanning is synchronous: call it from a worker thread in a GUI. Results are
immutable and may be read concurrently, but destruction must wait for readers.
No Zig allocator or IO object crosses the C boundary; free results only with
`cia_core_result_destroy`. The C adapter currently has no cancellation or
progress API and returns coarse status codes; use `warning_count` to detect
partial read failures. This initial API is not yet a versioned ABI guarantee.
