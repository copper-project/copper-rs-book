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
as root, grant the capability, or raise the limit in `/etc/security/limits.conf`). Negative
niceness (`Nice(-1)` and below) needs the same capability -- without it the request falls
back per the pool's `on_error`. On non-Linux hosts only `Fair` is applied directly; `Nice`,
`Fifo`, and `RoundRobin` all fail according to the pool's `on_error`. CPU affinity is
cross-platform regardless.

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

### Choosing cores

Copper does not auto-detect kernel work or CPU topology -- the `affinity` list is taken at
face value. Two things on Linux are worth checking before you pick cores for a
latency-critical pool:

- **Where the kernel handles IRQs.** Hardware interrupts (NIC, NVMe, USB, timers) run on
  whichever CPUs the kernel binds them to, and a busy IRQ adds jitter to that core.
  `cat /proc/interrupts` shows per-CPU interrupt counts;
  `cat /proc/irq/<n>/smp_affinity_list` shows the affinity of a specific IRQ. By default
  most distros either pin IRQs to CPU 0 or let `irqbalance` spread them; either way, the
  conservative move is to keep your real-time `affinity` off the cores that show large
  counts in `/proc/interrupts`. For full isolation, the standard tool is the kernel command
  line (`isolcpus=`, `nohz_full=`, `rcu_nocbs=`), which removes the listed cores from the
  general scheduler entirely.
- **Hyperthread siblings.** Two logical CPUs that share one physical core compete for the
  same execution units, so pinning a real-time pool across a sibling pair gives almost no
  isolation from background work landing on the other sibling. `lscpu -e` shows the
  `CORE`/`CPU` mapping; `/sys/devices/system/cpu/cpuN/topology/thread_siblings_list` gives
  the pair directly. The conservative move is to pick one logical CPU per physical core for
  the `rt` pool and leave the siblings to `background` or to the OS.

The explicit list is intentionally the lowest-level knob -- a list of logical CPU ids the
OS understands -- and there are no higher-level selectors (`BigCores`, `NumaNode`, "avoid
IRQs", "avoid siblings") yet. Future versions can layer those on top without changing the
list form, so the recommendation today is to inspect your target machine with the tools
above and write the list explicitly.

## Reserved pools: `background` and `rt`

Two pool names have special meaning.

### `background`

When a source or task is marked `background: true`, it runs on the pool named `background`.
If you do not declare one, Copper creates a default `background` pool for you: 2 worker
threads, no affinity, `Fair` scheduling. Declare it explicitly when you want to size it or
pin it:

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
class of heavy tasks scheduled separately from the rest of your background work. The pool
name is resolved at build time: referencing a pool that isn't declared in
`runtime.thread_pools`, or pointing a background task at the reserved `rt` pool, is a
compile-time error.

See [The Task Graph](./task-graph.md) for the `background` field, and
[Performance Basics](./performance-basics.md) for when backgrounding a stage is the right
call.

### `rt`

The `rt` in `parallel-rt` stands for **runtime** -- the generated execution engine that
runs the task graph -- not "real-time". The pool named `rt` is the one the runtime looks
for to drive the [`parallel-rt`](./performance-basics.md) engine: it spawns one worker per
generated process stage, and the `rt` pool lets you pin and prioritize those workers
exactly like any other pool:

```ron
runtime: (
    thread_pools: [
        ( id: "rt", threads: 4, affinity: [2, 3, 4, 5], policy: Fifo(priority: 80) ),
    ],
),
```

The `rt` pool is consumed directly by the engine: only its `affinity` and `policy` are
applied to the stage workers (Spread across the stage index). `parallel-rt` spawns one
worker per generated process stage, so the `threads:` field has no effect on the `rt` pool
-- size `affinity` to match the stage count if you want exact one-core-per-stage pinning.
Unlike other pools, you do not bind tasks to it and you cannot use it as a `background`
target.

## When it cannot be applied: `on_error`

Setting CPU affinity or a real-time priority can fail. The common cases are platform-
specific: on **Linux**, a `Fifo` / `RoundRobin` priority (or `Nice` below 0) without
`CAP_SYS_NICE`; on **Windows**, any non-`Fair` policy at all, since the POSIX real-time
policies are not implemented there; and on either OS, an `affinity` entry that names a
core the machine does not have. `on_error` chooses what happens:

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

## Determinism and replay

Pool configuration is **performance-only**. Affinity and policy change when and where work
runs, never what each task computes or in what order results commit to a copperlist. By
design, swapping in or out an `rt` pool produces a bit-identical normalized CopperList
stream in both sync and `parallel-rt` modes, and the runtime matrix integration tests guard
this as a regression.

The practical consequence is that an offline replay or `resim` run on a different machine
keeps producing the same output as the live capture, even when the pool config cannot be
honored: with the default `on_error: Warn` the runtime logs and falls back to default
scheduling, and the stream is unchanged. If you need to *force* neutralization (for
example, to suppress warnings on a CI host that cannot pin, or to pick cores at runtime),
mutate `config.runtime.thread_pools` before building the app.

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
