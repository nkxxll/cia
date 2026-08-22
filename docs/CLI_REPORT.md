# CLI Report

## Overview

The two files form a two-stage CLI system:

```text
argv
  -> flags.zig
  -> raw CLIArgs structures
  -> cli.zig validation/conversion
  -> normalized Command structures
  -> application logic
```

`flags.zig` is a generic reflection-based argument parser. `cli.zig` defines TigerBeetle’s actual commands, options, defaults, and domain-specific validation.

## `src/flags.zig`

### Purpose

`flags.zig` provides a reusable parser driven entirely by Zig structs and unions. The struct definition becomes the CLI specification.

For example:

```zig
const Args = struct {
    verbose: bool = false,
    count: u32,

    @"--": void,
    path: []const u8,
};
```

This accepts:

```text
--verbose
--count=10
file.txt
```

Field names are converted automatically:

```text
foo_bar -> --foo-bar
```

### Commands and subcommands

A top-level `union(enum)` represents commands:

```zig
const CLIArgs = union(enum) {
    start: StartArgs,
    version: VersionArgs,
};
```

The first argument selects the union case:

```text
program start ...
program version ...
```

Nested unions create nested subcommands. `-h` and `--help` are recognized only when the union defines a public `help` constant.

### Named options

Named options must appear before the positional arguments and use long-option syntax:

```text
--addresses=127.0.0.1:3000
--replica=1
--verbose
```

Values must use `=`. This is rejected:

```text
--replica 1
```

Boolean fields are special:

```zig
verbose: bool = false
```

They accept:

```text
--verbose
--verbose=true
--verbose=false
```

All options are checked for duplicates. Repeating an option is fatal.

### Supported value types

The parser supports:

- `bool`
- unsigned integer types
- `[]const u8`
- `[:0]const u8`
- exhaustive enums
- optional versions of supported types
- custom types implementing `parse_flag_value`

Integer parsing supports separators such as:

```text
--count=1_000
```

Leading zeroes and signed values are rejected.

### Positional arguments

The special field:

```zig
@"--": void,
```

separates named options from positional arguments.

Example:

```zig
struct {
    verbose: bool = false,

    @"--": void,
    path: []const u8,
}
```

The parser requires:

```text
program --verbose file.dat
```

Positional arguments cannot begin with `-`. The literal `--` is not a general positional-argument separator in this mode.

Optional positional arguments must come after required positional arguments.

### Arbitrary trailing arguments

A field of type:

```zig
rest: []const []const u8
```

after `@"--"` enables arbitrary trailing arguments:

```zig
struct {
    @"--": void,
    rest: []const []const u8,
}
```

The extra arguments must be introduced with a literal `--`:

```text
program -- arg1 arg2
```

### Memory and errors

`Flags` owns an `ArenaAllocator`. Argument strings are allocated or retained in this arena, so the arena must remain alive while parsed values are used.

Errors are fatal rather than returned:

```text
error: --replica: argument is required
```

The process exits with status `1`.

This makes the parser simple to call, but less reusable in libraries or tests because parsing failures terminate the process.

### Important behavior when modifying it

The parser intentionally does not provide:

- short options other than `-h`
- automatic help generation
- typo correction
- `--key value` syntax
- error propagation through Zig’s `try`

The parser also matches options by prefix, then relies on sorting longer field names first. Therefore, adding similarly named flags requires care.

## `src/cli.zig`

### Purpose

`cli.zig` contains the application-specific CLI definition and validation. It is not the low-level parser.

It has two representations:

```text
CLIArgs
  Raw values directly parsed from argv

Command
  Validated and normalized values used by the rest of the program
```

### `CLIArgs`

`CLIArgs` defines the user-facing command structure.

Current top-level commands are:

- `format`
- `recover`
- `start`
- `version`
- `repl`
- `benchmark`
- `inspect`
- `multiversion`
- `amqp`

Each command has its own struct. Required values have no default:

```zig
replica_count: u8,
```

Optional values use defaults:

```zig
cluster: ?u128 = null,
```

Boolean options default to `false`:

```zig
development: bool = false,
```

The help text is manually written in `CLIArgs.help`.

### `parse_args`

The public entry point is:

```zig
pub fn parse_args(flags: *stdx.Flags) Command
```

It first invokes the generic parser:

```zig
const cli_args = flags.parse(CLIArgs);
```

Then it dispatches to a command-specific conversion function:

```zig
.format => parse_args_format(...)
.start => parse_args_start(...)
```

### Command-specific validation

The conversion functions perform checks that cannot be expressed by the generic parser.

Examples include:

- replica count ranges
- mutually exclusive options
- required combinations of options
- address and port validation
- memory limits
- cache size calculations
- timeout constraints
- deprecated option handling
- experimental-option gating

For example, `start` rejects experimental flags unless:

```text
--experimental
```

is provided.

The raw parser only knows that a value is a `u32` or `ByteSize`. `cli.zig` knows whether that value makes sense for TigerBeetle.

### Normalization

`Command` converts user input into forms convenient for the application.

Examples:

- byte sizes become cache entry counts
- millisecond timeouts become internal ticks
- addresses become parsed socket addresses
- `--aof` becomes a generated `<path>.aof`
- memory is split into individual cache sizes
- defaults are selected based on development or production mode

This is why application code should generally consume `Command`, not `CLIArgs`.

## How To Modify The CLI

### Add a new command

1. Add a struct inside `CLIArgs`.
2. Add a union field for the command.
3. Add a corresponding struct inside `Command`.
4. Add a dispatch case in `parse_args`.
5. Implement a `parse_args_<command>` function.
6. Update the hand-written help text.

### Add a simple option

Add a field to the relevant `CLIArgs` struct:

```zig
dry_run: bool = false,
```

or:

```zig
output: ?[]const u8 = null,
```

The parser automatically exposes these as:

```text
--dry-run
--output=value
```

If the value has application-specific constraints, validate it in the corresponding `parse_args_*` function.

### Make an option required

Remove its default:

```zig
replica_count: u8,
```

The generic parser will report an error if it is missing.

### Add a custom value type

Define `parse_flag_value` on the type. This is appropriate for addresses, sizes, ratios, or structured values. The function must return a statically allocated diagnostic ending in `:` when parsing fails.

### Change defaults

There are two kinds of defaults:

- Syntax-level defaults: fields such as `verbose: bool = false`
- Application defaults: values calculated in `cli.zig`, such as production cache sizes

Change the first kind in `CLIArgs`. Change the second kind in the `StartDefaults` or related validation code.

## Current Project Caveat

These files are still TigerBeetle-specific and are not currently integrated with this GTK application:

- `main.zig` does not call `cli.parse_args`
- `cli.zig` imports TigerBeetle-specific `vsr` modules
- `flags.zig` imports `stdx.zig`, which is not present in the listed `src` files
- `cli.zig` depends on TigerBeetle types such as `ClusterAddress`, `ByteSize`, `Operation`, and internal constants

Therefore, the first practical modification step is to decide whether to:

1. Keep the generic parser and replace `cli.zig` completely, or
2. Port the TigerBeetle command model and dependencies into this project.

For a GTK application, keeping the parsing concepts from `flags.zig` but simplifying `cli.zig` is likely the cleanest approach.
