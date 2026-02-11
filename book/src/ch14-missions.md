# Missions

So far, our project has a single pipeline: `MySource → MyTask → MySink`. Every time we
run it, the same three tasks execute in the same order. But real-world robots often need
to operate in **different modes** -- a drone might have a "takeoff" mode and a "cruise"
mode, a warehouse robot might switch between "navigate" and "charge", or you might want
a "simulation" mode that uses mock drivers instead of real hardware.

In many frameworks, you'd handle this with `if` statements scattered across your code, or
by maintaining separate launch files. Copper takes a different approach: **missions**.

## What are missions?

A mission is a named **variant** of your task graph. You declare all possible tasks and
connections in a single `copperconfig.ron`, then tag each one with the missions it belongs
to. At build time, Copper generates a separate application builder for each mission. At
runtime, you choose which builder to use.

The key properties:

- **Tasks without a `missions` field are shared** -- they exist in every mission.
- **Tasks with a `missions` field are selective** -- they only exist in the listed missions.
- **Connections follow the same rule** -- tag them with `missions` to make them
  mission-specific.
- **No recompilation needed to switch** -- all missions are compiled at once. You pick
  which one to run.

## Step 1: Define missions in copperconfig.ron

Let's modify our project to support two missions:

- **"normal"** -- The full pipeline we've been using: source → processing → sink.
- **"direct"** -- A shortcut that skips the processing task: source → sink.

This is a simple but realistic scenario. Imagine `MyTask` does some expensive computation
(image processing, path planning). During testing or in a degraded mode, you might want to
bypass it and send raw data straight to the sink.

Replace your `copperconfig.ron` with:

```ron
(
    missions: [(id: "normal"), (id: "direct")],
    tasks: [
        (
            id: "src",
            type: "tasks::MySource",
        ),
        (
            id: "t-0",
            type: "tasks::MyTask",
            missions: ["normal"],
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
            missions: ["normal"],
        ),
        (
            src: "t-0",
            dst: "sink",
            msg: "crate::tasks::MyPayload",
            missions: ["normal"],
        ),
        (
            src: "src",
            dst: "sink",
            msg: "crate::tasks::MyPayload",
            missions: ["direct"],
        ),
    ],
    runtime: (
        rate_target_hz: 1,
    ),
)
```

Let's break down what changed:

### The `missions` declaration

```ron
missions: [(id: "normal"), (id: "direct")],
```

This top-level array declares all available missions. Each mission is just an ID -- a
string that you'll reference elsewhere.

### Shared tasks

`src` and `sink` have **no** `missions` field. This means they participate in every
mission. They are the common backbone of the pipeline.

### Mission-specific tasks

```ron
(
    id: "t-0",
    type: "tasks::MyTask",
    missions: ["normal"],
),
```

`MyTask` is tagged with `missions: ["normal"]`. It only exists in the "normal" mission.
When running the "direct" mission, this task is simply not instantiated.

### Mission-specific connections

The connections are where the graph really diverges:

```text
Mission "normal":   src ──▶ t-0 ──▶ sink
Mission "direct":   src ──────────▶ sink
```

In "normal", data flows through the processing task. In "direct", the source connects
directly to the sink, bypassing `MyTask` entirely.

Notice that the connection `src → sink` in the "direct" mission uses the same message type
(`crate::tasks::MyPayload`) as the other connections. This works because `MySink` already
accepts `MyPayload` as input -- the message types must be compatible regardless of which
path the data takes.

## Step 2: Update main.rs

When you declare missions, the `#[copper_runtime]` macro no longer generates a single
builder. Instead, it creates a **module for each mission**, named after the mission ID.
Each module contains its own builder type.

For our project, the macro generates:

- `normal::MyProjectApplicationBuilder` -- builds the "normal" pipeline
- `direct::MyProjectApplicationBuilder` -- builds the "direct" pipeline

Update `main.rs` to select a mission:

```rust
pub mod tasks;

use cu29::prelude::*;
use cu29_helpers::basic_copper_setup;
use std::path::{Path, PathBuf};
use std::thread::sleep;
use std::time::Duration;

const PREALLOCATED_STORAGE_SIZE: Option<usize> = Some(1024 * 1024 * 100);

#[copper_runtime(config = "copperconfig.ron")]
struct MyProjectApplication {}

// Import the per-mission builders
use normal::MyProjectApplicationBuilder as NormalBuilder;
use direct::MyProjectApplicationBuilder as DirectBuilder;

fn main() {
    // Pick the mission from the first command-line argument (default: "normal")
    let mission = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "normal".to_string());

    let logger_path = "logs/my-project.copper";
    if let Some(parent) = Path::new(logger_path).parent() {
        if !parent.exists() {
            std::fs::create_dir_all(parent).expect("Failed to create logs directory");
        }
    }
    let copper_ctx = basic_copper_setup(
        &PathBuf::from(&logger_path),
        PREALLOCATED_STORAGE_SIZE,
        true,
        None,
    )
    .expect("Failed to setup logger.");
    debug!("Logger created at {}.", logger_path);

    match mission.as_str() {
        "normal" => {
            debug!("Starting mission: normal");
            let mut app = NormalBuilder::new()
                .with_context(&copper_ctx)
                .build()
                .expect("Failed to create application.");
            app.run().expect("Failed to run application.");
        }
        "direct" => {
            debug!("Starting mission: direct");
            let mut app = DirectBuilder::new()
                .with_context(&copper_ctx)
                .build()
                .expect("Failed to create application.");
            app.run().expect("Failed to run application.");
        }
        other => {
            eprintln!("Unknown mission: '{}'. Available: normal, direct", other);
            std::process::exit(1);
        }
    }

    debug!("End of program.");
    sleep(Duration::from_secs(1));
}
```

The important changes:

1. **Two `use` statements** import the builders from the generated mission modules.
2. **A `match` on the mission name** selects which builder to use. Here we read it from
   the command line, but you could also use an environment variable, a config file, or any
   other mechanism.
3. **Each branch is independent** -- the "normal" branch builds a three-task pipeline, the
   "direct" branch builds a two-task pipeline.

No changes to `tasks.rs` are needed. The task implementations are the same -- missions
only control which tasks are **instantiated and wired**, not how they behave.

## Step 3: Run it

Run the "normal" mission (the default):

```bash
cargo run
```

```text
00:00:00.0006 [Debug] Source at 630
00:00:00.0006 [Debug] Received message: 42
00:00:00.0006 [Debug] Sink Received message: 43
00:00:01.0002 [Debug] Source at 1000259
00:00:01.0004 [Debug] Received message: 42
00:00:01.0004 [Debug] Sink Received message: 43
00:00:01.9999 [Debug] Source at 1999931
00:00:02.0000 [Debug] Received message: 42
00:00:02.0001 [Debug] Sink Received message: 43
```

This is the full pipeline. The source produces 42, `MyTask` transforms it to 43, and the
sink receives 43.

Now run the "direct" mission:

```bash
cargo run -- direct
```

```text
00:00:00.0005 [Debug] Source at 549
00:00:00.0005 [Debug] Sink Received message: 42
00:00:00.9999 [Debug] Source at 999945
00:00:01.0000 [Debug] Sink Received message: 42
00:00:01.9992 [Debug] Source at 1999286
00:00:01.9994 [Debug] Sink Received message: 42
00:00:02.9987 [Debug] Source at 2998704
00:00:02.9988 [Debug] Sink Received message: 42
```

Notice the difference: there is no "Received message: 42" line from `MyTask`, and the sink
receives **42** (the raw value from the source) instead of 43. `MyTask` was never
instantiated -- the data went straight from source to sink.

Same binary, same tasks, different wiring. No recompilation.

## How it works under the hood

When the `#[copper_runtime]` macro processes a configuration with missions, it:

1. **Parses all missions** from the top-level `missions` array.
2. **For each mission**, filters the task list and connection list to include only:
   - Tasks/connections with no `missions` field (shared across all missions)
   - Tasks/connections whose `missions` array contains this mission's ID
3. **Generates a Rust module** for each mission (named after the mission ID), containing
   a builder type, the filtered task graph, and the scheduling code.

All of this happens at compile time. The final binary contains the code for every mission,
but only the tasks belonging to the selected mission are instantiated at runtime.

## A task can belong to multiple missions

A task isn't limited to a single mission. If you have a task that's needed in several
(but not all) missions, list them:

```ron
(
    id: "safety-monitor",
    type: "tasks::SafetyMonitor",
    missions: ["navigate", "charge", "manual"],
),
```

This task is active in three missions but excluded from others (say, "simulation" or
"diagnostics").

## When to use missions

Missions are most useful when you have:

- **Hardware vs simulation**: Use real drivers in one mission, mock drivers in another.
- **Operating modes**: Different task graphs for different phases of operation (startup,
  cruise, landing).
- **Platform variants**: The same codebase running on different hardware -- one mission for
  the prototype with basic sensors, another for the production model with full sensor
  suite.
- **Debug vs production**: A mission with extra logging/monitoring tasks for development,
  and a lean mission for deployment.

## Difference with ROS

In ROS 2, switching between configurations typically means maintaining **separate launch
files** or using **launch arguments** with conditionals:

```python
# ROS 2: launch file with conditionals
use_sim = LaunchConfiguration('use_sim')

Node(
    package='my_robot',
    executable='lidar_driver',
    condition=UnlessCondition(use_sim),
),
Node(
    package='my_robot',
    executable='fake_lidar',
    condition=IfCondition(use_sim),
),
```

```text
ros2 launch my_robot robot.launch.py use_sim:=true
```

This works, but the logic lives in Python launch files that are completely separate from
your node code. Errors (wrong topic names, missing remappings) only show up at runtime.

In Copper, everything is in one `copperconfig.ron`:

```text
Copper:
  copperconfig.ron    ← all missions, tasks, and connections in one place
  cargo run           ← default mission
  cargo run -- direct ← alternative mission
```

Key differences:

| | ROS 2 | Copper |
|---|---|---|
| **Where** | Python launch files + YAML params | Single `copperconfig.ron` |
| **Validation** | Runtime (nodes may fail to connect) | Compile time (macro checks the graph) |
| **Granularity** | Per-node conditionals | Per-task and per-connection tagging |
| **Switching** | Launch arguments | Builder selection in `main.rs` |
| **All variants visible** | Spread across files and conditionals | One file, all missions side by side |

The biggest advantage is **visibility**: you can look at one file and see every mission,
every task, and exactly which tasks are active in which missions. There's no need to
mentally simulate a launch file's conditional logic to figure out what will actually run.
