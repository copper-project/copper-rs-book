# The Task Graph: copperconfig.ron

The file `copperconfig.ron` is the heart of your robot's architecture. It defines **what
tasks exist**, **how they connect**, and **what parameters they receive**. Copper reads
this file at compile time to generate a deterministic scheduler.

The format is [RON](https://github.com/ron-rs/ron) (Rusty Object Notation) -- a
human-readable data format designed for Rust.

## The complete example

Here is the `copperconfig.ron` from our template project:

```ron
(
    tasks: [
        (
            id: "src",
            type: "tasks::MySource",
        ),
        (
            id: "t-0",
            type: "tasks::MyTask",
        ),
        (
            id: "sink",
            type: "tasks::MySink",
        ),
    ],
    cnx: [
        (
            src: "src",
            dst: "t-0",
            msg: "crate::tasks::MyPayload",
        ),
        (
            src: "t-0",
            dst: "sink",
            msg: "crate::tasks::MyPayload",
        ),
    ],
)
```

This defines a three-task pipeline:

```text
MySource  ──▶  MyTask  ──▶  MySink
  "src"        "t-0"        "sink"
```

We will discuss these 3 traits (Source, Task, Sink) later.  
For the moment, let's focus on the content of the file.


## The `tasks` section

Each entry in the `tasks` array declares one task:

```ron
(
    id: "src",                    // Unique string identifier
    type: "tasks::MySource",      // Rust type that implements the task
),
```

- **`id`** -- A unique name for this task instance. Used to reference it in connections.
- **`type`** -- The fully qualified path to the Rust struct (relative to your crate root).

### Optional task fields

Beyond `id` and `type`, each task entry supports several optional fields:

- **`config`** -- A key-value map of parameters passed to the task's `new()` constructor
  as an `Option<&ComponentConfig>`. We'll see how to read them in the
  [Task Anatomy](./ch08-task-anatomy.md) chapter.

  ```ron
  (
      id: "gpio",
      type: "cu_rp_gpio::RPGpio",
      config: {
          "pin": 4,
      },
  ),
  ```

- **`missions`** -- A list of mission IDs in which this task is active. Copper supports
  defining multiple "missions" (configurations of the same robot for different scenarios).
  A task only gets instantiated if the current mission is in its list. If omitted, the task
  is active in all missions.

  ```ron
  (
      id: "lidar",
      type: "tasks::LidarDriver",
      missions: ["outdoor", "mapping"],
  ),
  ```

- **`background`** -- When set to `true`, the task runs on a **background thread** instead
  of the critical path. Useful for tasks that do heavy or blocking work (network I/O, disk
  writes) that shouldn't affect the deterministic scheduling of other tasks.

  ```ron
  (
      id: "telemetry",
      type: "tasks::TelemetryUploader",
      background: true,
  ),
  ```

- **`logging`** -- Controls whether Copper's unified logger records the output messages of
  this task. Set `enabled: false` to reduce log size for high-frequency or uninteresting
  tasks.

  ```ron
  (
      id: "fast-sensor",
      type: "tasks::HighRateSensor",
      logging: (enabled: false),
  ),
  ```

## The `cnx` (connections) section

Each entry in `cnx` wires one task's output to another's input:

```ron
(
    src: "src",                          // Producing task's id
    dst: "t-0",                          // Consuming task's id
    msg: "crate::tasks::MyPayload",      // Rust type of the message payload
),
```

- **`src`** -- The `id` of the task producing the message.
- **`dst`** -- The `id` of the task consuming the message.
- **`msg`** -- The fully qualified Rust type of the payload (see next chapter for a focus on this).
- **`missions`** (optional) -- A list of mission IDs in which this connection is active,
  just like the `missions` field on tasks. If omitted, the connection is active in all
  missions.

  ```ron
  (
      src: "lidar",
      dst: "mapper",
      msg: "crate::tasks::PointCloud",
      missions: ["outdoor", "mapping"],
  ),
  ```

### How this compares to ROS

In ROS 2, you'd create publishers and subscribers on named topics, and they'd find each
other at runtime via DDS discovery. In Copper, connections are **explicit and resolved at
compile time**. If you reference a task `id` that doesn't exist, you get a compile error --
not a silent runtime misconfiguration.

## There's more

The configuration file we've seen here is minimal on purpose. Real-world Copper projects
can use additional top-level sections for monitoring, logging tuning, rate limiting,
missions, and modular composition. We'll cover these throughout the book as we go.
