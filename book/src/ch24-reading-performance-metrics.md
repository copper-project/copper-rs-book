# Reading Performance Metrics

Performance tuning starts with the right numbers. In Copper, the useful views are already
built in:

- live, in the console monitor
- offline, from `log-stats`

If you have not added the monitor yet, start with [Adding the Console Monitor](./ch12-monitoring.md).
If you want offline stats from a log, see [Exporting Data to Other Formats](./ch20-export-formats.md).

## Live signals

### LAT tab

Use the latency tab when you want to know whether the problem is inside the DAG itself.

Look for:

- one task with a much larger mean or max than the others
- high jitter on one task
- a high End2End latency even though no single task stands out

What it usually means:

- one hot task: optimize that task, background it, or parallelize inside it
- many moderate CPU-bound tasks in a row: consider `parallel-rt`

### BW tab

Use the bandwidth tab when the DAG seems fine but the loop still feels too expensive.

This tab is the first place to look for:

- observed loop rate
- CopperList size
- raw memory throughput
- serialized size
- total disk write rate

What it usually means:

- latency is fine, but BW is high at the end of the cycle: consider `async-cl-io`
- disk / encoding numbers are simply too large: reduce what you log
- numbers are fine for a while, then the machine slows down: suspect writeback pressure and
  test `mmap-fsync`

### MEM tab

Use the memory pools tab when the system looks unstable or starts failing only under load.

Look for:

- used buffers close to total buffers
- handles in use staying high
- obvious pool exhaustion

What it usually means:

- increase pool sizes
- reduce how long buffers stay alive
- if many CopperLists are in flight, check whether your pool sizing still makes sense

## Offline signals with `log-stats`

The `log-stats` command adds two kinds of evidence:

- pipeline timing in `perf`
- per-edge size and throughput in `edges`

Typical command:

```bash
cargo run --features logreader --bin my-project-logreader -- \
    logs/my-project.copper log-stats --output stats.json --config copperconfig.ron
```

The most useful fields for tuning are:

| Field | Why it matters |
|---|---|
| `perf.end_to_end.*` | Confirms real pipeline latency over a recorded session |
| `perf.jitter.*` | Shows whether the problem is mostly spikes rather than mean cost |
| `edges[].avg_raw_bytes` | Shows which edge is large |
| `edges[].throughput_bytes_per_sec` | Shows which edge is pushing the most sustained traffic |
| `edges[].rate_hz` | Shows whether the effective rate on that edge matches your expectation |
| `edges[].none_samples` | Useful when a task sometimes emits nothing, especially with background behavior |

## Symptom to first metric

| Symptom | Check first |
|---|---|
| "The loop is too slow" | LAT tab, then End2End in `log-stats` |
| "Tasks look fine but the cycle still ends late" | BW tab |
| "It works for a while, then degrades" | BW tab over time, then test `mmap-fsync` |
| "One task is clearly the culprit" | LAT tab row for that task |
| "A specific edge is too heavy" | `avg_raw_bytes` and `throughput_bytes_per_sec` in `log-stats` |
| "The system fails only under load" | MEM tab |
| "Async or parallel mode did not help much" | Check whether `logging.copperlist_count` is too low |

## A simple workflow

1. Start with the LAT tab and BW tab.
2. Confirm the hypothesis with `log-stats`.
3. Change one knob at a time.
4. Re-run and compare the same metrics.

Then use the decision tree:

- [Troubleshooting Performance](./ch25-troubleshooting-performance.md)
