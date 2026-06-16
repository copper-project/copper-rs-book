# Thread Pools, Affinity, and Real-Time Scheduling

By default, Copper runs your task graph on one thread: the global loop executes
source -> processing -> sink back-to-back every cycle. Two features step outside that
single thread -- `background: true` tasks and the `parallel-rt` runtime -- and both need
worker threads to run on. This chapter is about controlling those workers: how many there
are, which CPU cores they run on, and what scheduling priority the OS gives them.

On a laptop the defaults are fine. On a real robot, where a latency-critical control loop
shares a machine with heavy background work (logging, vision, networking), you often want
to **isolate** the critical work onto dedicated cores and give it real-time priority so the
OS never lets background work preempt it. That is what thread pools, CPU affinity, and
real-time scheduling are for.

> **Note**: This is a `std`-only, host-side feature. On `no_std` / embedded targets there
> are no threads to schedule and this whole chapter does not apply.

## Declaring thread pools

Thread pools are declared in the `runtime` section of `copperconfig.ron`, next to
`rate_target_hz`:

```ron
runtime: (
    thread_pools: [
        ( id: "rt",         threads: 4, affinity: [2, 3, 4, 5], policy: Fifo(priority: 80) ),
        ( id: "background", threads: 2, affinity: [0, 1] ),
        ( id: "vision",     threads: 2, policy: Nice(10), on_error: Strict ),
    ],
),
```

Each pool has:

- **`id`** -- a unique name. Tasks and the runtime refer to pools by this name. Two names
  are reserved (see below): `background` and `rt`.
- **`threads`** -- how many worker threads the pool runs.
- **`affinity`** (optional) -- the CPU cores the workers may run on.
- **`policy`** (optional) -- the OS scheduling policy and priority. Defaults to `Fair`.
- **`on_error`** (optional) -- what to do if the affinity or policy cannot be applied.
  Defaults to `Warn`.

> Earlier versions of Copper configured background threads through a `threadpool`
> **resource bundle**. That still works -- an existing `threadpool` resource is migrated
> automatically into a `background` pool -- but `runtime.thread_pools` is the way forward.

## Scheduling policies

The `policy` controls how the OS scheduler treats the pool's worker threads. On Linux these
map directly onto the POSIX scheduling policies.

| Policy | What it is | When to use it |
|---|---|---|
| `Fair` | Normal fair time-sharing (`SCHED_OTHER` / CFS). The OS shares the CPU across threads and nothing starves. | The default. Everything that is not latency-critical. |
| `Nice(n)` | Fair scheduler with a niceness bias, `n` in `-20..=19` (lower is more favorable). A soft hint, not a guarantee. | Bias a pool below or above normal work without leaving the fair scheduler -- e.g. `Nice(10)` for heavy work that should yield to the control loop. |
| `Fifo(priority: p)` | `SCHED_FIFO` hard real-time, `p` in `1..=99`. Runs ahead of every fair thread and is **not** time-sliced -- it runs until it blocks or a higher-priority thread preempts it. | The latency-critical pipeline. Pin it with `affinity` so a busy worker cannot starve other work on the same core. |
| `RoundRobin(priority: p)` | `SCHED_RR`, same as `Fifo` except threads at the same priority are time-sliced in turn. | Several real-time workers that share a priority and should interleave fairly. |

> **Rule of thumb**: reach for `Nice` first. Real-time policies (`Fifo` / `RoundRobin`) are
> powerful but easy to misuse -- a busy `Fifo` worker with no `affinity` can starve the rest
> of the system. Use them for genuinely time-critical work, and pin them.

Real-time policies are **Linux-only** and usually require the `CAP_SYS_NICE` capability (run
as root, grant the capability, or raise the limit in `/etc/security/limits.conf`). On other
platforms only `Fair` and `Nice` apply; requesting `Fifo` / `RoundRobin` fails according to
the pool's `on_error` setting.

## CPU affinity

`affinity` is a list of logical CPU cores the pool's workers are allowed to run on. When
set, workers are pinned **Spread**: worker `i` is pinned to `affinity[i % affinity.len()]`.
So a pool with `threads: 4` and `affinity: [2, 3, 4, 5]` pins one worker to each of
cores 2-5:

```text
worker 0 -> core 2
worker 1 -> core 3
worker 2 -> core 4
worker 3 -> core 5
```

The point of affinity is **isolation**. If your real-time pool owns cores 2-5 and your
background pool is confined to cores 0-1, the OS will not schedule background work onto the
cores running your control loop. Combined with a `Fifo` policy, this is how you keep jitter
out of the critical path.

If you omit `affinity`, the OS is free to run the workers on any core.

## Reserved pools: `background` and `rt`

Two pool names have special meaning.

### `background`

When a source or task is marked `background: true`, it runs on the pool named `background`.
If you do not declare one, Copper creates a default `background` pool for you. Declare it
explicitly when you want to size it or pin it:

```ron
runtime: (
    thread_pools: [
        ( id: "background", threads: 2, affinity: [0, 1] ),
    ],
),
```

A task can also opt into a **different** pool with the object form of `background`:

```ron
(
    id: "detector",
    type: "vision::Detector",
    background: (pool: "vision"),
),
```

This runs `detector` on the `vision` pool instead of `background` -- useful when you want a
class of heavy tasks scheduled separately from the rest of your background work. See
[The Task Graph](./task-graph.md) for the `background` field, and
[Performance Basics](./performance-basics.md) for when backgrounding a stage is the right
call.

### `rt`

The pool named `rt` drives the [`parallel-rt`](./performance-basics.md) execution engine.
`parallel-rt` spawns one worker per generated process stage; defining an `rt` pool lets you
pin and prioritize those workers exactly like any other pool:

```ron
runtime: (
    thread_pools: [
        ( id: "rt", threads: 4, affinity: [2, 3, 4, 5], policy: Fifo(priority: 80) ),
    ],
),
```

The `rt` pool is consumed directly by the engine: its `affinity` and `policy` are applied
to the stage workers (Spread across the stage index), so unlike other pools you do not bind
tasks to it and you cannot use it as a `background` target.

## When it cannot be applied: `on_error`

Setting CPU affinity or a real-time priority can fail -- most commonly a `Fifo` priority
without `CAP_SYS_NICE`, or affinity to a core that does not exist. `on_error` chooses what
happens:

- **`Warn`** (default) -- log a warning and fall back to default scheduling. The pool still
  runs; it just does not get the requested affinity/priority. This keeps unprivileged
  dev/laptop runs working out of the box.
- **`Strict`** -- fail at startup. Use this on a deployed real-time robot, where running the
  control loop at default priority is a fault you want to catch loudly rather than discover
  as jitter in the field.

```ron
( id: "control", threads: 2, policy: Fifo(priority: 90), on_error: Strict ),
```

## The `rt-scheduling` feature

Affinity and scheduling are gated behind the `rt-scheduling` Cargo feature on `cu29`,
forwarded from your crate the same way as the other runtime features:

```toml
[features]
rt-scheduling = ["cu29/rt-scheduling"]
```

```bash
cargo run --features rt-scheduling
```

With the feature **off**, `runtime.thread_pools` still works -- pools are built with the
requested thread counts -- but `affinity` and `policy` are ignored and a warning is emitted.
This lets you keep one config that runs unprivileged in development and pins to real-time on
the target by flipping a feature flag. CPU affinity is cross-platform; the real-time
policies are Linux-only.

## Good fit / Bad fit

Good fit:

```text
core 0-1: background pool (logging, telemetry)   Nice / Fair
core 2-5: rt pool (control pipeline)             Fifo, pinned
```

Why:

- the critical pipeline owns dedicated cores at real-time priority
- everything else is confined elsewhere and yields to it

Bad fit:

```text
( id: "everything", threads: 8, policy: Fifo(priority: 99) )
```

Why:

- a single high-priority `Fifo` pool with no affinity, sized to every core, can starve the
  OS itself
- real-time priority is for isolating *specific* work, not for "make it all fast"

## Summary

| Field | Purpose | Default |
|---|---|---|
| `id` | Pool name; `background` and `rt` are reserved | -- (required) |
| `threads` | Number of worker threads | -- (required) |
| `affinity` | CPU cores the workers are pinned to (Spread) | unpinned |
| `policy` | OS scheduling policy/priority | `Fair` |
| `on_error` | Behavior when affinity/policy cannot be applied | `Warn` |

For complete working examples, see
[`examples/cu_background_task`](https://github.com/copper-project/copper-rs/tree/master/examples/cu_background_task)
(both `background` forms) and
[`examples/cu_runtime_matrix`](https://github.com/copper-project/copper-rs/tree/master/examples/cu_runtime_matrix)
(`rt` and `background` pools).
