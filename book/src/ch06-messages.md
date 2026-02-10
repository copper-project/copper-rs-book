# Defining Messages

Messages (also called **payloads**) are the data that flows between tasks. In ROS, you'd
define these in `.msg` files and run a code generator. In Copper, they're just Rust structs
with the right derives.

## A custom payload

Here's the message type from our template project (in src/tasks.rs):

```rust
use bincode::{Decode, Encode};
use cu29::prelude::*;
use serde::{Deserialize, Serialize};

#[derive(Default, Debug, Clone, Encode, Decode, Serialize, Deserialize, Reflect)]
pub struct MyPayload {
    value: i32,
}
```


## What each derive does

Every derive on a payload struct has a specific purpose:

| Derive | Purpose |
|---|---|
| `Default` | **Required.** Copper pre-allocates message buffers at startup. `Default` provides the initial "empty" value. |
| `Encode`, `Decode` | Binary serialization for Copper's zero-alloc message buffers and logging. These come from `cu-bincode`. |
| `Serialize`, `Deserialize` | Used for configuration parsing, log export (MCAP, JSON), and tooling. These come from `serde`. |
| `Reflect` | Runtime type introspection for monitoring tools and simulation integration. |
| `Debug` | Human-readable printing for development. |
| `Clone` | Allows copying messages when needed (e.g., forking data to multiple consumers). |

You do not really have to worry about all of these derives for now. Just add them each time you define a message, and we'll see how they come into action later.

## Using primitive types

For simple cases, you don't need a custom struct at all. Primitive types like `i32`, `f64`,
and `bool` already implement all the required traits:

```rust
// In copperconfig.ron:
//   msg: "i32"

// In your task:
type Output<'m> = output_msg!(i32);
```

This is great for prototyping. As your robot grows, you'll likely define richer message
types with multiple fields.

## Designing good payloads

A few tips for payload design:

- **Keep payloads small.** They're pre-allocated and copied between cycles. Large payloads
  waste memory and cache space.
- **Use fixed-size types.** Avoid `String` or `Vec` on the critical path. Prefer arrays,
  fixed-size buffers, or enums.
- **One struct per "topic".** Each connection in `copperconfig.ron` carries exactly one
  message type. If you need to send different kinds of data, define different structs and
  use separate connections.

## Example: an IMU payload

Here's what a more realistic payload might look like for an IMU sensor (from [here](https://github.com/copper-project/copper-rs/blob/master/components/payloads/cu_sensor_payloads/src/imu.rs#L16)):

```rust
#[derive(Default, Debug, Clone, Encode, Decode, Serialize, Deserialize, Reflect)]
pub struct ImuPayload {
    pub accel_x: Acceleration,
    pub accel_y: Acceleration,
    pub accel_z: Acceleration,
    pub gyro_x: AngularVelocity,
    pub gyro_y: AngularVelocity,
    pub gyro_z: AngularVelocity,
    pub temperature: ThermodynamicTemperature,
}
```

In the next chapter, we'll see how tasks produce and consume these messages.
