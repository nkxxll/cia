# Code Inspection and Analysis

... not what you think.

## Build and packages

Requires Zig 0.16; the frontend also requires GTK 4 and libepoxy development
files and pkg-config.

```sh
zig build               # install cia, the core shared library, and its C header
zig build run -- lines  # open the LOC treemap for the working directory
zig build test          # all headless tests, including the C ABI integration test
```

- [cia-core](cia-core/README.md): standalone analysis module and shared library
  for Zig, C/C++, Qt, and other frontends. Build it without GTK using
  `cd cia-core && zig build`.
- [cia-opengl](cia-opengl/README.md): GTK/OpenGL application, with cia-core as a
  Zig package dependency and a separate pure treemap layout module.

See [the package boundary](docs/core-ui-split.md) for API and ownership details.

## Mission statement

For me to go deeper into systems programming. I am familiar with memory
management and programming language interpreters now (by literally building
multiple interpreters with garbage collectors and multiple isolated garbage
collectors). Now I want to dive deeper into how systems programming with
graphics elements works while leveraging `iouring` on Linux and `kqueue` on
Mac. The problem is also the problem of my masters thesis and I am too eager to
make the analysis program better with what I have learned from the thesis. Is
this project useful for anyone but me? Probably not, but many useful projects
start like this and I do not strive to make the next code analysis tool that
everyone uses, I strive to learn something that will help me get better at what
I love doing. So now that we have this done what is the MVP what has to work
before I eventually abandon this project like the other 500+ projects in my
GitHub graveyard 🪦.

## Requirements

The first release should provide a reliable end-to-end workflow for exploring a
source tree:

- Launch with a project directory, either positionally or with `--project`.
- Support `--help`, `--no-scan`, and deterministic development state/fixture
  options. Invalid command-line input must fail before GTK starts.
- Select a project directory through a GTK directory chooser and rescan it
  without blocking the UI.
- Recursively discover regular files while skipping symlinks and common
  generated, dependency, cache, and version-control directories.
- Allow scans to be cancelled and replace displayed results atomically when
  complete.
- Continue scanning when individual files are unreadable, disappear, contain
  invalid text, or are excluded; report these cases as diagnostics.
- Classify supported source files by extension or filename, excluding binary
  and overly large files by default.
- Calculate file size, physical lines of code, blank lines, comment lines, and
  a basic code/blank/comment/mixed classification.
- Aggregate file counts, byte sizes, and line metrics for every directory.
- Display the project as an interactive treemap with areas based on LOC, bytes,
  or file count.
- Distinguish files from directories, show item paths and metric values on
  hover, and support selection, details, directory zoom, and navigation back.
- Keep colors meaningful and documented; visual color must not be the only way
  to distinguish items.
- Open a selected file in Neovim using a configurable argv-style command,
  without blocking GTK or invoking a shell.

The application must remain responsive during scanning and processing, use
deterministic results for identical inputs, handle platform-supported arbitrary
filesystem paths safely, release scan allocations, and keep analyzer and
treemap layout code testable without GTK or an active OpenGL context.

The MVP is complete when a user can launch `cia .` (or another project
path), see a responsive OpenGL treemap sized by LOC, inspect and navigate the
result, safely cancel or rescan, and open a selected file in Neovim.
