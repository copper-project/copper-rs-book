# Writing a Bridge

So far, our Copper apps have been made from sources, tasks, and sinks. Those are enough
when every endpoint is independent. A **bridge** is for the next case: one external
connection or protocol has several logical channels that should share the same state.

This chapter builds a tiny bridge with one incoming channel and one outgoing channel. It
does not talk to real hardware. That is intentional: the goal is to learn the bridge shape
without also learning serial ports, sockets, ROS 2, CAN, or motor protocols.

The bridge will keep two pieces of state:

```rust
connected: bool,
messages_seen: u64,
```

`connected` changes in the bridge lifecycle. `messages_seen` increments when the bridge
receives a command. When the bridge sends a status message, it can see the same
`messages_seen` value. That small bit of shared state is the reason this belongs in one
bridge instead of two unrelated tasks.

The graph will look like this:

```text
counter/command_in  ──▶  CountCommands  ──▶  counter/status_out
      Rx channel              task                 Tx channel
```

## Step 1: Add message types

Create a new file called `src/messages.rs`:

```rust
use bincode::{Decode, Encode};
use cu29::prelude::*;
use serde::{Deserialize, Serialize};

#[derive(Default, Debug, Clone, Serialize, Deserialize, Encode, Decode, Reflect)]
pub struct CommandPayload {
    pub requested_count: u64,
}

#[derive(Default, Debug, Clone, Serialize, Deserialize, Encode, Decode, Reflect)]
pub struct StatusPayload {
    pub cycles: u64,
}
```

These are normal Copper payloads. The bridge receives `CommandPayload` from the outside
world and sends `StatusPayload` back out.

**Checkpoint:** after this step, `src/messages.rs` should contain only payload types. It
should not mention bridges or tasks yet.

## Step 2: Add a task between the bridge channels

Edit `src/tasks.rs` and add this task:

```rust
use crate::messages::{CommandPayload, StatusPayload};
use cu29::prelude::*;

#[derive(Default, Reflect)]
pub struct CountCommands {
    cycles: u64,
}

impl Freezable for CountCommands {}

impl CuTask for CountCommands {
    type Resources<'r> = ();
    type Input<'m> = input_msg!(CommandPayload);
    type Output<'m> = output_msg!(StatusPayload);

    fn new(
        _config: Option<&ComponentConfig>,
        _resources: Self::Resources<'_>,
    ) -> CuResult<Self> {
        Ok(Self { cycles: 0 })
    }

    fn process<'i, 'o>(
        &mut self,
        _ctx: &CuContext,
        input: &Self::Input<'i>,
        output: &mut Self::Output<'o>,
    ) -> CuResult<()> {
        if input.payload().is_some() {
            self.cycles += 1;
            output.set_payload(StatusPayload {
                cycles: self.cycles,
            });
        } else {
            output.clear_payload();
        }
        Ok(())
    }
}
```

This task is deliberately small. It counts how many command messages reached it and emits
that count as status.

If your `tasks.rs` already has `use cu29::prelude::*;`, do not add it twice. Add only the
`use crate::messages::{CommandPayload, StatusPayload};` line and the `CountCommands`
struct/implementation.

**Checkpoint:** the task should compile as an ordinary `CuTask`: one input payload, one
output payload, no resources.

## Step 3: Declare bridge channels

Create a new file called `src/bridges.rs`:

```rust
use crate::messages::{CommandPayload, StatusPayload};
use cu29::prelude::*;

rx_channels! {
    pub struct CounterRxChannels : CounterRxId {
        command_in => CommandPayload = "counter/command_in",
    }
}

tx_channels! {
    pub struct CounterTxChannels : CounterTxId {
        status_out => StatusPayload = "counter/status_out",
    }
}
```

The `rx_channels!` macro declares channels that enter Copper from the outside world. The
`tx_channels!` macro declares channels that leave Copper for the outside world.

Each channel has three pieces:

| Piece | Example | Meaning |
|---|---|---|
| Channel id | `command_in` | Name used by the mission config |
| Payload type | `CommandPayload` | Message type on that channel |
| Default route | `"counter/command_in"` | External route/topic/path if the config does not override it |

**Checkpoint:** after this step, the bridge has channel declarations but no bridge struct
yet. That is normal.

## Step 4: Implement the bridge state

In the same `src/bridges.rs` file, add the bridge struct:

```rust
#[derive(Default, Reflect)]
pub struct CounterBridge {
    connected: bool,
    messages_seen: u64,
}

impl Freezable for CounterBridge {}
```

This is the shared state owned by the bridge instance.

For this tutorial, `messages_seen` is used only for debug output, so the empty
`Freezable` implementation is fine. If bridge state affects real outputs during replay,
implement `freeze` and `thaw` as shown in the previous chapter.

**Checkpoint:** the state should belong to the bridge, not to a global variable. Bridge
methods will receive `&mut self`, so they can update this state safely.

## Step 5: Implement `CuBridge::new`

Continue in `src/bridges.rs`:

```rust
impl CuBridge for CounterBridge {
    type Resources<'r> = ();
    type Tx = CounterTxChannels;
    type Rx = CounterRxChannels;

    fn new(
        _config: Option<&ComponentConfig>,
        _tx_channels: &[BridgeChannelConfig<<Self::Tx as BridgeChannelSet>::Id>],
        _rx_channels: &[BridgeChannelConfig<<Self::Rx as BridgeChannelSet>::Id>],
        _resources: Self::Resources<'_>,
    ) -> CuResult<Self>
    where
        Self: Sized,
    {
        Ok(Self {
            connected: false,
            messages_seen: 0,
        })
    }
```

Unlike a task constructor, a bridge constructor receives the configured Tx and Rx channel
lists. Real bridges use those lists to read routes, topic names, baud rates, QoS settings,
or other per-channel configuration. This first bridge ignores them.

**Checkpoint:** this code opens the `impl CuBridge for CounterBridge` block but does not
close it yet. The next steps add lifecycle, receive, and send methods inside the same
block.

## Step 6: Add lifecycle methods

Still inside the `impl CuBridge for CounterBridge` block, add:

```rust
    fn start(&mut self, _ctx: &CuContext) -> CuResult<()> {
        self.connected = true;
        debug!("CounterBridge connected");
        Ok(())
    }

    fn stop(&mut self, _ctx: &CuContext) -> CuResult<()> {
        self.connected = false;
        debug!("CounterBridge disconnected after {} messages", self.messages_seen);
        Ok(())
    }
```

`start` runs before bridge I/O begins. `stop` runs when the application shuts down. A real
bridge might open and close a serial port here. Our tutorial bridge only flips a boolean.

**Checkpoint:** after this step, `connected` is changed only by lifecycle methods. That
makes it easy to reason about.

## Step 7: Receive commands

Add the `receive` method inside the same `impl` block:

```rust
    fn receive<'a, Payload>(
        &mut self,
        _ctx: &CuContext,
        channel: &'static BridgeChannel<CounterRxId, Payload>,
        msg: &mut CuMsg<Payload>,
    ) -> CuResult<()>
    where
        Payload: CuMsgPayload + 'a,
    {
        match channel.id() {
            CounterRxId::CommandIn => {
                self.messages_seen += 1;
                msg.set_payload(Payload::default());
                debug!("CounterBridge received command {}", self.messages_seen);
            }
        }
        Ok(())
    }
```

The method is generic over `Payload` because a real bridge can have many Rx channels with
different payload types. This example has only one Rx channel, so the match has one arm.

The important part is the state change:

```rust
self.messages_seen += 1;
```

That state will still be available when the bridge sends status later in the same graph.

**Checkpoint:** `receive` should write into the provided `msg` buffer with
`msg.set_payload(...)`. Do not allocate a new message.

## Step 8: Send status

Finish the `impl CuBridge` block with `send` and the final closing brace:

```rust
    fn send<'a, Payload>(
        &mut self,
        _ctx: &CuContext,
        channel: &'static BridgeChannel<CounterTxId, Payload>,
        msg: &CuMsg<Payload>,
    ) -> CuResult<()>
    where
        Payload: CuMsgPayload + 'a,
    {
        match channel.id() {
            CounterTxId::StatusOut => {
                if self.connected {
                    debug!(
                        "CounterBridge sent status; bridge has seen {} commands",
                        self.messages_seen
                    );
                } else {
                    warn!("CounterBridge tried to send while disconnected");
                }
                debug!("Status payload present: {}", msg.payload().is_some());
            }
        }
        Ok(())
    }
}
```

This is where the example shows shared bridge state. `receive` increments
`messages_seen`; `send` reads it. Both methods are part of the same bridge instance.

**Checkpoint:** the `send` method should consume the `msg` passed by the runtime. It
should not call the `CountCommands` task directly. The graph decides what data reaches the
Tx channel.

## Step 9: Register the new modules

Edit `src/main.rs`. Near the existing module declarations, add:

```rust
pub mod bridges;
pub mod messages;
```

If your file already has:

```rust
pub mod tasks;
```

then the top of the file should now look like:

```rust
pub mod bridges;
pub mod messages;
pub mod tasks;
```

**Checkpoint:** `copperconfig.ron` will reference `bridges::CounterBridge`,
`tasks::CountCommands`, and `messages::...`, so all three modules must be visible from
the crate root.

## Step 10: Wire the bridge in `copperconfig.ron`

Replace the simple three-task pipeline with this bridge graph:

```ron
(
    tasks: [
        (
            id: "count_commands",
            type: "tasks::CountCommands",
        ),
    ],
    bridges: [
        (
            id: "counter",
            type: "bridges::CounterBridge",
            channels: [
                Rx(
                    id: "command_in",
                    route: "counter/command_in",
                ),
                Tx(
                    id: "status_out",
                    route: "counter/status_out",
                ),
            ],
        ),
    ],
    cnx: [
        (
            src: "counter/command_in",
            dst: "count_commands",
            msg: "messages::CommandPayload",
        ),
        (
            src: "count_commands",
            dst: "counter/status_out",
            msg: "messages::StatusPayload",
        ),
    ],
)
```

The important syntax is the endpoint path:

```text
bridge_id/channel_id
```

`counter/command_in` is an Rx channel, so it can only be a source endpoint.  
`counter/status_out` is a Tx channel, so it can only be a destination endpoint.

**Checkpoint:** the direction should read naturally:

```text
external command -> bridge Rx -> task -> bridge Tx -> external status
```

If you accidentally wire a Tx channel as a source, or an Rx channel as a destination,
Copper should reject the configuration.

## Step 11: Build and run

Run a compile check first:

```bash
cargo check
```

If that passes, run the app:

```bash
cargo run
```

You should see debug logs showing that the bridge connected, received commands, and sent
status messages. The exact output depends on your logger and monitor setup, but the
important pattern is:

```text
CounterBridge connected
CounterBridge received command 1
CounterBridge sent status; bridge has seen 1 commands
```

**Checkpoint:** if you see both receive and send logs, the bridge is wired correctly. If
you see receive logs but no send logs, check the `count_commands -> counter/status_out`
connection. If you see no bridge logs, check that `pub mod bridges;` exists in `main.rs`
and that `copperconfig.ron` has a `bridges` section.

## What this example leaves out

This bridge is intentionally fake. It does not open a socket, parse bytes, or talk to a
device. Those details are transport-specific, and adding them now would hide the important
shape:

- Declare Rx and Tx channels.
- Store shared state in the bridge struct.
- Use `start` and `stop` for connection lifecycle.
- Use `receive` to fill Copper messages from outside data.
- Use `send` to consume Copper messages and write them outside.
- Wire bridge channels with `bridge_id/channel_id` in `copperconfig.ron`.

Once that shape is clear, real bridges are mostly a matter of replacing the fake receive
and send bodies with protocol code.

## Examples to read next

After you finish this chapter, the cleanest examples to read are:

| Example | Why read it |
|---|---|
| [`examples/cu_bridge_test`](https://github.com/copper-project/copper-rs/tree/master/examples/cu_bridge_test) | Shows bridge scheduling and graph wiring with small in-repo bridge implementations. Start here if you want to see Rx-to-task, task-to-Tx, loopback, and fanout shapes. |
| [`examples/cu_resources_test/src/bridges.rs`](https://github.com/copper-project/copper-rs/blob/master/examples/cu_resources_test/src/bridges.rs) | Shows a compact custom bridge that receives injected resources. Read this after the resources chapter. |
| [`examples/cu_zenoh_bridge_demo`](https://github.com/copper-project/copper-rs/tree/master/examples/cu_zenoh_bridge_demo) | Shows a real middleware bridge used by two Copper apps. This is a good next step once the simple bridge API is familiar. |

There are also protocol-specific bridges such as MSP, CRSF, DSHOT, ROS 2, and Iceoryx2.
Those are useful references, but they are not the first examples to read: each one adds
domain-specific protocol details on top of the bridge mechanics.

## When to make a bridge

Use a bridge when the channels belong to the same external connection or protocol:

- One serial port with commands in and telemetry out
- One CAN bus with several message IDs
- One middleware session with several topics
- One ESC bus with command and telemetry channels

Use plain sources and sinks when the endpoints are independent and do not need shared
transport state.

## Summary

A bridge is not just a source and a sink placed next to each other. It is one component
that owns shared protocol state and exposes several typed channels to Copper. In this
chapter, `CounterBridge` owned `connected` and `messages_seen`; its Rx and Tx methods both
used that state through one bridge instance.

The small counter example is not useful as a robot driver, but it is useful as a template:
start with channel declarations, add the bridge state, implement `CuBridge`, and then wire
the channels into the graph.
