# Reusing Community Components

One of the biggest advantages of building your robot with Copper is that you don't have to
write everything from scratch. The Copper RS repository ships with a growing collection of
**ready-made components** -- sensor drivers, algorithms, bridges, and shared message
types -- that you can drop into your project.

In this chapter, we'll explore what's available and how to use it.

## The components directory

The Copper RS repository organizes its components by role:

```text
components/
├── sources/      Sensor drivers that produce data
├── sinks/        Actuator drivers that consume data
├── tasks/        Processing algorithms (input → output)
├── bridges/      Interfaces to external systems (Zenoh, ROS 2)
├── monitors/     Monitoring and visualization tools
├── payloads/     Shared message types
├── libs/         Supporting libraries
├── res/          Platform-specific resource bundles (HAL)
└── testing/      Test helpers (network injection, mocks)
```

Each component is a standalone Rust crate that implements one or more Copper tasks. You
add it as a dependency, reference it in `copperconfig.ron`, and you're done -- no glue
code needed.

The ecosystem is actively growing. Browse the
[components directory](https://github.com/copper-project/copper-rs/tree/master/components)
in the Copper RS repository to see what's currently available -- you'll find LiDAR drivers,
IMU drivers, camera capture, PID controllers, AprilTag detection, Zenoh and ROS 2 bridges,
and more.

## How to use a component

Let's say you want to add a PID controller to your project. The process is:

### 1. Add the dependency

In your application's `Cargo.toml`:

```toml
[dependencies]
cu-pid = { path = "../../components/tasks/cu_pid" }
```

Or if the component is published on crates.io:

```toml
[dependencies]
cu-pid = "0.12"
```

In a workspace, you'd add it to the workspace-level `Cargo.toml` first:

```toml
[workspace.dependencies]
cu-pid = { path = "../../components/tasks/cu_pid" }
```

Then reference it in the app's `Cargo.toml`:

```toml
[dependencies]
cu-pid = { workspace = true }
```

### 2. Reference it in copperconfig.ron

Add the task to your configuration using the crate's type path:

```ron
(
    id: "pid",
    type: "cu_pid::PIDTask",
    config: {
        "kp": 1.0,
        "ki": 0.1,
        "kd": 0.05,
    },
),
```

The `type` field uses the crate name and the task struct name. The `config` section passes
parameters that the task reads in its `new()` constructor.

### 3. Wire it up

Connect it to your existing tasks:

```ron
cnx: [
    (
        src: "imu",
        dst: "pid",
        msg: "cu_sensor_payloads::ImuData",
    ),
    (
        src: "pid",
        dst: "motor",
        msg: "cu_pid::PIDOutput",
    ),
],
```

That's it. No wrapper code, no adapter layer. The component is a Copper task like any
other -- it just happens to live in a separate crate.

## Using shared payload types

When two components need to exchange data, they must agree on a message type. This is
where the **payloads** crates come in.

For example, `cu-sensor-payloads` defines common sensor types that multiple source drivers
produce. If you use the BMI088 IMU driver (`cu-bmi088`), it outputs a type from
`cu-sensor-payloads`. Any downstream task that accepts that same type can consume the data
without any conversion.

This is the component ecosystem's contract: drivers produce standard payload types, and
algorithms consume them. Swap a Bosch IMU for an InvenSense IMU, and the downstream
pipeline doesn't change -- both produce the same `ImuData` type.

## Writing your own reusable components

If you've built a task that could be useful to others -- or even just to your future
self across projects -- you can extract it into a component crate:

1. **Create a library crate** under `components/` (pick the right category).
2. **Move your task struct and its `impl`** into `lib.rs`.
3. **Move shared message types** into the crate or use existing ones from `cu-sensor-payloads`.
4. **Add it to the workspace** `members` list in the root `Cargo.toml`.
5. **Reference it** from your application's `Cargo.toml` and `copperconfig.ron`.

The workspace template already has placeholder directories with `.keep` files for each
component category. Just replace the placeholder with your crate.

## Difference with ROS

In ROS 2, reusing components means installing packages (via `apt` or building from source)
and then referencing their nodes in your launch files. The discovery is runtime-based --
nodes find each other through DDS topics.

In Copper, reusing components means adding a Rust dependency and referencing the task
type in `copperconfig.ron`. The wiring is resolved at compile time.

| | ROS 2 | Copper |
|---|---|---|
| **Discovery** | Packages via `apt` / source build | Crates via `Cargo.toml` |
| **Integration** | Launch files + topic remapping | `copperconfig.ron` + type paths |
| **Message compatibility** | `.msg` files + code generation | Shared Rust types (payloads crates) |
| **Validation** | Runtime (topics may not match) | Compile time (types must match) |
| **Sharing** | ROS package index | crates.io / git dependencies |

The biggest difference is the **compile-time guarantee**. In ROS, you can wire two nodes
together with mismatched message types and only find out when you run the system. In
Copper, if your PID controller expects `ImuData` and your driver produces `CameraFrame`,
the compiler tells you immediately.

