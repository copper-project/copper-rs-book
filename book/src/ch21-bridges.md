# Bridges

So far we've focused on tasks that live entirely inside Copper: sources, processing tasks,
and sinks, all wired in `copperconfig.ron` and running in the same deterministic process.
But real robots often need to talk to the outside world -- existing ROS 2 stacks,
telemetry servers, simulators, or other processes written in different languages.

**Bridges** are Copper tasks that sit at the boundary between the Copper task graph and
external systems. They translate between Copper's in-memory message passing and whatever
protocol or middleware the external system uses.

## Why bridges?

You might want a bridge to:

- **Integrate with ROS 2** -- Keep your existing ROS nodes (navigation, simulation,
  tooling) while moving performance-critical pipelines (perception, control) into Copper.
- **Talk to other processes** -- Send data to a Rust service, a Python script, or a
  cloud backend without pulling those into the Copper scheduler.
- **Progressive migration** -- Run Copper and ROS 2 side by side and move functionality
  from one to the other over time, without a big-bang rewrite.

Bridges are regular Copper tasks: they implement `CuSrcTask`, `CuTask`, or `CuSinkTask`,
and you wire them in `copperconfig.ron` like any other component. The only difference is
that they also perform I/O with an external system (network, IPC, etc.).

## Zenoh as the bridge layer

Copper's bridges use [Zenoh](https://zenoh.io/) as the **middleware** between Copper and
the rest of the world. Zenoh is a pub/sub and storage protocol that can run over shared
memory, UDP, TCP, or other transports. It is lightweight and has first-class support for
**ROS 2 compatibility**: Copper can publish and subscribe to data that ROS 2 nodes see as
normal DDS topics when they use the `rmw_zenoh` RMW implementation.

Conceptually:

```text
  Copper task graph                    Zenoh                    External world
  ┌─────────────────┐                  ┌─────┐                  ┌─────────────┐
  │  Source / Task  │──▶ Bridge sink ─▶│     │──▶ ROS 2 topic   │ ROS 2 node  │
  └─────────────────┘                  │     │                  └─────────────┘
                                       │Zenoh│
  ┌─────────────────┐                  │     │                  ┌─────────────┐
  │  Bridge source  │◀── Zenoh topic ◀─│     │◀── ROS 2 topic   │ ROS 2 node  │
  └────────┬────────┘                  └─────┘                  └─────────────┘
           │
           ▼
  ┌─────────────────┐
  │  Task / Sink    │
  └─────────────────┘
```

- A **bridge sink** is a Copper sink task that takes the output of upstream Copper tasks
  and publishes it to a Zenoh (or ROS-compatible) topic. Data flows *out* of Copper.
- A **bridge source** is a Copper source task that subscribes to a Zenoh (or
  ROS-compatible) topic and injects received messages into the task graph. Data flows
  *in* to Copper.

A single bridge can be **both** a sink and a source: it may have Tx channels (sending
commands or data out) and Rx channels (receiving sensor or status data in). Many
hardware drivers are implemented this way — for example, the **cu_feetech** bridge
talks to Dynamixel-style servos over serial (e.g. the SO101 arm) and exposes both
joint commands (Tx) and joint state feedback (Rx) in the same component.

In hardware and middleware jargon, **Tx** (transmit) is the direction out of Copper — the
bridge sink sends data to the external system. **Rx** (receive) is the direction in —
the bridge source receives data from the external system and feeds it into the graph.

In the config, bridges that expose multiple channels declare **Tx** and **Rx** entries
with an `id` and a message type (or route). You then wire tasks to them in `cnx` using
`bridge_id/channel_id`. For example, from the copper-rs runtime tests
(`core/cu29_runtime/tests/sim_bridge_config.ron`):

```ron
bridges: [
    (
        id: "bridge",
        type: "DummyBridge",
        channels: [
            Tx(id: "tx", msg: "Ping"),
            Rx(id: "rx", msg: "Pong"),
        ],
    ),
],
cnx: [
    (src: "src", dst: "bridge/tx", msg: "Ping"),
    (src: "bridge/rx", dst: "sink", msg: "Pong"),
],
```

Here, `src` feeds the bridge's **Tx** channel (data leaves Copper), and **Rx** is the
source for `sink` (data that arrived from outside). The Zenoh bridge demo
(`examples/cu_zenoh_bridge_demo/`) uses the same pattern with multiple Tx/Rx channels
and Zenoh routes.

So from the point of view of your `copperconfig.ron`, a bridge source is just another
source, and a bridge sink is just another sink. You connect them with `cnx` exactly as
you would connect a sensor driver or an actuator.

## What lives in the components

The copper-rs repository provides bridge components under `components/bridges/`:

- **Zenoh bridge** -- Generic publish/subscribe over Zenoh. Useful when the other side is
  another Copper app, a custom Rust service, or anything that speaks Zenoh.
- **ROS 2 bridge** -- Same idea, but the messages are serialized in a way that ROS 2
  nodes understand. When your ROS 2 stack uses the Zenoh RMW, those nodes see Copper's
  traffic as normal ROS 2 topics. You don't need to run a separate "bridge process" --
  Copper publishes and subscribes directly.
- **cu_feetech bridge** -- Connects to Dynamixel-style servos over serial (e.g. the
  SO101 arm): it is both a sink (joint commands out) and a source (joint state feedback in).

For concrete examples, see the [bridges directory on GitHub](https://github.com/copper-project/copper-rs/tree/master/components/bridges) (e.g. `cu_zenoh_bridge`, `cu_zenoh_ros_sink`, and the workspace template's `cu_example_shared_bridge`).

These components are crates like any other: you add them as dependencies, reference their
task types in `copperconfig.ron`, and configure topic names and message types. The next
chapter walks through a concrete example: a ROS 2 node publishing integers, a Copper task
that turns them into a string, and a bridge sink that publishes that string back to ROS 2
so you can see it with standard ROS tools.

## Difference with ROS

In ROS 2, "bridging" to another middleware or system usually means running an extra node
(e.g. `ros1_bridge`) that subscribes on one side and publishes on the other. The bridge
is a separate process with its own scheduling and failure mode.

In Copper, a bridge is a **task inside your graph**. It runs in the same process, on the
same clock, and you can place it exactly where you need it in the data flow. You get
compile-time wiring and a single binary; the "external" side is just the Zenoh (or ROS 2)
topic name and message type you configure.

| | ROS 2 (typical) | Copper |
|---|---|---|
| **Bridge** | Separate bridge node/process | Task in the graph (sink or source) |
| **Configuration** | Launch file + topic remapping | `copperconfig.ron` + component config |
| **Scheduling** | Independent of your nodes | Same deterministic loop as the rest of the graph |
| **Middleware** | DDS (or RMW) | Zenoh (ROS 2 via rmw_zenoh) |

Next we'll put this into practice with a small ROS 2 ↔ Copper example.
