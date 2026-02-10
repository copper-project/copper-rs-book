# Writing Tasks: tasks.rs

In the previous chapters we looked at `copperconfig.ron` (the architecture) and message
payloads (the data). Now let's look at `tasks.rs` -- where the actual **behavior** lives.

Just like the task graph chapter, we'll start with the complete file and then break it
down piece by piece.

## The complete file

Here is the full `tasks.rs` from our template project:

```rust
use bincode::{Decode, Encode};
use cu29::prelude::*;
use serde::{Deserialize, Serialize};

// Define a message type
#[derive(Default, Debug, Clone, Encode, Decode, Serialize, Deserialize, Reflect)]
pub struct MyPayload {
    value: i32,
}

// Defines a source (ie. driver)
#[derive(Default, Reflect)]
pub struct MySource {}

impl Freezable for MySource {}

impl CuSrcTask for MySource {
    type Resources<'r> = ();
    type Output<'m> = output_msg!(MyPayload);

    fn new(_config: Option<&ComponentConfig>, _resources: Self::Resources<'_>) -> CuResult<Self>
    where
        Self: Sized,
    {
        Ok(Self {})
    }

    fn process(&mut self, _clock: &RobotClock, output: &mut Self::Output<'_>) -> CuResult<()> {
        output.set_payload(MyPayload { value: 42 });
        Ok(())
    }
}

// Defines a processing task
#[derive(Reflect)]
pub struct MyTask {}

impl Freezable for MyTask {}

impl CuTask for MyTask {
    type Resources<'r> = ();
    type Input<'m> = input_msg!(MyPayload);
    type Output<'m> = output_msg!(MyPayload);

    fn new(_config: Option<&ComponentConfig>, _resources: Self::Resources<'_>) -> CuResult<Self>
    where
        Self: Sized,
    {
        Ok(Self {})
    }

    fn process(
        &mut self,
        _clock: &RobotClock,
        input: &Self::Input<'_>,
        output: &mut Self::Output<'_>,
    ) -> CuResult<()> {
        debug!("Received message: {}", input.payload().unwrap().value);
        output.set_payload(MyPayload { value: 43 });
        Ok(())
    }
}

// Defines a sink (ie. actuation)
#[derive(Default, Reflect)]
pub struct MySink {}

impl Freezable for MySink {}

impl CuSinkTask for MySink {
    type Resources<'r> = ();
    type Input<'m> = input_msg!(MyPayload);

    fn new(_config: Option<&ComponentConfig>, _resources: Self::Resources<'_>) -> CuResult<Self>
    where
        Self: Sized,
    {
        Ok(Self {})
    }

    fn process(&mut self, _clock: &RobotClock, input: &Self::Input<'_>) -> CuResult<()> {
        debug!("Sink Received message: {}", input.payload().unwrap().value);
        Ok(())
    }
}
```

That's the entire file. Let's walk through it section by section.

## The imports

```rust
use bincode::{Decode, Encode};
use cu29::prelude::*;
use serde::{Deserialize, Serialize};
```

- **`cu29::prelude::*`** -- Brings in everything you need from Copper: task traits,
  `RobotClock`, `ComponentConfig`, `CuResult`, `Freezable`, `Reflect`, the `input_msg!` /
  `output_msg!` macros, and the `debug!` logging macro.
- **`bincode`** and **`serde`** -- For the serialization derives on `MyPayload` (covered in
  the [Defining Messages](./ch06-messages.md) chapter).

## The message type

```rust
#[derive(Default, Debug, Clone, Encode, Decode, Serialize, Deserialize, Reflect)]
pub struct MyPayload {
    value: i32,
}
```

We already covered this in the previous chapter. This is the data that flows between tasks
through the connections defined in `copperconfig.ron`.

## The three task traits

The file defines three structs, each implementing a different trait. Copper provides
**three task traits** for the three roles a task can play in the pipeline:

| Trait | Role | Has Input? | Has Output? | ROS Analogy |
|---|---|---|---|---|
| `CuSrcTask` | Produces data | No | Yes | Publisher / driver node |
| `CuTask` | Transforms data | Yes | Yes | Subscriber + Publisher |
| `CuSinkTask` | Consumes data | Yes | No | Subscriber / actuator node |

Let's look at each one.

## Source Task: `CuSrcTask` -- `MySource`

```rust
#[derive(Default, Reflect)]
pub struct MySource {}

impl Freezable for MySource {}

impl CuSrcTask for MySource {
    type Resources<'r> = ();
    type Output<'m> = output_msg!(MyPayload);

    fn new(_config: Option<&ComponentConfig>, _resources: Self::Resources<'_>) -> CuResult<Self>
    where
        Self: Sized,
    {
        Ok(Self {})
    }

    fn process(&mut self, _clock: &RobotClock, output: &mut Self::Output<'_>) -> CuResult<()> {
        output.set_payload(MyPayload { value: 42 });
        Ok(())
    }
}
```

A source is the **entry point** of data into the pipeline. It has no input -- it generates
data, typically by reading from hardware (a camera, an IMU, a GPIO pin).

**What happens each cycle**: The runtime calls `process()`, and `MySource` writes a
`MyPayload { value: 42 }` into the pre-allocated output buffer. Downstream tasks will
read this value.

Notice the `process()` signature: it only has `output`, no `input`.

## Processing Task: `CuTask` -- `MyTask`

```rust
#[derive(Reflect)]
pub struct MyTask {}

impl Freezable for MyTask {}

impl CuTask for MyTask {
    type Resources<'r> = ();
    type Input<'m> = input_msg!(MyPayload);
    type Output<'m> = output_msg!(MyPayload);

    fn new(_config: Option<&ComponentConfig>, _resources: Self::Resources<'_>) -> CuResult<Self>
    where
        Self: Sized,
    {
        Ok(Self {})
    }

    fn process(
        &mut self,
        _clock: &RobotClock,
        input: &Self::Input<'_>,
        output: &mut Self::Output<'_>,
    ) -> CuResult<()> {
        debug!("Received message: {}", input.payload().unwrap().value);
        output.set_payload(MyPayload { value: 43 });
        Ok(())
    }
}
```

A processing task sits **in the middle** of the pipeline. It reads from upstream and writes
downstream.

**What happens each cycle**: The runtime first runs the upstream source, then calls this
task's `process()` with the source's output as `input`. The task reads the value, logs it,
and writes a new value to its own output for the sink downstream.

Notice the `process()` signature: it has **both** `input` and `output`.

## Sink Task: `CuSinkTask` -- `MySink`

```rust
#[derive(Default, Reflect)]
pub struct MySink {}

impl Freezable for MySink {}

impl CuSinkTask for MySink {
    type Resources<'r> = ();
    type Input<'m> = input_msg!(MyPayload);

    fn new(_config: Option<&ComponentConfig>, _resources: Self::Resources<'_>) -> CuResult<Self>
    where
        Self: Sized,
    {
        Ok(Self {})
    }

    fn process(&mut self, _clock: &RobotClock, input: &Self::Input<'_>) -> CuResult<()> {
        debug!("Sink Received message: {}", input.payload().unwrap().value);
        Ok(())
    }
}
```

A sink is the **end of the pipeline**. It receives data but produces no output. Typically
this drives an actuator, writes to a display, or sends data to an external system.

**What happens each cycle**: The runtime calls `process()` with the upstream task's output.
The sink reads the value and does something with it (here, it logs it).

Notice the `process()` signature: it only has `input`, no `output`.

## Tying it back to the task graph

Remember our `copperconfig.ron`:

```ron
tasks: [
    ( id: "src",  type: "tasks::MySource" ),
    ( id: "t-0",  type: "tasks::MyTask"   ),
    ( id: "sink", type: "tasks::MySink"   ),
],
```

Each `type` field points to one of the structs we just defined. The connections in `cnx`
determine which task's `output` feeds into which task's `input`. The Rust compiler verifies
that the message types match at build time.

In the next chapter, we'll dissect our task to look more closely at each associated type and method in order to
understand exactly what they do.
