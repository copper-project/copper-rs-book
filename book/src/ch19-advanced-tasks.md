# Advanced Task Features

In the earlier chapters we treated `#[derive(Reflect)]`, `impl Freezable`, and
`type Resources<'r> = ()` as required boilerplate. This chapter explains what each of
these does and when you'd want to customize them.

## `#[derive(Reflect)]`

The `Reflect` derive macro enables **runtime introspection** on your task struct.
Monitoring tools and simulation environments use it to inspect a task's fields at runtime
without knowing the concrete type at compile time.

```rust
#[derive(Reflect)]
pub struct MyController {
    kp: f64,
    ki: f64,
    accumulated_error: f64,
}
```

With `Reflect` derived, a monitoring UI could display `kp`, `ki`, and
`accumulated_error` as live values while the robot is running.

When the `reflect` feature is disabled (which is the default in production builds), the
derive is a no-op -- it compiles but generates no code, so there is zero runtime cost.

**In practice**: always add `#[derive(Reflect)]` to your task structs. It costs nothing in
production and enables tooling when you need it.

## `Freezable` -- State Serialization

The `Freezable` trait enables Copper's **deterministic replay** system. The runtime
periodically takes "snapshots" (keyframes) of every task's internal state, much like
keyframes in a video codec. During replay, it can jump to any snapshot instead of
replaying from the very beginning.

### Stateless tasks

For tasks that hold no internal state (or state that can be trivially reconstructed), the
empty implementation is all you need:

```rust
impl Freezable for MySource {}
```

This tells Copper "there's nothing to snapshot for this task." This is what we've been
using throughout the book, and it's correct for all our tasks so far -- they don't carry
any state between cycles.

### Stateful tasks

If your task maintains state that affects its behavior across cycles -- for example, a PID
controller accumulating error, a Kalman filter maintaining a covariance matrix, or a
counter tracking message sequence numbers -- you should implement the `freeze` and `thaw`
methods.

The `Freezable` trait uses bincode's `Encoder` and `Decoder` for serialization:

```rust
use cu29::prelude::*;
use bincode::enc::Encoder;
use bincode::de::Decoder;
use bincode::error::{EncodeError, DecodeError};

#[derive(Reflect)]
pub struct PidController {
    kp: f64,
    ki: f64,
    kd: f64,
    accumulated_error: f64,
    previous_error: f64,
}

impl Freezable for PidController {
    fn freeze<E: Encoder>(&self, encoder: &mut E) -> Result<(), EncodeError> {
        // Serialize the fields that change at runtime
        bincode::Encode::encode(&self.accumulated_error, encoder)?;
        bincode::Encode::encode(&self.previous_error, encoder)?;
        Ok(())
    }

    fn thaw<D: Decoder>(&mut self, decoder: &mut D) -> Result<(), DecodeError> {
        self.accumulated_error = bincode::Decode::decode(decoder)?;
        self.previous_error = bincode::Decode::decode(decoder)?;
        Ok(())
    }
}
```

**`freeze`** serializes the task's mutable state using bincode's `Encode` trait.
**`thaw`** deserializes it back using `Decode`. The runtime calls these automatically at
keyframe boundaries.

> **Rule of thumb**: Only serialize fields that change during `process()`. Configuration
> fields like `kp`, `ki`, `kd` are set once in `new()` and don't need to be frozen --
> they'll be reconstructed from `copperconfig.ron` during replay.

### When does this matter?

If you never use Copper's replay features, the empty `impl Freezable` is fine for every
task. But if you plan to record and replay robot runs (one of Copper's strongest features),
implementing `Freezable` correctly means the replay system can seek to any point in the
log efficiently rather than replaying from the start.

Think of it like a video file: without keyframes, you'd have to decode from the beginning
every time you want to seek. With keyframes (state snapshots), you can jump to any point
and resume from there. `Freezable` is how Copper creates those keyframes for your task's
internal state.

## `Resources` -- Hardware Injection

The `type Resources<'r>` associated type declares what **hardware or system resources** a
task needs. Resources represent physical endpoints -- serial ports, GPIO controllers, SPI
buses, cameras -- or shared services like a thread pool.

### No resources

Most tasks in a simple project don't need external resources:

```rust
type Resources<'r> = ();
```

This means "give me nothing." The `_resources` parameter in `new()` is just `()`. This is
what we've used throughout the book.

### The problem resources solve

On a real robot, a sensor driver needs access to a hardware peripheral -- say, a serial
port or an SPI bus. Where does that handle come from? You have a few options:

1. **Create it inside `new()`** -- Works, but what if two tasks need the same bus? Or if
   the hardware needs platform-specific initialization that your task shouldn't know about?

2. **Pass it as a global** -- Not great for testing, portability, or safety.

3. **Have the runtime inject it** -- This is what Resources does. You declare what you
   need, and the runtime provides it.

### How it works

Resources involve three pieces:

**1. A resource provider** (called a "bundle") is declared in `copperconfig.ron`:

```ron
resources: [
    (
        id: "board",
        provider: "crate::resources::BoardBundle",
        config: { "uart_device": "/dev/ttyUSB0" },
    ),
],
```

The bundle is a Rust type that knows how to create the actual hardware handles (open the
serial port, initialize GPIO, etc.).

**2. Tasks declare which resources they need** in `copperconfig.ron`:

```ron
(
    id: "imu",
    type: "tasks::ImuDriver",
    resources: { "serial": "board.uart0" },
),
```

This says: "the `imu` task needs a resource it calls `serial`, and it should be bound to
the `uart0` resource from the `board` bundle."

**3. The task declares a `Resources` type** in its Rust implementation that knows how to
pull the bound resources from the runtime's resource manager:

```rust
impl CuSrcTask for ImuDriver {
    type Resources<'r> = ImuResources<'r>;
    type Output<'m> = output_msg!(ImuData);

    fn new(
        config: Option<&ComponentConfig>,
        resources: Self::Resources<'_>,
    ) -> CuResult<Self> {
        // resources.serial is the hardware handle, injected by the runtime
        Ok(Self { port: resources.serial })
    }
    // ...
}
```

### Why this design?

Resources keep your tasks **portable**. An IMU driver doesn't need to know which serial
port to open -- that's a deployment detail. On one robot it might be `/dev/ttyUSB0`, on
another it might be a different bus entirely. By moving the hardware binding to the
configuration, the same task code works on different platforms without changes.

Resources can also be **shared**. A shared bus (like I2C) can be bound to multiple tasks.
The resource manager handles the ownership semantics: exclusive resources are moved to a
single task, shared resources are behind an `Arc` and can be borrowed by many.

### When do you need resources?

For the projects in this book, `type Resources<'r> = ()` is all you need. Resources become
important when you:

- Write drivers that talk to real hardware (serial, SPI, GPIO, USB)
- Need multiple tasks to share a hardware bus
- Want the same task to work across different boards without code changes
- Want to swap real hardware for mocks in testing

The `examples/cu_resources_test/` in the Copper RS repository is a complete working example
that demonstrates bundles, shared resources, owned resources, and mission-specific resource
bindings.

## Summary

| Feature | Purpose | When to customize |
|---|---|---|
| `#[derive(Reflect)]` | Runtime introspection for monitoring/simulation | Always use the derive; the feature flag controls cost |
| `impl Freezable` | State snapshots for deterministic replay | Implement `freeze`/`thaw` for stateful tasks |
| `type Resources<'r>` | Hardware/service dependency injection | Declare resource types when your task needs hardware handles |

For most of the projects you'll build while learning Copper, the defaults are fine:
`#[derive(Reflect)]` on the struct, empty `impl Freezable`, and `type Resources<'r> = ()`.
These become important as you move from prototyping to deploying on real hardware with
real replay requirements.
