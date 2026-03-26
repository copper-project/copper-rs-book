# Troubleshooting Performance

This chapter is meant to be navigated. Start at the first question and follow the links.

Before you start:

- use the LAT, BW, and MEM tabs from [Adding the Console Monitor](./ch12-monitoring.md)
- if you need offline evidence, generate `stats.json` with [`log-stats`](./ch20-export-formats.md#log-statistics)

## Start Here

### Q1: Are you missing your target rate?

- [Yes](#q2-are-you-actually-rate-limited-by-config)
- [No](#q6-is-the-problem-mostly-end-of-copperlist-overhead-or-late-collapse)

### Q2: Are you actually rate-limited by config?

Check `runtime.rate_target_hz`.

- [Yes](#rate-target-is-the-limiter)
- [No](#q3-is-one-task-clearly-dominating-the-latency-tab)

### Q3: Is one task clearly dominating the latency tab?

- [Yes](#q4-can-that-task-finish-later-without-blocking-every-cycle)
- [No](#q5-do-you-have-a-long-cpu-bound-pipeline)

### Q4: Can that task finish later without blocking every cycle?

- [Yes](#background-one-task)
- [No](#parallelize-inside-one-task)

### Q5: Do you have a long CPU-bound pipeline?

Think: several pure compute stages back to back, little blocking I/O, little waiting on
hardware.

- [Yes](#enable-parallel-rt)
- [No](#reduce-logging-volume)

### Q6: Is the problem mostly end-of-CopperList overhead or late collapse?

- Large end-of-cycle overhead right away, while task latencies are acceptable:
  [Enable `async-cl-io`](#enable-async-cl-io)
- The system runs well at first, then degrades over time:
  [Enable `mmap-fsync`](#enable-mmap-fsync)
- Neither:
  [Continue to Q7](#q7-are-you-pushing-too-much-data)

### Q7: Are you pushing too much data?

Check the BW tab and `log-stats`:

- large serialized CopperLists
- high disk write rate
- one edge with large `avg_raw_bytes` or `throughput_bytes_per_sec`

- [Yes](#reduce-logging-volume)
- [No](#q8-are-you-running-out-of-buffers-or-in-flight-copperlists)

### Q8: Are you running out of buffers or in-flight CopperLists?

- Pool pressure in MEM tab:
  [Tune memory pools](#tune-memory-pools)
- Too few in-flight CopperLists for async or parallel execution:
  [Increase CopperList slots](#increase-copperlist-slots)
- Neither:
  [Reduce thread oversubscription](#reduce-thread-oversubscription)

## Outcomes

## Rate Target Is the Limiter

If `runtime.rate_target_hz` is lower than the rate you want, Copper is doing exactly what you
asked.

```ron
runtime: (
    rate_target_hz: 100,
),
```

If you need a higher rate:

- raise `rate_target_hz`
- or remove it and run at best effort

If the system starts missing deadlines after that change, go back to [Q3](#q3-is-one-task-clearly-dominating-the-latency-tab)
or [Q5](#q5-do-you-have-a-long-cpu-bound-pipeline).

## Enable `async-cl-io`

Use this when the **task path is fine**, but the **end of the CopperList is too expensive**.

What it does:

- keeps the DAG execution on the main loop
- queues the completed CopperList to a dedicated serializer thread
- recycles the slot later when serialization finishes

Minimal feature forwarding:

```toml
[features]
async-cl-io = ["cu29/async-cl-io"]
```

```bash
cargo run --features async-cl-io
```

Good fit:

```text
src -> task_a -> task_b -> sink

The LAT tab looks acceptable, but BW shows large serialized CL cost.
```

Bad fit:

```text
src -> huge_cpu_task -> sink

The hot spot is inside huge_cpu_task itself. Moving CL serialization off-thread does not fix that.
```

Two checks after enabling it:

- if the benefit is small, your real bottleneck is elsewhere
- if the serializer now waits for free CopperLists, raise `logging.copperlist_count`

## Enable `parallel-rt`

Use this when you have **several CPU-bound stages back to back** and want higher global
throughput.

What it does:

- keeps deterministic FIFO order per generated process stage
- lets multiple CopperLists be in flight at the same time
- turns the runtime into a stage pipeline instead of a strictly one-CL-at-a-time loop

Minimal feature forwarding:

```toml
[features]
parallel-rt = ["cu29/parallel-rt"]
```

```bash
cargo run --features parallel-rt
```

Good fit:

```text
src -> cpu_a -> cpu_b -> cpu_c -> cpu_d -> sink
```

Why:

- many stages can work on different CopperLists at the same time
- no single stage is overwhelmingly larger than the others

Bad fit:

```text
src -> giant_cpu_task -> sink
```

Why:

- the giant task is still the throughput limiter
- you usually get more by optimizing or parallelizing that task directly

Also a poor fit:

```text
camera -> wait_for_io -> bridge -> sink
```

Why:

- the graph is dominated by waiting and I/O, not by a CPU pipeline

Two checks after enabling it:

- if workers look idle, you may need a larger `logging.copperlist_count`
- if throughput does not move, the graph probably lacks enough useful overlap

## Enable `mmap-fsync`

Use this when the system **runs well for a while, then starts degrading**, and you suspect the
OS is accumulating too many dirty pages from the memory-mapped logger.

What it does:

- keeps the memory-mapped logger
- adds synchronous file `sync_all()` on section flush
- trades peak throughput for more explicit writeback

Minimal feature forwarding:

```toml
[features]
mmap-fsync = ["cu29/mmap-fsync"]
```

```bash
cargo run --features mmap-fsync
```

Good fit:

```text
The robot behaves well for a while, BW looks reasonable, then the machine starts stalling.
```

Bad fit:

```text
The loop is already compute-bound from the first second.
```

After enabling it, measure the cost. If the throughput penalty is too large:

- reduce what you log
- experiment with `section_size_mib` and `slab_size_mib`
- or accept the default async writeback and provision the storage path better

## Background One Task

Use this when **one isolated task** is too slow, but it does not need to block the whole loop.

```ron
(
    id: "heavy",
    type: "tasks::HeavyTask",
    background: true,
),
```

What it means semantically:

- Copper runs that task on the background threadpool
- while it is still busy, `process()` returns `None`
- downstream tasks therefore see missing output for some cycles

Good fit:

```text
src -> heavy_optional_stage -> sink
```

Why:

- it is acceptable for the stage to sample or skip intermediate cycles

Bad fit:

```text
src -> estimator -> controller -> actuator
```

Why:

- the controller path usually needs one coherent output per cycle

Copper will ensure a `threadpool` resource bundle exists when background tasks are present.
If you need a specific sizing, provide that bundle explicitly instead of relying on the
default.

## Parallelize Inside One Task

Use this when the real bottleneck is **inside one task**, not in the DAG structure.

Typical cases:

- per-pixel or per-point computation
- large reduction or map kernels
- CPU-heavy loops that can be split cleanly

Preferred approach:

- keep the DAG simple
- add a thread pool in resources or use a controlled parallel loop inside the task
- measure the task again in the LAT tab

Good fit:

```text
src -> expensive_image_task -> sink
```

Bad fit:

```text
The real issue is serialized logging or OS writeback.
```

## Reduce Logging Volume

Use this when BW and `log-stats` show that the logger is simply carrying too much data.

The first lever is per-task logging:

```ron
(
    id: "fast-sensor",
    type: "tasks::FastSensor",
    logging: (enabled: false),
),
```

The second lever is global task logging:

```ron
logging: (
    enable_task_logging: false,
),
```

Good fit:

```text
One or two high-rate edges dominate avg_raw_bytes and throughput_bytes_per_sec.
```

Bad fit:

```text
The hot spot is a CPU-heavy task, but the logged payloads are small.
```

The practical rule is simple:

- keep logging on for the edges you actually need for replay or diagnosis
- turn it off for bulky intermediate traffic first

## Increase CopperList Slots

Use this when async or parallel execution is underfilled because there are not enough
preallocated CopperLists available.

```ron
logging: (
    copperlist_count: 8,
),
```

This value is consumed by the generated runtime, so it needs to be compiled into the binary.

Good fit:

```text
async-cl-io or parallel-rt is enabled, but the runtime still behaves as if only a tiny number
of CopperLists can be active.
```

Bad fit:

```text
The graph has no useful overlap to exploit.
```

More slots help only when there is real work to overlap.

## Tune Memory Pools

Use this when the MEM tab shows pressure on pooled buffers or handles.

Good fit:

```text
handle-backed payloads stay alive across several stages and the pool remains near full.
```

Actions:

- increase pool size
- reduce payload lifetime
- reduce the number of simultaneously retained CopperLists if that is what keeps the buffers
  alive

Bad fit:

```text
The pool is healthy and the real issue is CPU or disk.
```

## Reduce Thread Oversubscription

Use this when you stacked too many concurrency mechanisms at once:

- `parallel-rt`
- several `background: true` tasks
- task-local Rayon pools or custom worker pools

Symptoms:

- throughput does not improve
- jitter gets worse
- the machine is busy, but the useful rate barely moves

The fix is usually to simplify first:

- use `parallel-rt` for DAG-level overlap
- use `background: true` for one isolated non-blocking stage
- use task-local parallelism for one hot algorithm

Do not enable all three everywhere by default.
