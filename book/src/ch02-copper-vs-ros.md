# Copper RS vs ROS

If you're coming from ROS or ROS 2, this chapter maps the concepts you already know to
their Copper equivalents. The mental model is similar. Both are component-based
frameworks with message passing, but the execution model is fundamentally different.

## Concept mapping

| ROS 2 | Copper RS | Notes |
|---|---|---|
| Node | Task | A unit of computation |
| Publisher | `CuSrcTask` | Produces data (sensor driver) |
| Subscriber + Publisher | `CuTask` | Processes data (algorithm) |
| Subscriber | `CuSinkTask` | Consumes data (actuator) |
| `.msg` file | Rust struct with derives | Message definition |
| Topic | Connection in `copperconfig.ron` | Data channel between tasks |
| Launch file + YAML params | `copperconfig.ron` | Graph topology + task parameters |
| `colcon build` | `cargo build` | Build system |
| `package.xml` / `CMakeLists.txt` | `Cargo.toml` | Dependency management |
| Executor | `#[copper_runtime]` macro | Generated deterministic scheduler |
| `rosbag` | Unified Logger + `cu29-export` | Record and replay |
| Parameter server | `ComponentConfig` in RON | Per-task key-value configuration |

## Key differences

### Scheduling

In ROS 2, nodes are separate processes (or threads in a composed executor). Callbacks fire
**asynchronously** when messages arrive via DDS. The execution order depends on network
timing and OS scheduling -- it's non-deterministic.

In Copper, tasks run **in the same process** and are called **synchronously** in a
compile-time-determined order. Every cycle, every task runs in the exact same sequence.
There are no callbacks, no races, no surprises.

### Message passing

In ROS 2, messages are serialized, sent over DDS (a network middleware), deserialized, and
delivered to callbacks. This adds latency and allocations.

In Copper, messages are **pre-allocated buffers** in shared memory. A task writes its
output directly into a buffer that the next task reads from. No serialization, no copies,
no allocations on the hot path.

### Replay

In ROS 2, `rosbag` records and replays topic messages. Replay is approximate -- timing
jitter, OS scheduling, and node startup order can cause differences.

In Copper, replay is **deterministic**. The unified logger records every message and
periodic state snapshots ("keyframes"). Given the same log, replay produces identical
results every time, down to the bit.

### Configuration

In ROS 2, you typically write a launch file (Python or XML), separate YAML parameter
files, and topic remappings. These are resolved at runtime.

In Copper, everything is in **one RON file** (`copperconfig.ron`) that is read at
**compile time**. If your config references a task type that doesn't exist, you get a
compile error, not a runtime crash.

### Bridges

The good news is that you do not have to chose between Copper and ROS: Copper's Zenoh bridge lets you run both side by side, so you can migrate
incrementally.
