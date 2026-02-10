# What is Copper RS?

Copper is a **deterministic robotics runtime** written in Rust. Think of it as a "game engine for robots": describe your system declaratively and Copper will create a custom scheduler and run it deterministically from cloud simulation down to embedded controllers.

## The big idea

You describe your robot as a **task graph** -- a directed graph of components that produce,
process, and consume data. Copper reads this graph at **compile time** and generates a
custom **deterministic scheduler**. At runtime, your tasks execute in a precise,
pre-computed order with zero overhead.

```text
  ┌──────────┐     ┌──────────┐     ┌──────────┐
  │  Sensor  │────▶│ Algorithm│────▶│ Actuator │
  │  (Source)│     │  (Task)  │     │  (Sink)  │
  └──────────┘     └──────────┘     └──────────┘
```

## Key features


- **Rust-first** -- Ergonomic and safe.
- **Sub-microsecond latency** -- Zero-alloc, data-oriented runtime.
- **Deterministic replay** -- Every run, bit-for-bit identical.
- **Interoperable with ROS 2** -- Bridges via Zenoh, opening the path for a progressive
  migration.
- **Runs anywhere** -- From Linux servers, workstations, and SBCs to bare-metal MPUs.
- **Built to ship** -- One stack from simulation to production.


## How it works (in 30 seconds)

1. You define your tasks (Rust structs that implement a trait).
2. You wire them together in a configuration file (`copperconfig.ron`).
3. A compile-time macro reads the config and generates the scheduler.
4. At runtime, Copper calls your tasks' `process()` methods in the optimal order, passing
   pre-allocated messages between them.

That's it. No topic discovery, no callback registration, no middleware configuration.
Define, wire, run.
