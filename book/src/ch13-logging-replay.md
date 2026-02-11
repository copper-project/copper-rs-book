# Logging and Replaying Data

Every time you've run our project so far, Copper has been quietly recording everything.
Look at `main.rs` -- the call to `basic_copper_setup()` initializes a **unified logger**
that writes to `logs/my-project.copper`. Every cycle, the runtime serializes every message
exchanged between tasks (the **CopperList**) and writes it to that file.

In this chapter, we'll explore what's in that log file, how to read it back, and how to
**replay** recorded data through the pipeline.

## What gets logged?

Copper's unified logger captures two kinds of data in a single `.copper` file:

1. **Structured text logs** -- Every `debug!()`, `info!()`, `warn!()`, and `error!()` call
   from your tasks. These are stored in an efficient binary format (not as text strings),
   so they're extremely fast to write and compact on disk.

2. **CopperList data** -- The complete set of message payloads exchanged between tasks in
   each cycle. In our project, that means every `MyPayload { value: 42 }` from `MySource`
   and every `MyPayload { value: 43 }` from `MyTask`, along with precise timestamps.

This is different from most robotics frameworks where logging is opt-in and you have to
explicitly record topics. In Copper, **every message is logged by default**. The runtime
does this automatically as part of its execution loop -- no extra code needed.

## Step 1: Generate a log file

Make sure your project is in the state from the previous chapters, with the 1 Hz rate
limiter. Here's the `copperconfig.ron` for reference:

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
    runtime: (
        rate_target_hz: 1,
    ),
)
```

> **Note:** If you still have the `monitor` section from the previous chapter, remove it
> for now. The console monitor takes over the terminal and makes it harder to see the
> debug output.

Run the project and let it execute for 5-10 seconds, then press **Ctrl+C**:

```bash
cargo run
```

```text
00:00:03.9986 [Debug] Received message: 42
00:00:03.9987 [Debug] Sink Received message: 43
00:00:04.9979 [Debug] Source at 4997916
00:00:04.9980 [Debug] Received message: 42
00:00:04.9981 [Debug] Sink Received message: 43
...
```

After stopping, check the `logs/` directory:

```bash
ls -lh logs/
```

```text
-rw-r--r-- 1 user user 4.0K  logs/my-project.copper
```

That `.copper` file contains everything: every message, every timestamp, every debug line.

> **Note:** The log path is hardcoded to `"logs/my-project.copper"` in `main.rs`. Each run
> overwrites the previous log file -- there is no automatic rotation or timestamping. If
> you want to keep a log from a previous session, rename or move the file before running
> the project again.

## Step 2: The log reader

If you look at your project, you'll notice there's already a file you haven't used yet:
`src/logreader.rs`. The project template ships with a built-in log reader. Let's look at
it:

```rust
pub mod tasks;

use cu29::prelude::*;
use cu29_export::run_cli;

// This will create the CuStampedDataSet that is specific to your copper project.
// It is used to instruct the log reader how to decode the logs.
gen_cumsgs!("copperconfig.ron");

#[cfg(feature = "logreader")]
fn main() {
    run_cli::<CuStampedDataSet>().expect("Failed to run the export CLI");
}
```

This is a small but powerful program. Let's break it down:

**`gen_cumsgs!("copperconfig.ron")`** -- This macro reads your task graph and generates a
`CuStampedDataSet` type that knows the exact message types used in your pipeline. The log
reader needs this to decode the binary data in the `.copper` file -- without it, the bytes
would be meaningless.

**`run_cli::<CuStampedDataSet>()`** -- This is Copper's built-in export CLI. It provides
several subcommands for extracting data from `.copper` files. By passing the generated
`CuStampedDataSet` type, you tell it exactly how to decode your project's messages.

**`#[cfg(feature = "logreader")]`** -- The log reader is gated behind a Cargo feature flag
so its dependencies (like `cu29-export`) are only compiled when you actually need them.

## Step 3: Extract text logs

The first thing you can do with the log reader is extract the structured text logs -- the
`debug!()` messages from your tasks. Remember, these aren't stored as text in the
`.copper` file; they're stored as compact binary indices. The log reader reconstructs the
human-readable text using the string index that was built at compile time.

Run:

```bash
cargo run --features logreader --bin my-project-logreader -- \
    logs/my-project.copper extract-text-log target/debug/cu29_log_index
```

The arguments are:
- `logs/my-project.copper` -- The log file to read
- `extract-text-log` -- The subcommand to extract text logs
- `target/debug/cu29_log_index` -- The path to the string index directory (generated
  during compilation by `build.rs`)

You'll see output like:

```text
25.501 µs [Debug]: Logger created at logs/my-project.copper.
45.903 µs [Debug]: Creating application... 
64.282 µs [Debug]: CuConfig: Reading configuration from file: copperconfig.ron
669.067 µs [Debug]: Running... starting clock: 666.866 µs.
823.766 µs [Debug]: Source at 822
870.122 µs [Debug]: Received message: 42
887.054 µs [Debug]: Sink Received message: 43
1.000 s [Debug]: Source at 1000206
1.000 s [Debug]: Received message: 42
1.000 s [Debug]: Sink Received message: 43
2.000 s [Debug]: Source at 1999631
...
```

This is the same output you saw scrolling by when the application was running -- but
reconstructed from the binary log after the fact.

## Step 4: Extract CopperLists

The more interesting subcommand extracts the **CopperList data** -- the actual message
payloads from every cycle:

```bash
cargo run --features logreader --bin my-project-logreader -- \
    logs/my-project.copper extract-copperlists
```

The output is JSON by default. Here's what the first CopperList looks like:

```json
{
  "id": 0,
  "state": "BeingSerialized",
  "msgs": [
    {
      "payload": {
        "value": 42
      },
      "tov": "None",
      "metadata": {
        "process_time": {
          "start": 822050,
          "end": 867803
        },
        "status_txt": ""
      }
    },
    {
      "payload": {
        "value": 43
      },
      "tov": "None",
      "metadata": {
        "process_time": {
          "start": 869282,
          "end": 885259
        },
        "status_txt": ""
      }
    }
  ]
}
```

Every message from every cycle is there, exactly as it was produced. Each entry in `msgs`
corresponds to a connection in your task graph (in order: `src→t-0`, then `t-0→sink`).
Along with the `payload`, you get:

- **`metadata.process_time`** -- The start and end timestamps (in nanoseconds) of the
  task's `process()` call that produced this message. This is the same timing data the
  console monitor uses for its latency statistics.
- **`tov`** -- "Time of validity", an optional timestamp that the task can set to indicate
  when the data was actually captured (useful for hardware drivers with their own clocks).
- **`status_txt`** -- An optional status string the task can set for diagnostics.

This is the raw data you'd use for offline analysis, regression testing, or replay.

## Why this matters: replay

Recording data is useful for post-mortem analysis, but the real power of Copper's logging
is **deterministic replay**. Because every message and its timestamp is recorded, you can
feed logged data back into the pipeline and reproduce the exact same execution -- without
any hardware.

This means you can:

- **Debug without hardware**: Record a session on the real robot, then replay it on your
  laptop to test processing logic.
- **Regression test**: Record a known-good session, then replay it after code changes to
  verify the pipeline still produces the same results.
- **Analyze edge cases**: When your robot encounters an unusual situation, the log
  captures it. You can replay that exact moment over and over while you debug.

The key insight is that all downstream tasks don't know the difference -- they receive
the same `MyPayload` messages with the same timestamps, whether they come from live
hardware or a log file.

## How the unified logger works under the hood

Copper's logger is designed for **zero-impact logging** on the critical path. Here's how:

1. **Pre-allocated memory slabs** -- At startup, `basic_copper_setup()` allocates a large
   contiguous block of memory (controlled by `PREALLOCATED_STORAGE_SIZE` -- 100 MB in our
   project). CopperLists are written into this pre-allocated buffer without any dynamic
   allocation.

2. **Binary serialization** -- Messages are serialized using `bincode`, not formatted as
   text. This is why your payloads need the `Encode` / `Decode` derives. Binary
   serialization is orders of magnitude faster than `format!()` or `serde_json`.

3. **Memory-mapped I/O** -- The pre-allocated slabs are memory-mapped to the `.copper`
   file. The OS handles flushing to disk asynchronously, so the robot's critical path
   never blocks on disk I/O.

4. **Structured text logging** -- Even `debug!()` calls don't format strings at runtime.
   Instead, Copper stores a compact index and the raw values. The actual string formatting
   happens only when you *read* the log -- not when you write it. This is why the
   `build.rs` sets up `LOG_INDEX_DIR` -- it's building a string table at compile time.

This means logging in Copper is almost free on the hot path. You can log everything
without worrying about performance -- which is exactly why it logs everything by default.

## Controlling what gets logged

Sometimes you don't want to log everything. A high-frequency sensor producing megabytes
per second can fill up your log storage quickly. Copper provides two ways to control this:

### Per-task logging control

In `copperconfig.ron`, you can disable logging for specific tasks:

```ron
(
    id: "fast-sensor",
    type: "tasks::HighRateSensor",
    logging: (enabled: false),
),
```

This stops the runtime from recording that task's output messages in the CopperList log.
The task still runs normally -- it just doesn't contribute to the log file.

### Global logging settings

The `logging` section in `copperconfig.ron` lets you tune the logger globally:

```ron
logging: (
    slab_size_mib: 1024,
    section_size_mib: 100,
),
```

## Difference with ROS

In ROS, data recording is a separate tool: `rosbag2`. You start a `ros2 bag record`
process alongside your running nodes, tell it which topics to subscribe to, and it saves
messages into a SQLite database or MCAP file. Replay is done with `ros2 bag play`, which
republishes the messages on the same topics.

```text
ROS:
  Run:    ros2 launch my_robot.launch.py
  Record: ros2 bag record /camera /imu /cmd_vel       ← separate process
  Replay: ros2 bag play my_bag/                        ← republishes on topics

Copper:
  Run:    cargo run                                     ← logging is automatic
  Read:   cargo run --features logreader --bin my-project-logreader ...
  Replay: feed CopperLists back into the pipeline       ← deterministic
```

Key differences:

| | ROS 2 (rosbag2) | Copper (unified logger) |
|---|---|---|
| **Opt-in vs automatic** | You must explicitly record topics | Everything is logged by default |
| **Separate process** | `ros2 bag record` runs alongside | Built into the runtime -- zero config |
| **Format** | SQLite / MCAP | Custom binary `.copper` format |
| **Performance impact** | Adds subscriber overhead per topic | Near-zero -- pre-allocated, memory-mapped |
| **Replay mechanism** | Republishes on topics | Feed CopperLists directly into tasks |
| **Deterministic** | Timing depends on DDS, not guaranteed | Timestamps are recorded, replay is deterministic |
| **Text logging** | Separate (`rosout`, `spdlog`) | Unified -- text and data in one file |

The biggest philosophical difference: in ROS, recording is something you *do*. In Copper,
recording is something that *happens*. You don't configure it, you don't start it, you
don't choose which topics to record. The runtime records everything, always. You only need
to decide what to *exclude* (via `logging: (enabled: false)`) if storage is a concern.

This "record everything by default" approach is what makes Copper's deterministic replay
possible. Since every message and every timestamp is captured automatically, you can always
go back and reproduce any moment of your robot's execution.

