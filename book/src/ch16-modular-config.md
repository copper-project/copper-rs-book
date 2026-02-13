# Modular Configuration

In the previous chapter we saw how a workspace separates **code** into multiple crates.
But what about the configuration? As your robot grows, a single `copperconfig.ron` with
dozens of tasks and connections becomes hard to read and maintain. What if you have two
motors that use the same driver with different parameters? You'd have to duplicate the
task entry and hope you keep them in sync.

Copper solves this with **modular configuration**: the ability to split your RON file into
smaller pieces and compose them with parameter substitution.

## The `includes` section

The key feature is the `includes` array at the top level of `copperconfig.ron`. Each entry
specifies a path to another RON file and an optional set of parameters:

```ron
(
    tasks: [],
    cnx: [],
    includes: [
        (
            path: "sensor.ron",
            params: { "id": "front", "pin": 4 },
        ),
    ],
)
```

When Copper processes this configuration, it reads `sensor.ron`, substitutes the
parameters, and merges the resulting tasks and connections into the main configuration.

## Parameter substitution with `{{param}}`

Inside an included file, parameters are referenced using double curly braces:

```ron
// sensor.ron
(
    tasks: [
        (
            id: "sensor_{{id}}",
            type: "tasks::SensorDriver",
            config: { "pin": {{pin}} },
        ),
    ],
    cnx: [],
)
```

When included with `params: { "id": "front", "pin": 4 }`, this expands to:

```ron
(
    tasks: [
        (
            id: "sensor_front",
            type: "tasks::SensorDriver",
            config: { "pin": 4 },
        ),
    ],
    cnx: [],
)
```

The `{{id}}` becomes `front` and `{{pin}}` becomes `4`. Simple text substitution --
it works in task IDs, config values, message types, or anywhere else in the RON file.

## Reusing the same file with different parameters

The real power shows up when you include the **same file multiple times** with different
parameters. This is the robotics equivalent of "instantiate the same component twice with
different settings."

Consider a robot with two motors -- left and right. They use the same driver code, but
different GPIO pins:

```ron
// motors.ron
(
    tasks: [
        (
            id: "motor_{{id}}",
            type: "tasks::MotorDriver",
            config: { "pin": {{pin}}, "direction": "{{direction}}" },
        ),
    ],
    cnx: [],
)
```

In your main configuration, include it twice:

```ron
(
    tasks: [],
    cnx: [],
    includes: [
        (
            path: "motors.ron",
            params: { "id": "left",  "pin": 4, "direction": "forward" },
        ),
        (
            path: "motors.ron",
            params: { "id": "right", "pin": 5, "direction": "reverse" },
        ),
    ],
)
```

This produces two tasks: `motor_left` on pin 4 and `motor_right` on pin 5. One file
defines the motor pattern; the main config just says "give me two of them with these
settings."

## A complete example

Here's a more realistic configuration that combines local tasks, included subsystems,
monitoring, and logging:

```ron
(
    tasks: [
        (
            id: "planner",
            type: "tasks::PathPlanner",
        ),
    ],
    cnx: [
        (
            src: "sensor_front",
            dst: "planner",
            msg: "crate::messages::SensorData",
        ),
        (
            src: "sensor_rear",
            dst: "planner",
            msg: "crate::messages::SensorData",
        ),
        (
            src: "planner",
            dst: "motor_left",
            msg: "crate::messages::MotorCommand",
        ),
        (
            src: "planner",
            dst: "motor_right",
            msg: "crate::messages::MotorCommand",
        ),
    ],
    monitor: ( type: "cu_consolemon::CuConsoleMon" ),
    logging: (
        slab_size_mib: 1024,
        section_size_mib: 100,
    ),
    includes: [
        (
            path: "sensor.ron",
            params: { "id": "front", "pin": 2 },
        ),
        (
            path: "sensor.ron",
            params: { "id": "rear", "pin": 3 },
        ),
        (
            path: "motors.ron",
            params: { "id": "left",  "pin": 4, "direction": "forward" },
        ),
        (
            path: "motors.ron",
            params: { "id": "right", "pin": 5, "direction": "reverse" },
        ),
    ],
)
```

The main config file focuses on **architecture** -- how subsystems connect to each other.
The included files focus on **component definition** -- what a sensor or motor looks like.
The connections in the main file reference tasks by their expanded IDs (`sensor_front`,
`motor_left`), which are predictable from the template + parameters.

## Recursive includes

Included files can themselves include other files. This lets you build hierarchical
configurations:

```text
copperconfig.ron
├── includes left_arm.ron
│   ├── includes shoulder_motor.ron
│   └── includes elbow_motor.ron
└── includes right_arm.ron
    ├── includes shoulder_motor.ron
    └── includes elbow_motor.ron
```

Each level can pass different parameters down, so `shoulder_motor.ron` is written once but
instantiated four times (left shoulder, left elbow, right shoulder, right elbow) -- each
with its own pin assignments and IDs.

## Where to put included files

There's no strict rule, but a common convention in workspace projects is to keep included
RON files next to the main `copperconfig.ron`:

```text
apps/cu_example_app/
├── copperconfig.ron        # Main config (includes the others)
├── sensor.ron              # Sensor subsystem template
├── motors.ron              # Motor subsystem template
└── src/
    └── ...
```

For very large projects, you might create a `config/` subdirectory and use relative paths
in the includes:

```ron
includes: [
    ( path: "config/sensor.ron", params: { ... } ),
]
```

## Difference with ROS

In ROS 2, configuration reuse is handled through **launch file composition** and
**YAML parameter files**. You can include other launch files and remap parameters:

```python
# ROS 2: composing launch files
IncludeLaunchDescription(
    PythonLaunchDescriptionSource('motor_launch.py'),
    launch_arguments={'motor_id': 'left', 'pin': '4'}.items(),
)
```

Copper's approach is similar in spirit but different in execution:

| | ROS 2 | Copper |
|---|---|---|
| **Format** | Python launch files + YAML | RON files with `{{param}}` substitution |
| **Reuse** | `IncludeLaunchDescription` | `includes` array in RON |
| **Parameters** | Launch arguments + YAML files | `params` map with text substitution |
| **Validation** | Runtime | Compile time |
| **Nesting** | Launch files can include other launch files | RON files can include other RON files |

The main advantage of Copper's approach is simplicity: it's just text substitution in a
declarative format. No Python logic, no conditionals, no `if/else` chains. The included
file is a template, the parameters fill in the blanks, and the result is a flat list of
tasks and connections that Copper validates at compile time.

## Further reading

- [Modular Configuration](https://copper-project.github.io/copper-rs/Modular-Configuration/)
  in the official Copper documentation.
- [Configuration reference](https://copper-project.github.io/copper-rs/Copper-Configuration-file-Reference/)
  for the full RON schema.
- `examples/modular_config_example/` in the
  [copper-rs repository](https://github.com/copper-project/copper-rs) for a working
  example.
