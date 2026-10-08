# Automating Tasks with Just

Running a logreader or rendering a graph involves binary names, features, and
paths. A `justfile` gives those commands short names so you can spend your time
changing the robot instead of reconstructing command lines.

This chapter uses the 1.3.0-dev templates and assumes `just` is available.
Start in the project directory from [Setting Up](./setup.md), or the workspace
root from [From Project to Workspace](./workspace.md). Run `just --list` to see
the recipes your generated project provides.

## Read a recording in two commands

After running the application once, use:

```sh
just log
just cl
```

`log` reconstructs the structured text with the producing build's string index.
`cl` exports each recorded CopperList, including task payloads and timestamps.
For the first project, look for the source value `42` and processing value `43`.
Both commands default to the application's normal log path.

For a different recording in a single-crate project:

```sh
just cl logs/another-session.copper
```

In the workspace template, the first argument selects the application and the
second selects its recording:

```sh
just cl cu_example_app apps/cu_example_app/logs/cu_example_app.copper
```

Recipe arguments are positional. When you target another app, provide its log
path too; the default log path still names `cu_example_app`.

## See the graph and the execution schedule

The graph answers “what connects to what?” The schedule answers “where and in
what order will that work execute?” Both views help you check a RON edit before
running hardware.

From either template's root:

```sh
just graph
just sched
```

The recipes open SVG files in your default viewer. In a single-crate project,
the outputs are `graph.svg` and `schedule.svg`. In the workspace template they
are `apps/cu_example_app/graph.svg` and
`apps/cu_example_app/schedule.svg`.

For our three-task app, the graph shows `src -> t-0 -> sink`. Its default serial
schedule runs those operations on one worker. After selecting the
[Pipeline planner](./performance-basics.md#select-a-pipeline-plan), inspect the
schedule to see the process stages placed on separate workers and CopperLists
overlapping across stages.

Resource tables list the consumers of each resource, including configured
LogStream transports. A destination using `network.tx`, for example, appears as
`system: logstream (ground)` in the **Used by** column. Use this to check shared
hardware ownership alongside the task graph.

### Add observed timing

A schedule diagram explains placement and ordering; it does not establish how
fast your app runs. Record a representative run, then add its measured timings:

```sh
just graph-log
just sched-log
```

These recipes use the application's logreader to obtain statistics from its
normal log. Keep the log and configuration from the same application version.
Look for an expensive stage or a large gap between stages, then use the
[performance chapters](./reading-performance-metrics.md) to investigate it.

### Target another configuration

In a single-crate project, render an alternate configuration without replacing
your application config:

```sh
just graph copperconfig.ron graph-check.svg
just sched copperconfig.ron schedule-check.svg
```

In a workspace, supply the app, config, and output paths:

```sh
just graph cu_example_app apps/cu_example_app/copperconfig.ron graph-check.svg
just sched cu_example_app apps/cu_example_app/copperconfig.ron schedule-check.svg
```

The first argument is the Cargo application package name. Both templates also
provide a Rust viewer helper for additional options, including mission
selection. For example, in the workspace from the
[missions exercise](./missions.md), select `normal` with:

```sh
cargo run -p cu29-view-helper -- schedule --app cu_example_app --mission normal --output schedule-normal.svg --open
```

Use a mission ID that your selected app actually declares.

## Replay a failure

The generated recipes run replay through the `debug-optimized` Cargo profile:

```sh
just resim
just resim-debug
```

`resim` replays the recording. `resim-debug` serves a replay session to a remote
debug client. Compiler optimization keeps seeking practical while preserving
Copper's debug logs, assertions, and debugger information. See
[Logging and Replaying Data](./logging-replay.md) for the replay workflow.

## Automate your own repeated commands

A recipe is a name followed by indented shell commands. In the workspace
`justfile`, add this complete recipe:

```just
run:
  cargo run -p cu_example_app
```

Then run:

```sh
just run
```

It starts the same application you would launch with the Cargo command. Use
`just` for operations you repeat, keeping explicit arguments for the paths and
applications that change.
