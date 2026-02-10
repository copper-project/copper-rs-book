# Controlling the Loop Frequency

If you've run our project, you noticed that the output scrolls **extremely fast**. That's
because by default, Copper runs the task graph as fast as possible -- there's no rate
limiter. On a modern machine, that can mean hundreds of thousands of cycles per second.

In this chapter, we'll see how fast the loop actually runs and how to set a target
frequency.

## How fast is it running?

Let's modify `MySource` in `tasks.rs` to print the time at each cycle. Replace the
`process()` method:

```rust
fn process(&mut self, clock: &RobotClock, output: &mut Self::Output<'_>) -> CuResult<()> {
    debug!("Source at {}µs", clock.now().as_micros());
    output.set_payload(MyPayload { value: 42 });
    Ok(())
}
```

Run the project and look at the timestamps:

```text
00:00:00.5296 [Debug] Source at 529632
00:00:00.5297 [Debug] Received message: 42
00:00:00.5298 [Debug] Sink Received message: 43
00:00:00.5300 [Debug] Source at 530005
00:00:00.5301 [Debug] Received message: 42
00:00:00.5302 [Debug] Sink Received message: 43
...
```

The values are in microseconds. The gap between two `Source at ...` lines is a few hundred
microseconds. Without a rate limiter, the loop runs as fast as it can -- potentially
thousands of cycles per second, pegging a CPU core at 100%. Way too fast for most applications -- and it will peg a CPU
core at 100%.

## Setting a target frequency

Copper provides a simple way to rate-limit the execution loop. Add a `runtime` section to
your `copperconfig.ron`:

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

The only change is the `runtime` section at the bottom. `rate_target_hz: 1` tells Copper
to target **1 cycle per second** (1 Hz).

Run again:

```text
00:00:00.0005 [Debug] Source at 510
00:00:00.0005 [Debug] Received message: 42
00:00:00.0005 [Debug] Sink Received message: 43
00:00:01.0000 [Debug] Source at 1000019
00:00:01.0001 [Debug] Received message: 42
00:00:01.0001 [Debug] Sink Received message: 43
```

Now each full cycle (source -> task -> sink) runs once per second.


## How it works

`rate_target_hz` acts as a **rate limiter**, not a scheduler. After each complete cycle,
the runtime checks how much time has elapsed. If the cycle finished faster than the target
period (e.g., under 10ms for 100 Hz), the runtime waits for the remaining time. If the
cycle took longer than the target period, the next cycle starts immediately -- no time is
wasted.

This means:
- Your actual frequency is **at most** `rate_target_hz`.
- If your tasks are too slow for the target, the loop runs at whatever rate it can sustain.
- Without the `runtime` section, the loop runs flat-out with no pause between cycles.

## Difference with ROS

In ROS, each node controls its own frequency. A camera node publishes at 30 Hz, an IMU
node publishes at 200 Hz, and a planner node runs at 10 Hz -- all independently. Nodes
are loosely coupled via topics, and each one has its own `rospy.Rate()` or `rclcpp::Rate`
timer that governs how often it publishes.

Copper works differently. There is **one global loop** that executes the entire task graph
in sequence: source -> processing -> sink, back-to-back, in topological order. Every task
runs **every cycle**, as fast as possible. The `rate_target_hz` setting doesn't make
individual tasks run at different speeds -- it tells the runtime how long to **wait
between cycles** so the whole pipeline doesn't run flat-out and peg the CPU.

```text
ROS:    Node A (30 Hz)  ──┐
        Node B (200 Hz) ──┼── independent timers, publish on topics
        Node C (10 Hz)  ──┘

Copper: [ Source → Task → Sink ] → wait → [ Source → Task → Sink ] → wait → ...
        └──── one cycle ────────┘         └──── one cycle ────────┘
                         global rate_target_hz
```

The key insight: in Copper, all tasks share the same cadence. If you need different parts
of your system to run at different rates (e.g., a fast inner control loop and a slow
planner), you'd use separate task graphs or implement logic inside a task to skip cycles.
But for most applications, a single frequency for the whole pipeline is simpler and avoids
the synchronization headaches that come with multiple independent timers.

