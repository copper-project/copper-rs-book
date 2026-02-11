# Task Lifecycle

Beyond `new()` and `process()`, Copper tasks have a full lifecycle with optional hooks for
setup, teardown, and non-critical work. Understanding this lifecycle helps you put the
right code in the right place.

## The full lifecycle

```text
new()  →  start()  →  [ preprocess() → process() → postprocess() ]  →  stop()
                       └──────────── repeats every cycle ────────────┘
```

## Lifecycle methods

| Method | When | Thread | What to do here |
|---|---|---|---|
| `new()` | Once, at construction | Main | Read config, initialize state |
| `start()` | Once, before the first cycle | Main | Open file handles, initialize hardware, allocate buffers |
| `preprocess()` | Every cycle, before `process()` | **Best-effort** | Heavy prep work: decompression, FFT, parsing |
| `process()` | Every cycle | **Critical path** | Core logic. Keep it fast. No allocations. |
| `postprocess()` | Every cycle, after `process()` | **Best-effort** | Telemetry, non-critical logging, statistics |
| `stop()` | Once, after the last cycle | Main | Cleanup: close files, stop hardware, free resources |

## The two threads

Copper splits each cycle across two execution contexts:

### Critical path thread
This is where `process()` runs. Tasks execute **back-to-back** in the order determined by
the task graph topology. The runtime minimizes latency and jitter on this thread. You must
avoid allocations, system calls, and anything that could block.

### Best-effort thread
This is where `preprocess()` and `postprocess()` run. The runtime schedules these to
**minimize interference** with the critical path. You can safely do heavier work here:
I/O, allocations, logging, network calls.

### What if `preprocess()` is late?

The critical path **never waits** for the best-effort thread. If `preprocess()` takes
longer than expected and hasn't finished when the critical path is ready, `process()` runs
anyway -- with whatever data is available from the previous cycle (or nothing, if it's the
first one).

This is intentional: in a real-time system, a late result is a wrong result. It's better
to run your control loop on slightly stale data than to miss a deadline. Your `process()`
should handle this gracefully:

```rust
fn preprocess(&mut self, _clock: &RobotClock) -> CuResult<()> {
    // Heavy work on the best-effort thread -- might be slow
    self.decoded_image = Some(decode_jpeg(&self.raw_buffer));
    Ok(())
}

fn process(&mut self, _clock: &RobotClock, input: &Self::Input<'_>,
           output: &mut Self::Output<'_>) -> CuResult<()> {
    // Use whatever is ready. If preprocess was late, decoded_image
    // still holds the previous cycle's result (or None on first cycle).
    if let Some(ref image) = self.decoded_image {
        output.set_payload(run_inference(image));
    }
    Ok(())
}
```

The same applies to `postprocess()`: if it falls behind, the next cycle's `process()`
still runs on time.

## Example: when to use each method

Imagine an IMU driver task:

```text
new()           → Read the SPI bus config from ComponentConfig
start()         → Open the SPI device, configure the sensor registers
preprocess()    → (not needed for this task)
process()       → Read raw bytes from SPI, convert to ImuReading, set_payload()
postprocess()   → Log statistics (sample rate, error count)
stop()          → Close the SPI device
```

Or a computer vision task:

```text
new()           → Load the model weights
start()         → Initialize the inference engine
preprocess()    → Decode the JPEG image from the camera (heavy, OK on best-effort thread)
process()       → Run inference on the decoded image, output detections
postprocess()   → Update FPS counter, send telemetry
stop()          → Release GPU resources
```

## All lifecycle methods are optional

`new()` and `process()` are required -- everything else has a default no-op implementation.
You only implement the lifecycle methods you need:

```rust
impl CuTask for MyTask {
    type Resources<'r> = ();
    type Input<'m> = input_msg!(MyPayload);
    type Output<'m> = output_msg!(MyPayload);

    // Required: constructor
    fn new(_config: Option<&ComponentConfig>, _resources: Self::Resources<'_>) -> CuResult<Self>
    where Self: Sized {
        Ok(Self {})
    }

    // Required: core logic
    fn process(&mut self, _clock: &RobotClock, input: &Self::Input<'_>,
               output: &mut Self::Output<'_>) -> CuResult<()> {
        // your core logic
        Ok(())
    }

    // Optionally implement any of these:
    // fn start(&mut self, clock: &RobotClock) -> CuResult<()> { ... }
    // fn stop(&mut self, clock: &RobotClock) -> CuResult<()> { ... }
    // fn preprocess(&mut self, clock: &RobotClock) -> CuResult<()> { ... }
    // fn postprocess(&mut self, clock: &RobotClock) -> CuResult<()> { ... }
}
```

## Freeze and thaw (state snapshots)

Copper automatically **logs every message** flowing between tasks. But messages alone
aren't enough to reproduce a task's behavior -- you also need its **internal state**.

Consider a PID controller that accumulates error over time. If you want to replay from
minute 7 of a 10-minute run to debug a crash, you need to know what the accumulated error
was at minute 7. Without state snapshots, you'd have to replay from the very start and
wait 7 minutes to get there.

That's what `freeze` and `thaw` solve. The `Freezable` trait gives each task two hooks:

- **`freeze()`** -- Save the task's internal state. Called periodically by the runtime
  to create "keyframes."
- **`thaw()`** -- Restore the task's state from a saved snapshot.

These are **not** part of the per-cycle loop. They run at a much lower rate and are
independent of the critical path:

```text
         ┌─── cycle ───┐  ┌─── cycle ───┐        ┌─── cycle ───┐
... ─── process() ─── process() ─── ... ─── process() ─── ...
                              │                         │
                          freeze()                  freeze()
                        (keyframe)                (keyframe)
```

Think of it like a video codec: `process()` runs every frame, while `freeze()` saves a
keyframe at a low rate. During replay, the runtime jumps to the nearest keyframe before
minute 7, restores every task's state via `thaw()`, and replays from there -- no need to
start from the beginning.

For stateless tasks (like our simple `MySource`, `MyTask`, `MySink`), the empty
`impl Freezable` is fine -- there's nothing to snapshot. We'll cover how to implement
`freeze` and `thaw` for stateful tasks in the
[Advanced Task Features](./ch19-advanced-tasks.md) chapter.
