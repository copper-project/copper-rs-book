# Advanced Configuration

In the [Task Graph](./ch05-task-graph.md) chapter we covered the `tasks` and `cnx`
sections of `copperconfig.ron`. Those two are all you need to get started, but real-world
projects often use additional top-level sections to configure monitoring, logging, runtime
behavior, missions, and modular composition.

This chapter gives an overview of each.

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
