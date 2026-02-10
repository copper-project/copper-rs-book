# Advanced Configuration

In the [Task Graph](./ch05-task-graph.md) chapter we covered the `tasks` and `cnx`
sections of `copperconfig.ron`. Those two are all you need to get started, but real-world
projects often use additional top-level sections to configure monitoring, logging, runtime
behavior, missions, and modular composition.

This chapter gives an overview of each.

## Monitoring

The optional `monitor` section selects a monitoring component that observes every cycle of
the runtime. The most common choice is the console monitor, which prints live task status
to the terminal:

```ron
monitor: (
    type: "cu_consolemon::CuConsoleMon",
    config: { "verbosity": 2 },
),
```

The `type` field references a Rust type that implements the `CuMonitor` trait, and
`config` passes key-value parameters to its constructor -- just like task `config` blocks.

## Logging

The `logging` section tunes Copper's unified structured logger. These options mirror the
`LoggingConfig` struct defined in `cu29-runtime`:

| Field | Description | Default |
|---|---|---|
| `enable_task_logging` | Controls per-task message logging | `true` |
| `slab_size_mib` | Size of each memory-mapped slab in MiB | -- |
| `section_size_mib` | Pre-allocated size per log section in MiB | -- |
| `keyframe_interval` | Number of CopperLists between two state snapshots (keyframes) | `100` |

Example:

```ron
logging: (
    slab_size_mib: 1024,
    section_size_mib: 100,
),
```

The runtime validates that `section_size_mib` does not exceed `slab_size_mib`.

> **Tip**: If your log files are growing too large, reduce the slab size or disable logging
> on high-frequency tasks using the per-task `logging: (enabled: false)` option described
> in the [Task Graph](./ch05-task-graph.md) chapter.

## Runtime settings

Runtime behavior can be adjusted with the `runtime` section. Currently the main option is
`rate_target_hz`, which acts as a rate limiter for CopperList execution:

```ron
runtime: (
    rate_target_hz: 2,
),
```

This tells the runtime to target 2 full cycles per second. Without it, the runtime runs
as fast as possible.

## Missions

Configurations can define multiple **missions**, each representing an alternative variant
of the task graph. A mission is simply an ID:

```ron
missions: [ (id: "A"), (id: "B") ],
```

Tasks and connections can then specify a `missions` array to indicate which missions they
belong to. Only the tasks and connections matching the active mission are instantiated.

This is useful when the same robot codebase supports multiple operating modes (e.g.,
"indoor" vs "outdoor", "simulation" vs "hardware") and you want to swap configurations
without recompiling.

See `examples/cu_missions/copperconfig.ron` in the Copper RS repository for a complete
example.

## Modular configuration

As your robot grows, a single `copperconfig.ron` can get unwieldy. Copper supports
**composition** of configurations via the `includes` section. Each include specifies a
path to another RON file and optional parameter substitutions:

```ron
includes: [
    (
        path: "base.ron",
        params: { "id": "left", "pin": 4 },
    ),
],
```

Inside `base.ron`, parameters are substituted using the `{{param}}` syntax:

```ron
// base.ron
(
    tasks: [
        (
            id: "motor_{{id}}",
            type: "tasks::MotorDriver",
            config: { "pin": {{pin}} },
        ),
    ],
    cnx: [],
)
```

This would expand to a task with `id: "motor_left"` and `config: { "pin": 4 }`.

Includes are processed recursively, so included files can themselves include other files.

### Full example

Here's a more complete configuration demonstrating several of these features together:

```ron
(
    tasks: [],
    cnx: [],
    monitor: ( type: "cu_consolemon::CuConsoleMon" ),
    logging: (
        slab_size_mib: 1024,
        section_size_mib: 100,
    ),
    includes: [
        ( path: "base.ron", params: {} ),
        ( path: "motors.ron", params: { "id": "left",  "pin": 4, "direction": "forward" } ),
        ( path: "motors.ron", params: { "id": "right", "pin": 5, "direction": "reverse" } ),
    ],
)
```

This keeps each subsystem in its own file and reuses `motors.ron` twice with different
parameters -- one for the left motor and one for the right.

## Further reading

- [Modular Configuration](https://copper-project.github.io/copper-rs/Modular-Configuration/)
  in the official Copper documentation.
- [Configuration reference](https://copper-project.github.io/copper-rs/Copper-Configuration-file-Reference/)
  for the full RON schema.
- `examples/cu_missions/` and `examples/modular_config_example/` in the
  [Copper RS repository](https://github.com/copper-project/copper-rs) for working examples.
