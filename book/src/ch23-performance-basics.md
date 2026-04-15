# Performance Basics

This chapter should serve two different readers:

- If you already know how Copper executes a cycle and you just want the knobs, jump to
  [Tuning Knob Reference](#tuning-knob-reference).
- If you are still building the mental model, read straight through, then continue to
  [Troubleshooting Performance](./ch25-troubleshooting-performance.md).

## Start with one simple idea

By default, Copper runs **one CopperList at a time on one thread**.

That is the baseline model. Most performance questions are just variations of:

- is one task too slow?
- is the end of the CopperList too slow?
- is the OS getting behind on disk writeback?
- does this graph have enough CPU work to profit from overlap?

Those are different problems, so they do not use the same tuning knob.

## What one Copper cycle looks like

At a high level, one cycle looks like this:

1. Create or reuse a CopperList.
2. Run the generated DAG in topological order.
3. Record timings and monitoring data.
4. Serialize and log the completed CopperList.
5. Recycle the CopperList and start the next cycle.

That last part is important. Even when the task path is fast, the cycle is not really over
until Copper has dealt with the finished CopperList.

## Two places where time is spent

When a user says "my loop is too slow", the time is usually being lost in one of two places:

### Inside the DAG

This means one or more tasks are expensive.

Typical signs:

- one task dominates the LAT tab
- end-to-end latency is high because task execution itself is high

Typical fixes:

- optimize one task
- run one task in the background
- parallelize inside one task
- use `parallel-rt` if the graph is a long CPU pipeline

### After the DAG finishes

This means the task work is acceptable, but the completed CopperList is expensive to finish.

Typical signs:

- task latencies look acceptable
- the BW tab shows significant serialization or disk cost

Typical fixes:

- `async-cl-io`
- reducing logged data
- `mmap-fsync` if the problem appears later under writeback pressure

## What Copper does with the finished CopperList

Copper's unified logger writes the finished CopperList to a memory-mapped log.

By default:

- the task outputs are serialized at the end of the cycle
- the logger writes to memory-mapped slabs
- when a section is closed, Copper asks the OS to flush that range asynchronously

This is usually fast enough, but it creates an important beginner trap:

- the system can look fine at first
- dirty pages accumulate in the background
- later, the machine starts paying the bill

So "it collapses after a while" is often a logging and writeback story, not a task story.

## What to do next

Once this mental model is clear, do not keep guessing. Look at the numbers:

- [Reading Performance Metrics](./ch24-reading-performance-metrics.md)
- [Troubleshooting Performance](./ch25-troubleshooting-performance.md)

The normal flow should be:

1. understand the baseline model
2. inspect LAT, BW, MEM, and `log-stats`
3. follow the troubleshooting tree
4. only then choose a tuning knob

## Tuning Knob Reference

This is the fast path for readers who already know what kind of bottleneck they have.

| Knob | What it changes | Typical symptom |
|---|---|---|
| `async-cl-io` | Moves CopperList serialization and logging to a dedicated thread | Task latencies are fine, but end-of-CL overhead is too high |
| `parallel-rt` | Pipelines multiple CopperLists across generated process stages | Several CPU-bound stages are back to back and the global rate is too low |
| `mmap-fsync` | Forces file `sync_all()` on section flush | The system runs fine for a while, then collapses under dirty-page / writeback pressure |
| `background: true` | Runs one compatible source or task on the background threadpool and returns `None` while it is still busy | One isolated stage is too slow, but it does not need to block every cycle |
| Task-local thread pool / parallel `for` | Parallelizes the internals of one task | One hot task has obvious internal data parallelism |
| `logging: (enabled: false)` or `enable_task_logging: false` | Reduces logged bytes | Bandwidth and serialized size are too high |
| `logging.copperlist_count` | Increases the number of preallocated in-flight CopperLists | Async or parallel modes stall because they run out of CopperList slots |

## Feature switches

The runtime features are Cargo features on `cu29`. A simple way to expose them in your app is
to forward them from your crate:

```toml
[features]
async-cl-io = ["cu29/async-cl-io"]
parallel-rt = ["cu29/parallel-rt"]
mmap-fsync = ["cu29/mmap-fsync"]
```

Then you can run:

```bash
cargo run --features async-cl-io
cargo run --features parallel-rt
cargo run --features mmap-fsync
```

## Two distinctions that matter

### `parallel-rt` is not the same as `background: true`

`parallel-rt` is a **runtime-level pipeline**. Multiple CopperLists can be in flight at the
same time, and each generated process stage keeps FIFO order for determinism.

`background: true` is a **stage-level escape hatch**. One source or task moves to the
background threadpool and may return `None` for some cycles while its previous run is still
finishing.

### `parallel-rt` is not the same as task-local parallelism

`parallel-rt` parallelizes the **DAG across CopperLists**.

Task-local parallelism parallelizes the **inside of one task**.

If one task is much heavier than the rest, fixing that task directly is often better than
adding runtime-level parallelism around it.

## Background tasks and the threadpool bundle

If a source or task is marked with `background: true`, Copper ensures a `threadpool` resource bundle is
available. If you do not provide one explicitly, the runtime creates a default one.

This makes background stages easy to turn on, but it does not mean they are always the right
choice. They work best when skipping or sampling intermediate cycles is acceptable.
