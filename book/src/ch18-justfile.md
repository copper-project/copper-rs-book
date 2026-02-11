# Automating Tasks with Just

Throughout this book, we've been typing long `cargo` commands to run the logreader, extract
CopperLists, and more. Those commands are precise but tedious -- especially when they
involve feature flags, binary names, and multiple path arguments.

The workspace template ships with a `justfile` that wraps common operations into short,
memorable commands. In this chapter, we'll see what `just` is, what recipes come built-in,
and how to visualize the task graph.

## What is Just?

[Just](https://just.systems/) is a command runner -- think of it as a modern, simpler
alternative to `make` for project automation. You define **recipes** (named commands) in a
`justfile`, then run them with `just <recipe>`.

### Installing Just

If you don't have it already:

```bash
cargo install just
```

Or on most Linux distributions:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | \
    bash -s -- --to ~/bin
```

Verify with:

```bash
just --version
```

## The workspace justfile

Here's the `justfile` that comes with the `cu_full` workspace template:

```just
# Render the execution DAG from the app config.
rcfg:
  #!/usr/bin/env bash
  set -euo pipefail
  APP_DIR="${APP_DIR:-cu_example_app}"
  ../../target/debug/cu29-rendercfg apps/"${APP_DIR}"/copperconfig.ron --open

# Extract the structured log via the log reader.
log:
  #!/usr/bin/env bash
  set -euo pipefail
  APP_DIR="${APP_DIR:-cu_example_app}"
  APP_NAME="${APP_NAME:-${APP_DIR}}"
  RUST_BACKTRACE=1 cargo run -p "${APP_NAME}" --features=logreader \
    --bin "${APP_NAME}-logreader" \
    apps/"${APP_DIR}"/logs/"${APP_NAME}".copper \
    extract-text-log target/debug/cu29_log_index

# Extract CopperLists from the log output.
cl:
  #!/usr/bin/env bash
  set -euo pipefail
  APP_DIR="${APP_DIR:-cu_example_app}"
  APP_NAME="${APP_NAME:-${APP_DIR}}"
  RUST_BACKTRACE=1 cargo run -p "${APP_NAME}" --features=logreader \
    --bin "${APP_NAME}-logreader" \
    apps/"${APP_DIR}"/logs/"${APP_NAME}".copper extract-copperlists
```

Three recipes, each wrapping a command we'd otherwise have to type (or remember) by hand.

## The recipes

### `just log` -- Extract text logs

Remember in [Chapter 13](./ch13-logging-replay.md) when we ran this?

```bash
cargo run --features logreader --bin my-project-logreader -- \
    logs/my-project.copper extract-text-log target/debug/cu29_log_index
```

In the workspace, that becomes:

```bash
just log
```

It extracts the structured text logs (`debug!()`, `info!()`, etc.) from the `.copper` file
and reconstructs the human-readable output using the compile-time string index.

### `just cl` -- Extract CopperLists

Also from Chapter 13, extracting CopperList data (the message payloads from every cycle)
was:

```bash
cargo run --features logreader --bin my-project-logreader -- \
    logs/my-project.copper extract-copperlists
```

Now it's just:

```bash
just cl
```

### `just rcfg` -- Render the task graph

This is the new one. Copper includes a tool called `cu29-rendercfg` that reads your
`copperconfig.ron` and generates a visual diagram of the task graph -- an SVG showing
all tasks and their connections as a directed acyclic graph (DAG).

Let's try it on our workspace.

Then, from the `my_workspace/` directory:

```bash
just rcfg
```

This renders the DAG from `apps/cu_example_app/copperconfig.ron` and opens it in your
default browser. You'll see a diagram like:

```text
┌─────────┐     ┌─────────┐     ┌─────────┐
│   src   │────▶│   t-0   │────▶│  sink   │
└─────────┘     └─────────┘     └─────────┘
```

For our simple three-task pipeline, the diagram is straightforward. But as your robot
grows to 10, 20, or 50 tasks with complex wiring, this visualization becomes invaluable
for understanding the data flow at a glance.

## Targeting a different app

All three recipes default to `cu_example_app`. If your workspace has multiple applications,
override the target with environment variables:

```bash
APP_DIR=my_other_app just log
APP_DIR=my_other_app just cl
APP_DIR=my_other_app just rcfg
```

The `APP_DIR` variable controls which app directory to look in, and `APP_NAME` (which
defaults to `APP_DIR`) controls the binary and package name passed to `cargo`.

## Adding your own recipes

The `justfile` is yours to extend. Here are some recipes you might add as your project
evolves:

```just
# Run the main application.
run:
  cargo run -p cu_example_app

# Run with the console monitor enabled.
run-mon:
  cargo run -p cu_example_app -- --monitor

# Build everything in release mode.
release:
  cargo build --release

# Clean build artifacts and log files.
clean:
  cargo clean
  rm -f apps/*/logs/*.copper
```

Recipes are just shell commands with names. If you find yourself typing the same command
twice, make it a recipe.

## Why not make?

You could use `make` for all of this, and some people do. `just` has a few advantages for
this use case:

- **No tabs-vs-spaces headaches** -- `just` uses consistent indentation rules.
- **No implicit rules** -- every recipe is explicit. No "magic" `.PHONY` targets.
- **Variables and defaults** -- `just` supports environment variable defaults natively
  (the `${APP_DIR:-cu_example_app}` syntax).
- **Cross-platform** -- works the same on Linux, macOS, and Windows.
- **No build system baggage** -- `just` is purely a command runner, not a build system.
  Cargo is already your build system.
