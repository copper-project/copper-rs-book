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

## The workspace recipes

The `cu_full` workspace template includes recipes for inspecting logs, extracting
CopperLists, and visualizing both the task graph and generated process schedule. Run
`just --list` in the workspace to see the recipes available in your version of the
template.

## The recipes

### `just log` -- Extract text logs

Remember in [Logging and Replaying Data](./logging-replay.md) when we ran this?

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

Also from [Logging and Replaying Data](./logging-replay.md), extracting CopperList data (the message payloads from every cycle)
was:

```bash
cargo run --features logreader --bin my-project-logreader -- \
    logs/my-project.copper extract-copperlists
```

Now it's just:

```bash
just cl
```

### `just dag` -- Render the task graph

This is the new one. Copper includes a tool called `cu29-rendercfg` that reads your
`copperconfig.ron` and generates a visual diagram of the task graph -- an SVG showing
all tasks and their connections as a directed acyclic graph (DAG).

Let's try it on our workspace.

Then, from the `my_workspace/` directory:

```bash
just dag
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

### `just plan` -- Render the generated process schedule

`just plan` answers a different question from `just dag`: it renders the exact process
schedule generated for each CopperList. Both projections use the same scheduler lanes: serial has
one main CopperList worker, while `parallel-rt` staggers CopperLists across generated stage workers.
Background gateways point into aligned named-pool worker lanes in both views; their open-ended bars
show jobs that may remain active across later CopperLists. Large configured depths show a readable
six-CopperList window (`CL n` through `CL n+5`) while preserving the real depth in the header.
Repeated configured resource targets are highlighted, including background jobs and skew outside
the nominal diagonal. Equal-width columns represent ordinal order, not elapsed time.

All missions are stacked by default. Select a mission or resolve conditional config fragments
with recipe arguments:

```bash
just plan mission=autonomous
just plan features=camera,mock
just plan log=apps/cu_example_app/logs/cu_example_app.copper
just plan-log
```

Resource bindings on cards are annotations, not claims that the scheduler reserves or locks
those resources.

With `log=...`, the typed logreader appends typical and slowest CopperList timelines. Recorded
task durations are packed back-to-back as proportional, hoverable segments; carried-forward slots
outside the current execution cluster are excluded so stale timestamps do not flatten the chart.
`just plan-log` selects the project's default log, logreader, required features, and recorded mission
automatically.
The bars are recorded `process_time` intervals. Overlapping intervals sharing a declared resource
are potential contention, not proof of lock waiting. Serialization is not timestamped, so residual
gaps remain unclassified and may also include rate limiting, scheduling, and I/O.

## Targeting a different app

These recipes default to `cu_example_app`. If your workspace has multiple applications,
override the target with environment variables:

```bash
APP_DIR=my_other_app just log
APP_DIR=my_other_app just cl
APP_DIR=my_other_app just dag
APP_DIR=my_other_app just plan
```

The `APP_DIR` variable controls which app directory to look in, and `APP_NAME` (which
defaults to `APP_DIR`) controls the binary and package name passed to `cargo`.

`just rcfg` still works as a compatibility alias, but `just dag` is the current primary
name in the generated template.

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
