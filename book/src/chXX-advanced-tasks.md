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

This tells Copper "there's nothing to snapshot for this task."

### Stateful tasks

If your task maintains state that affects its behavior across cycles -- for example, a PID
controller accumulating error, a Kalman filter maintaining a covariance matrix, or a
counter tracking message sequence numbers -- you should implement the `freeze` and `thaw`
methods:

```rust
use cu29::prelude::*;

#[derive(Reflect)]
pub struct PidController {
    kp: f64,
    ki: f64,
    kd: f64,
    accumulated_error: f64,
    previous_error: f64,
}

impl Freezable for PidController {
    fn freeze<W: std::io::Write>(&self, writer: &mut W) -> CuResult<()> {
        // Serialize the fields that change at runtime
        writer.write_all(&self.accumulated_error.to_le_bytes())?;
        writer.write_all(&self.previous_error.to_le_bytes())?;
        Ok(())
    }

    fn thaw<R: std::io::Read>(&mut self, reader: &mut R) -> CuResult<()> {
        let mut buf = [0u8; 8];
        reader.read_exact(&mut buf)?;
        self.accumulated_error = f64::from_le_bytes(buf);
        reader.read_exact(&mut buf)?;
        self.previous_error = f64::from_le_bytes(buf);
        Ok(())
    }
}
```

**`freeze`** writes the task's mutable state into a byte stream. **`thaw`** reads it back.
The runtime calls these automatically at keyframe boundaries.

> **Rule of thumb**: Only serialize fields that change during `process()`. Configuration
> fields like `kp`, `ki`, `kd` are set once in `new()` and don't need to be frozen --
> they'll be reconstructed from `copperconfig.ron` during replay.

### When does this matter?

If you never use Copper's replay features, the empty `impl Freezable` is fine for every
task. But if you plan to record and replay robot runs (one of Copper's strongest features),
implementing `Freezable` correctly means the replay system can seek to any point in the
log efficiently rather than replaying from the start.

## `Resources` -- Hardware Injection

The `type Resources<'r>` associated type declares what **hardware or system resources** a
task needs. Resources represent physical endpoints -- serial ports, GPIO controllers, SPI
buses, cameras, network sockets -- or shared services that the runtime provides at
construction time.

### No resources

Most tasks in a simple project don't need external resources:

```rust
type Resources<'r> = ();
```

This means "give me nothing." The `_resources` parameter in `new()` is just `()`.

### Declaring a resource

On a real robot, a camera driver task might declare the resource it needs:

```rust
impl CuSrcTask for CameraDriver {
    type Resources<'r> = &'r CameraHandle;
    type Output<'m> = output_msg!(ImageFrame);

    fn new(
        _config: Option<&ComponentConfig>,
        camera: Self::Resources<'_>,
    ) -> CuResult<Self> {
        // `camera` is injected by the runtime based on copperconfig.ron
        Ok(Self { camera: camera.clone() })
    }

    // ...
}
```

The runtime knows how to create and inject the resource based on the task's configuration
in `copperconfig.ron`. This is similar to dependency injection in other frameworks.

### Why resources?

Resources solve a practical problem: hardware handles often can't (or shouldn't) be
created inside a task's `new()` method. They may require system-level initialization,
ordering constraints, or shared access across tasks. By declaring resources as an
associated type, the runtime manages their lifecycle and injection, keeping tasks focused
on data processing.

## Summary

| Feature | Purpose | When to customize |
|---|---|---|
| `#[derive(Reflect)]` | Runtime introspection for monitoring/simulation | Always use the derive; the feature flag controls cost |
| `impl Freezable` | State snapshots for deterministic replay | Implement `freeze`/`thaw` for stateful tasks |
| `type Resources<'r>` | Hardware/service dependency injection | Declare resource types when your task needs hardware handles |
