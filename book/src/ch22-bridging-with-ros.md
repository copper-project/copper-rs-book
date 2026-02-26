# Bridging with ROS

In this chapter we'll build a small example that connects ROS 2 and Copper: a ROS 2 node
publishes integers at 1 Hz, a Copper task receives them, formats a string, and publishes
it back to ROS 2 so you can see it with standard ROS tools. This demonstrates the full
round-trip: **ROS → Copper → ROS**.

## What we're building

```text
  ROS 2                          Copper
  ┌──────────────┐               ┌─────────────────────────────────────────┐
  │ Publisher    │   /counter    │ ROS 2 bridge (cu_ros2_bridge)           │
  │ Int32 1,2,3… │──────────────▶│ Rx: /counter ──▶ Format task (int→str)  │
  │ at 1 Hz      │               │                    │                    │
  └──────────────┘               │ Tx: /from_copper ◀─┘                    │
                                 └─────────────────────────────────────────┘
                                                                  │
  ┌──────────────┐               "Received from ROS: N, Publishing to ROS"
  │ Subscriber   │   /from_copper
  │ (topic echo) │◀────────────────────────────────────────────────────────
  └──────────────┘
```

You will need:

- A Copper workspace or project with the **cu_ros2_bridge** component (see the
  [copper-rs bridges](https://github.com/copper-project/copper-rs/tree/master/components/bridges/cu_ros2_bridge)).
- A ROS 2 environment. For Copper and ROS 2 to interoperate on the same topics, your
  ROS 2 stack should use the Zenoh RMW (`rmw_zenoh`). Make sure that you have a Zenoh router (`ros2 run rmw_zenoh_cpp rmw_zenohd`)

We'll assume a workspace layout similar to [From Project to Workspace](./ch15-workspace.md),
with an app and the bridge components as dependencies.

## Step 1: A ROS 2 node that publishes 1, 2, 3 at 1 Hz

This chapter assumes that you already have ROS2 knowledge and know how to run a ROS node to publish on a topic.  
First, create a simple ROS 2 node that publishes `std_msgs/Int32` on a topic called
`/counter`, incrementing every second. Here is a minimal Python example:

```python
#!/usr/bin/env python3
import rclpy
from rclpy.node import Node
from std_msgs.msg import Int32

class CounterNode(Node):
    def __init__(self):
        super().__init__("counter_node")
        self.publisher = self.create_publisher(Int32, "/counter", 10)
        self.timer = self.create_timer(1.0, self.tick)
        self.count = 0

    def tick(self):
        msg = Int32()
        msg.data = self.count
        self.publisher.publish(msg)
        self.get_logger().info(f"Publishing: {self.count}")
        self.count += 1

def main(args=None):
    rclpy.init(args=args)
    node = CounterNode()
    rclpy.spin(node)
    node.destroy_node()
    rclpy.shutdown()

if __name__ == "__main__":
    main()
```

Verify that you have data published on the topic.

```bash
ros2 topic echo /counter
```

## Step 2: Copper project setup

In your Copper app, add the **cu_ros2_bridge** dependency. In the app's `Cargo.toml`:

```toml
[dependencies]
cu29 = { workspace = true }
cu-ros2-bridge = { path = "../../components/bridges/cu_ros2_bridge" }
```

Paths depend on your workspace layout (see the
[cu_ros2_bridge README](https://github.com/copper-project/copper-rs/tree/master/components/bridges/cu_ros2_bridge) for details).

### Payload types

The bridge uses **i32** for the integer from ROS (`std_msgs/Int32`) and **String** for the
string we publish back. `cu_ros2_bridge` ships with codecs for both: no custom message
structs needed. ROS 2's `std_msgs/String` has a single `data` field; the bridge's
built-in `String` adapter maps to that shape so ROS subscribers see a normal string topic.

## Step 3: Define the bridge and the format task

**Bridge type** — `cu_ros2_bridge` is a bidirectional bridge: you define one type with
both Tx and Rx channels. In your app (e.g. in `main.rs` or a `bridges` module), declare
the channel sets and the bridge type:

```rust
pub mod bridges {
    use cu_ros2_bridge::Ros2Bridge;
    use cu29::prelude::*;

    tx_channels! {
        pub struct RoundtripTxChannels : RoundtripTxId {
            from_copper => String,
        }
    }

    rx_channels! {
        pub struct RoundtripRxChannels : RoundtripRxId {
            counter => i32,
        }
    }

    pub type Ros2RoundtripBridge = Ros2Bridge<RoundtripTxChannels, RoundtripRxChannels>;
}
```

**Format task** — A Copper task that receives the integer from the bridge Rx channel and
produces the string we send out on the Tx channel. In `tasks.rs`:

```rust
#[derive(Reflect)]
pub struct RosFormatTask {
    /// Last formatted message, so we republish it when there is no new ROS message this cycle.
    last_msg: String,
}

impl Freezable for RosFormatTask {}

impl CuTask for RosFormatTask {
    type Resources<'r> = ();
    type Input<'m> = input_msg!(i32);
    type Output<'m> = output_msg!(String);

    fn new(_config: Option<&ComponentConfig>, _resources: Self::Resources<'_>) -> CuResult<Self>
    where
        Self: Sized,
    {
        Ok(Self {
            last_msg: String::new(),
        })
    }

    fn process(
        &mut self,
        _clock: &RobotClock,
        input: &Self::Input<'_>,
        output: &mut Self::Output<'_>,
    ) -> CuResult<()> {
        if let Some(&n) = input.payload() {
            self.last_msg = format!("Received from ROS: {}, Publishing to ROS", n);
        }
        output.set_payload(self.last_msg.clone());
        Ok(())
    }
}
```

When the Copper control loop runs faster than the ROS publisher (e.g. Copper at 10 Hz,
ROS at 1 Hz), many cycles will have no new message on the Rx channel. The task keeps the
last formatted string in `last_msg` and republishes it on those cycles, so the bridge
keeps sending the last value to ROS instead of going silent until the next ROS message.

## Step 4: Wire the graph in copperconfig.ron

Declare the **single bridge** (with one Rx and one Tx channel) and the format task. In
`copperconfig.ron`:

```ron
(
    tasks: [
        (
            id: "ros_format",
            type: "tasks::RosFormatTask",
        ),
    ],
    bridges: [
        (
            id: "ros2",
            type: "bridges::Ros2RoundtripBridge",
            config: {
                "domain_id": 0,
                "namespace": "copper",
                "node": "counter_node",
                "zenoh_config_json": r#"{"mode": "client", "connect": {"endpoints": ["tcp/127.0.0.1:7447"]}}"#,
            },
            channels: [
                Rx(id: "counter", route: "/counter"),
                Tx(id: "from_copper", route: "/from_copper"),
            ],
        ),
    ],
    cnx: [
        (
            src: "ros2/counter",
            dst: "ros_format",
            msg: "i32",
        ),
        (
            src: "ros_format",
            dst: "ros2/from_copper",
            msg: "String",
        ),
    ],
    runtime: (rate_target_hz: 1)
)
```

Data from ROS on `/counter` enters the graph via the bridge's **Rx** channel
`ros2/counter`; the format task's output goes to the bridge's **Tx** channel
`ros2/from_copper`, which publishes to ROS on `/from_copper`. Bridge-level `config`
options (e.g. `zenoh_config_file`) are documented in the
[cu_ros2_bridge README](https://github.com/copper-project/copper-rs/tree/master/components/bridges/cu_ros2_bridge).

## Step 5: Run Copper and see the string on ROS

1. Start your ROS 2 counter node so `/counter` is publishing.
2. Run your Copper application (e.g. `cargo run` from your workspace).
3. In another terminal, with the same ROS 2 environment sourced, run:

```bash
ros2 topic echo /from_copper
```

You should see messages with the string "Received from ROS: 0, Publishing to ROS",
"Received from ROS: 1, Publishing to ROS", and so on, at about 1 Hz.

```shell
$ ros2 topic echo /from_copper
data: 'Received from ROS: 35, Publishing to ROS'
---
data: 'Received from ROS: 36, Publishing to ROS'
---
data: 'Received from ROS: 37, Publishing to ROS'
---
data: 'Received from ROS: 38, Publishing to ROS'
```

## Summary

- A **ROS 2 node** publishes integers on `/counter` at 1 Hz.
- The **cu_ros2_bridge** (bidirectional, over Zenoh) has an **Rx** channel on `/counter`
  and a **Tx** channel on `/from_copper`. The Rx channel feeds `i32` into the graph; the
  format task turns each into the string "Received from ROS: {n}, Publishing to ROS";
  the Tx channel publishes that string to ROS.
- **ROS 2** tools (`ros2 topic echo /from_copper`) show the string.

This round-trip shows how to plug ROS 2 data into Copper with a single bridge
component, process it with a deterministic task, and expose the result back to the ROS 2
world. From here you can add more channels or tasks using the same pattern.
