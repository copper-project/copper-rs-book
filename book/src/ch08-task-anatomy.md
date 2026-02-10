# Task Anatomy: Types and Methods

Now that you've seen the three task traits, let's look closely at the associated types and
methods that make them work.

## Associated Types

### `type Resources<'r>` and `impl Freezable`

We'll cover these in detail in the
[Advanced Task Features](./ch15-advanced-tasks.md) chapter. For now, notice that both are
defined as empty -- `type Resources<'r> = ()` and `impl Freezable for MyTask {}` -- which
is all you need for a simple project.

### `type Input<'m>` (CuTask and CuSinkTask only)

```rust
type Input<'m> = input_msg!(MyPayload);
```

Declares **what messages this task receives** from upstream. The `input_msg!()` macro wraps
your payload type into Copper's message container (`CuMsg<T>`), which carries:

- The payload itself (your struct)
- Metadata (timestamps, status flags)
- Time of Validity (`tov`)

**Multiple inputs**: If a task receives data from multiple upstream tasks, list the types
separated by commas:

```rust
type Input<'m> = input_msg!(SensorA, SensorB);
```

In `process()`, the `input` parameter becomes a tuple that you can destructure:

```rust
fn process(&mut self, _clock: &RobotClock, input: &Self::Input<'_>, ...) -> CuResult<()> {
    let (sensor_a_msg, sensor_b_msg) = *input;
    // Use sensor_a_msg.payload() and sensor_b_msg.payload()
    Ok(())
}
```

### `type Output<'m>` (CuSrcTask and CuTask only)

```rust
type Output<'m> = output_msg!(MyPayload);
```

Declares **what messages this task produces** for downstream. The output buffer is
**pre-allocated** by the runtime at startup. You don't create messages -- you fill them
using `set_payload()`.

## Methods

### `fn new(config, resources) -> CuResult<Self>`

```rust
fn new(
    _config: Option<&ComponentConfig>,
    _resources: Self::Resources<'_>,
) -> CuResult<Self>
where
    Self: Sized,
{
    Ok(Self {})
}
```

The **constructor**. Called once when the runtime builds the task graph.

**`config: Option<&ComponentConfig>`** is a key-value map from the task's `config` block
in `copperconfig.ron`. For example, if your RON file has:

```ron
(
    id: "motor",
    type: "tasks::MotorDriver",
    config: { "pin": 4, "max_speed": 1.0 },
),
```

You can read the values in `new()`:

```rust
fn new(config: Option<&ComponentConfig>, _resources: Self::Resources<'_>) -> CuResult<Self> {
    let cfg = config.ok_or("MotorDriver requires a config block")?;
    let pin: u8 = cfg.get("pin").unwrap().clone().into();
    let max_speed: f64 = cfg.get("max_speed").unwrap().clone().into();
    Ok(Self { pin, max_speed })
}
```

We'll discuss resources in future chapters.

### `fn process()` -- the main loop

This is where your task does its work. The runtime calls it **every cycle**. The signature
depends on the trait:

| Trait | Signature |
|---|---|
| `CuSrcTask` | `process(&mut self, clock, output)` |
| `CuTask` | `process(&mut self, clock, input, output)` |
| `CuSinkTask` | `process(&mut self, clock, input)` |

In our simple example, the source ignores most parameters and just writes a value:

```rust
fn process(&mut self, _clock: &RobotClock, output: &mut Self::Output<'_>) -> CuResult<()> {
    output.set_payload(MyPayload { value: 42 });
    Ok(())
}
```

Let's look at what each parameter gives you.

#### Reading input

`input.payload()` returns `Option<&T>` -- an `Option` because the message could be empty
(e.g., the upstream task had nothing to send this cycle). In production you should handle
`None`; in our example we just unwrap:

```rust
let value = input.payload().unwrap();
```

#### Writing output

`output.set_payload(value)` writes your data into a buffer that was **pre-allocated at
startup**.

#### The clock: `&RobotClock`

Every `process()` receives a `clock` parameter. This is Copper's **only clock** -- a
monotonic clock that starts at zero when your program launches and ticks forward in
nanoseconds. There is no UTC or wall-clock in Copper; tasks should never call
`std::time::SystemTime::now()` or `std::time::Instant::now()`.

`clock.now()` returns a `CuTime` (a `u64` of nanoseconds since startup). In our simple
project we prefix the parameter with `_` because we don't use it. But on a real robot
you'd use it like this:

**Timestamp your output** (typical for source tasks):

```rust
fn process(&mut self, clock: &RobotClock, output: &mut Self::Output<'_>) -> CuResult<()> {
    output.set_payload(MyPayload { value: read_sensor() });
    output.tov = Tov::Time(clock.now());
    Ok(())
}
```

**Compute a time delta** (e.g., for a PID controller):

```rust
fn process(&mut self, clock: &RobotClock, input: &Self::Input<'_>, output: &mut Self::Output<'_>) -> CuResult<()> {
    let now = clock.now();
    let dt = now - self.last_time;  // CuDuration in nanoseconds
    self.last_time = now;

    let error = self.target - input.payload().unwrap().value;
    let correction = self.kp * error + self.ki * self.integral * dt.as_secs_f64();
    // ...
    Ok(())
}
```

**Detect a timeout**:

```rust
fn process(&mut self, clock: &RobotClock, input: &Self::Input<'_>) -> CuResult<()> {
    if input.payload().is_none() {
        let elapsed = clock.now() - self.last_seen;
        if elapsed > CuDuration::from_millis(100) {
            debug!("Sensor timeout! No data for {}ms", elapsed.as_millis());
        }
    }
    Ok(())
}
```

**Why not use the system clock?** Because Copper supports **deterministic replay**. When
you replay a recorded run, the runtime feeds your tasks the exact same clock values from
the original recording. If you used `std::time`, the replay would have different
timestamps and your tasks would behave differently. With `RobotClock`, same clock + same
inputs = same outputs, every time.

### The golden rule of `process()`

Because `process()` runs on the **real-time critical path** (potentially thousands of
times per second), you should avoid heap allocation inside it. Operations like
`Vec::push()`, `String::from()`, or `Box::new()` ask the system allocator for memory,
which can take an unpredictable amount of time and cause your cycle to miss its deadline.

Copper's architecture is designed so you never need to allocate in `process()`: messages
are pre-allocated, and the structured logger writes to pre-mapped memory. Keep your
`process()` fast and predictable.

---

So far we've focused on `new()` and `process()` -- the two methods you'll always
implement. But Copper tasks have a richer lifecycle with optional hooks for setup,
teardown, and work that doesn't need to run on the critical path. Let's look at that next.
