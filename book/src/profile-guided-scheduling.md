# Profile-Guided Scheduling

Profile-Guided Scheduling (PGS) uses timings from a representative Copper run to propose
execution schedules for your application. It is an offline workflow: the robot records its
normal unified log, a host-side logreader generates candidates, and you rebuild and measure
those candidates before selecting one.

The important rule is: **a prediction is a candidate to test, not a result to deploy**.
Task costs change when work is moved between CPUs, caches, and scheduling policies. The
measured ranking can select the original schedule, and that is a valid outcome.

The complete loop is:

```text
representative baseline -> contract -> predicted candidates -> candidate runs -> measured selection
```

PGS changes the execution plan: which worker runs each operation, the order on each worker,
CPU placement, and how many CopperLists may be in flight. It does not change the task graph
or task implementations. Generated candidates are normal explicit Copper plans, validated
against the static graph at build time.

## Before you start

Use the same application revision, target-class machine, launch options, and representative
workload throughout the comparison. A desktop profile is useful for testing the workflow,
but it does not predict a robot computer with different CPUs, devices, or load.

You need:

1. An application-specific logreader using `cu29_export::run_cli`, as described in
   [Logging and Replaying Data](./logging-replay.md).
2. A unified log from one mission with runtime lifecycle records and CopperList process
   timestamps.
3. Payload presence logged at the endpoints of every latency chain.
4. The `parallel-rt` feature forwarded by the application, as described in
   [Performance Basics](./performance-basics.md#feature-switches).

For handle-backed payloads, `handle_content: none` is sufficient for PGS: it preserves
message metadata and handle presence without recording the referenced buffer. A terminal
sink has no output payload, so PGS infers that it fired from its directly connected
producer. Keep payload presence for that producer as well.

Record long enough to cover steady state, periodic firing patterns, bursts, and the slow
paths that matter to the robot. PGS requires only two firings for a contracted source, but
two samples are not a useful latency distribution.

## 1. Write the scheduling contract

The contract states what the application needs and which machine resources PGS may use. Put
it in a separate file such as `schedule.ron`:

```ron
(
    chains: [
        (
            id: "sense_to_command",
            source: "camera",
            sink: "motor_command",
            deadline_ms: 20,
        ),
    ],
    sources: [
        (
            task: "camera",
            period_ms: 10,
        ),
    ],
    cpus: [2, 3, 4, 5],
    max_in_flight: 4,
    headroom: 0.2,
    worker_policy: Fair,
)
```

| Field | Meaning | How to choose it |
|---|---|---|
| `chains` | End-to-end paths whose latency matters | Name a source, a reachable sink, and the real application deadline |
| `sources` | Input delivery requirements | Give the expected period of sources whose throughput must be preserved; omit sources you do not want scored |
| `cpus` | Exact logical CPUs available to generated workers | Reserve CPUs intentionally; inspect affinity, IRQ load, and sibling cores as described in [Thread Pools](./thread-pools.md) |
| `max_in_flight` | Largest pipeline depth PGS may explore | Start conservatively; emitted configs raise `logging.copperlist_count` when needed, which increases preallocated memory |
| `headroom` | Fraction of deadlines and worker windows kept free | `0.2` means candidates enter the headroom penalty above 80% utilization |
| `worker_policy` | Policy applied to generated workers | Start with `Fair`; `Fifo(priority: N)` and `RoundRobin(priority: N)` require deployment support and leave two higher priorities for PGS |

A chain sample is the sink's process end minus the source's time of validity. If the source
did not set a time of validity, its process start is used. Every chain id must be unique,
every deadline and source period must be positive, and every sink must be reachable from its
source in the selected mission.

## 2. Record the baseline

Run the normal application on the deployment system under the workload you care about. Use
a distinct log path so the comparison cannot overwrite it:

```bash
cargo run --release --bin my-project -- --log logs/pgs-baseline.copper
```

The exact application command and `--log` argument are project-specific. What matters is
that the resulting unified log contains the effective configuration, the mission, process
timestamps, and the message presence needed by the contract.

If one log contains several recorded runs, inspect it first:

```bash
cargo run --release --features logreader --bin my-project-logreader -- \
    logs/pgs-baseline.copper list-runs
```

Pass the global `--run <index>` option when optimizing a particular run. PGS deliberately
uses the configuration and mission recorded in that run; there are no separate config or
mission overrides that could silently describe a different application.

## 3. Generate candidates

Run `optimize-schedule` through the application's typed logreader:

```bash
cargo run --release --features logreader --bin my-project-logreader -- \
    logs/pgs-baseline.copper optimize-schedule \
    --contract schedule.ron \
    --output target/pgs \
    --candidates 3
```

The search is deterministic: the same log, contract, and application version produce the
same candidates. Requesting more candidates gives you more distinct schedules to measure;
it does not make the first candidate more thoroughly optimized.

The command prints a readable ranking and writes the complete evidence under `target/pgs/`:

| Artifact | What you can learn or do with it |
|---|---|
| `contract.ron` | Confirm the normalized requirements used by this run |
| `profile.ron` | Inspect per-operation fired/skipped costs, percentiles, firing patterns, measured chains, source delivery, mission, and graph signature |
| `plan-N.plan.ron` | Inspect or archive the standalone validated `CuPlan` |
| `plan-N.config.ron` | Build the application with the original recorded config plus that exact explicit plan |
| `predictions.ron` | Compare predicted chain latency, source delivery, worker load, response time, CPU, and score for every candidate |
| `report.txt` | Read the same ranked summary printed in the terminal |

### Reading the score

Scores are compared from left to right. A later tier cannot compensate for a worse earlier
tier. The predicted score contains:

1. Source delivery deficit.
2. Number of chains predicted to miss their deadlines.
3. Number of chains predicted to consume the configured headroom.
4. Sum of chain latency divided by deadline.
5. Maximum predicted worker load.

This means PGS does not optimize only deadlines. It first protects contracted source
delivery, then deadline feasibility and margin, then total normalized latency, and finally
load balance. A source affects the first tier only when it appears in `sources`.

Worker `response` is the model's bounded response time for one cycle. `unbounded` means the
response-time calculation did not converge within its safety cap; do not treat that worker
as viable merely because another reported number looks small.

## 4. Build and run candidates

Build each candidate from its emitted `plan-N.config.ron`. The safest setup is a dedicated
candidate binary copied from the application's normal entry point, with only the compile-time
config path and output log path changed:

```rust,ignore
#[copper_runtime(config = "target/pgs/plan-1.config.ron")]
struct PgsCandidate {}
```

Keep the same resources, mission, component parameters, workload, release profile, and
launch options as the baseline. Enable `parallel-rt`, because a generated explicit schedule
may contain several workers:

```bash
cargo run --release --features parallel-rt --bin my-project-pgs-candidate -- \
    --log logs/pgs-plan-1.copper
```

Run on the same target under comparable system load. Warm-up, thermal throttling, IRQ
placement, logging pressure, and competing processes can all move the result. If those
conditions are part of normal robot operation, keep them in the measurement rather than
creating an unrealistically quiet benchmark.

## 5. Rank measurements and select

Feed candidate logs back into the same command. The positional log remains the baseline:

```bash
cargo run --release --features logreader --bin my-project-logreader -- \
    logs/pgs-baseline.copper optimize-schedule \
    --contract schedule.ron \
    --output target/pgs \
    --measure plan-1=logs/pgs-plan-1.copper \
    --measure plan-2=logs/pgs-plan-2.copper
```

This regenerates the predictions and adds:

| Artifact | Meaning |
|---|---|
| `measurements.ron` | Every measured candidate, best first, with p50/p99/max latency, misses, delivered source rate, and the corresponding prediction |
| `report.txt` | Predicted ranking followed by the measured ranking |
| `selected.plan.ron` | The standalone plan belonging to the best measured row, including the original plan when `baseline` wins |

Measured ranking uses delivered source rate and measured p99 chain latency. Its score omits
the predicted worker-load tier because the log comparison ranks observed end-to-end results.
Deadline misses are still reported for every chain, even though p99 is the ranking statistic.

Use the winning `plan-N.config.ron` when a candidate wins; keep the original configuration
when `baseline` wins. `selected.plan.ron` is the compact plan artifact for inspection,
versioning, or tooling. Before deployment, repeat the winning candidate across the robot's
expected operating range. Multiple measurement arguments may use names such as
`plan-1/r2=logs/pgs-plan-1-r2.copper`; each run remains a separate row so variability stays
visible.

## Diagnosing rejected inputs

PGS fails instead of filling missing evidence with guessed costs. Common input failures are:

| Error or symptom | Cause and action |
|---|---|
| No recorded configuration or runtime lifecycle record | Record a fresh log with the current application runtime and use the matching logreader build |
| No CopperList with process timestamps | Verify that the selected run contains executed CopperLists, not only lifecycle or text-log records |
| No process timestamps for an operation | The operation did not execute in the captured workload, or the log does not contain its timing metadata; exercise that path and record again |
| A chain has no samples | Its source and sink never both fired in a CopperList; preserve endpoint payload presence and exercise the complete path |
| A contracted source fired fewer than twice | Record a longer representative window or correct the source id/period |

Contract and comparison failures usually indicate a mismatch:

| Error or symptom | Cause and action |
|---|---|
| More than one mission in the selected run | Record or select one mission at a time |
| Unknown task or unreachable sink | Correct the task ids or define a chain that follows the selected mission's graph |
| Profiles were recorded on different graphs or missions | Rebuild and record baseline and candidates from the same topology, component config, resource bindings, and mission |
| No valid plan on the requested CPUs | Revisit the CPU set, deadlines, headroom, and in-flight capacity; do not weaken requirements merely to produce a file |
| Candidate fails to apply its scheduling policy | Use `Fair` while validating the workflow, or configure the required affinity and Linux real-time privileges described in [Thread Pools](./thread-pools.md) |

## Supporting example: Mandelbrot

`examples/cu_parallel_mandelbrot` in the copper-rs repository is a controlled PGS fixture.
It is deterministic and compute-bound, which makes the full workflow and model errors easy
to reproduce. It is not a representative robotics workload.

From that example directory, the one-line Just aliases run the same method:

```bash
just pgs-baseline
just pgs-optimize
just pgs-candidate
just pgs-measure
```

In one recorded development run, the baseline measured 41.66 ms p99. PGS predicted 43.71 ms
for `plan-1`, but the candidate measured 119.49 ms p99 on the same 250 ms chain. The measured
ranking correctly kept the baseline. Those numbers are machine-specific; the useful result
is the method catching a prediction error before deployment.
