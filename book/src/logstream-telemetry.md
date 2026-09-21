# Streaming Logs and Live Telemetry

LogStream sends your robot's execution log to a ground station while the robot
runs. The ground station records a native `.copper` archive, displays typed task
outputs and structured logs, and can run selected tasks locally to reconstruct
outputs you chose not to transmit.

This chapter takes you from the runnable UDP demo to your own sender and ground
application. Use matching application code, task graph, Copper revision, and
encoding features on both machines. Keep the producing build's `cu29_log_index`
with its recordings so you can render structured logs later.

```text
Robot tasks ──→ onboard .copper log
     │
     └──→ LogStream worker ──→ UDP or framed serial ──→ received .copper archive
                                                           │
                                                      live twin
                                                           │
                                                  your UI or analysis
```

Forward error correction (FEC) adds repair packets that can recover lost data
within configured bounds. Longer outages leave explicit gaps. A **keyframe**
saves task state; a **recovery point** binds that keyframe to the stream manifest
and a CopperList boundary so the receiver can resume safely. Starting late does
not retrieve expired history.

## 1. Try the UDP demo

Use a Copper source checkout containing the implementation described here,
including [replay-input validation in PR #1379](https://github.com/copper-project/copper-rs/pull/1379).
The [demo](https://github.com/copper-project/copper-rs/tree/master/examples/cu_logstream_demo)
requires the checkout's Rust toolchain, Just, and Python 3. From that checkout:

```sh
cd examples/cu_logstream_demo
just
```

This starts separate sender and receiver processes, compares the received archive
against the onboard recording, checks its integrity, and runs offline replay.
Each automated run prints a fresh output directory under the example's `logs/`.

For the interactive view, run these in separate terminals, both in the example
directory. Start telemetry first:

```sh
# Terminal 1: ground station
just telemetry
```

```sh
# Terminal 2: robot, with Copper's console monitor
just sender
```

The graph is `encoders → kinematics`. Joint angles cross the link; the ground
station runs the same kinematics task to calculate the arm pose. The robot arm
is labeled **reconstructed locally; payload not transmitted**. The robot log pane
shows simulated encoder temperature and supply-voltage diagnostics sent as
structured logs.

| Control | Action |
| --- | --- |
| `1`, `2`, `Tab` | Select Live, Health, or cycle between them. |
| `Space` | Pause both display readers; recording continues. |
| Arrow keys or `hjkl` | Scroll Health details. |
| `q`, Escape, Ctrl-C | Close telemetry and finalize its archive. |

The sender runs for about a minute. Telemetry stays open after it finishes.
Pause the view and resume to see display misses without interrupting recording.

The manual demo commands replace recordings at their chosen base paths. Supply
new paths to retain previous runs:

```sh
just telemetry 0.0.0.0:7447 logs/ground-session-2.copper
# On the robot; replace this example address with the ground station's address:
just sender 192.168.1.20:7447 logs/robot-session-2.copper
```

Use `just receiver 0.0.0.0:7447 logs/received-session-2.copper` for headless
recording. This demo receiver exits after one second without a datagram, or fails
if no traffic arrives within 15 seconds; start the sender promptly. These timeout
and overwrite behaviors belong to the demo, not the generated twin API.

## 2. Configure your robot's sender

Enable the `logstream` feature on your existing `cu29` dependency and add
`cu29-logstream-udp` from the same Copper revision. Ground code that directly uses
LogStream types also needs `cu29-logstream` with its `std` feature. Follow the
[demo Cargo manifest](https://github.com/copper-project/copper-rs/blob/master/examples/cu_logstream_demo/Cargo.toml)
for a workspace example; keep your application's existing dependency source.

Add the following top-level blocks to your `copperconfig.ron`, alongside your
existing `tasks` and `cnx`. These are the demo's working UDP settings; change
`remote_addr` for your ground station:

```ron
    logging: (
        enable_task_logging: true,
        enable_keyframe_logging: true,
        keyframe_interval: 16,
        slab_size_mib: 16,
        section_size_mib: 1,
        copperlist_count: 8,
    ),
    resources: [
        (
            id: "network",
            provider: "cu29_logstream_udp::CuUdpLogStreamResources",
            config: {
                "bind_addr": "127.0.0.1:0",
                "remote_addr": "127.0.0.1:7447",
                "send_buffer_bytes": 262144,
                "ttl": 1,
            },
        ),
    ],
    log_streaming: (
        destinations: [
            (
                id: "ground",
                transport: (
                    type: "cu29_logstream_udp::CuUdpLogStreamTx",
                    resource: "network.tx",
                ),
                link: (
                    mtu_bytes: 1200,
                    bitrate_bps: 2000000,
                    memory_budget_kib: 576,
                    max_latency_ms: 250,
                    burst_packets: 8,
                ),
                fec: (
                    continuous: (
                        field: Gf256,
                        window_symbols: 64,
                        repair_every_source_symbols: 4,
                        repair_density: Full,
                    ),
                    objects: (
                        max_object_bytes: 65536,
                        repair_symbols_per_block: 2,
                    ),
                ),
                recovery_interval: 16,
                max_record_bytes: 4096,
            ),
        ],
    ),
```

Keep your usual application builder, local log path, clock, and execution loop.
The generated runtime wires the configured transport and sender workers. The
demo's mock clock, impairment wrapper, and fixed iteration loop are test harness
code and are not needed in your application.

`network.tx` is a resource binding, not a task-graph edge. The
[graph renderer](./justfile.md#just-dag--render-the-task-graph) shows it in
the resource table as `system: logstream (ground)`.

| Setting | How to choose it |
| --- | --- |
| `mtu_bytes` | Maximum Copper packet size accepted by your carrier; 1200 is the demo profile. |
| `bitrate_bps` | Budget for all Copper packet bytes, including repairs, recovery, and structured logs. Leave room for UDP/IP or serial overhead. |
| `memory_budget_kib` | Sender buffer budget. The demo needs 576 KiB; larger records need more storage. This is not a total process-memory limit. |
| `max_latency_ms` | Expiry deadline for ordinary queued data, measured from encoded-record admission. |
| `burst_packets` | Allowed transmission burst; reduce it for a slow carrier. |
| `window_symbols` | Continuous FEC recovery window; the generated sender supports at most 64 symbols, and receiver limits also apply. |
| `repair_every_source_symbols` | One continuous repair after this many source symbols. Lower means more repair traffic. |
| `max_object_bytes` | Finite-object bound, including recovery data; it must fit the sender's supported RaptorQ geometry. |
| `max_record_bytes` | Maximum complete CopperList record, including its record header. |
| `recovery_interval` | Recovery boundaries in CopperLists, not milliseconds. Must be a nonzero multiple of `logging.keyframe_interval`. |

For example, keyframes every 20 lists and recovery points every 100 lists select
recovery boundaries at IDs 0, 100, 200, and so on. Streaming needs a nonzero
keyframe interval even if you disable local keyframe recording. Keeping local
keyframes, as above, also makes the onboard recording useful for stateful replay.

Start with the demo profile and captured task outputs. Measure actual transmission
and drop counters before reducing bandwidth or adding reconstruction.

## 3. Start a ground-side twin

Build a simulation application from the same graph and task types. The generated
`twin` builder owns receiving, archive writing, recovery, and replay; you supply
a packet receiver and consume the resulting frames. This integration sketch uses
`Ground` as your generated application type:

```rust,ignore
use cu29::prelude::*;
use cu29_logstream_udp::CuUdpLogStreamConfig;
use std::time::Duration;

#[copper_runtime(config = "copperconfig.ron", sim_mode = true)]
struct Ground {}

// Inside your fallible ground application entrypoint:
let (_, rx) = CuUdpLogStreamConfig::new("0.0.0.0:7447".parse()?).open()?;
let (mut twin, mut frames) = Ground::twin(rx)
    .with_log_path("logs/received-session-1.copper")
    .spawn()?;

// Repeat this on your UI or analysis thread while the application is running:
frames.wait_timeout(Duration::from_millis(50));
let status = frames.status();
while let Some(update) = frames.try_read() {
    render(&update.frame.copperlist); // Your presentation function.
    account_for_display_misses(update.missed);
}

// At application shutdown:
let final_status = twin.stop()?;
```

Use the generated output accessors for your graph. In the demo these include
`get_encoders_output()` and `get_kinematics_output()`. Their payloads remain typed
Rust values; your UI does not need to decode the stream again.

Choose a **fresh archive path for each sender session**. The builder rejects an
existing base file or first slab. Keep the twin handle alive while receiving;
`stop()` finalizes recording and reports worker errors and final counters.
Dropping the handle also stops and joins its workers.

For recording alone, insert `.archive_only()` before `.spawn()`. This disables
task reconstruction and frame production while preserving archival and status.

The default twin accepts the demo's 1200-byte packet, 64-symbol window, 4 KiB
record, and 64 KiB recovery-object profile. Increasing sender limits does not
increase receiver limits automatically. For a larger profile, use the
[custom receiver API](./logstream-reference.md#custom-receivers) with explicit bounds.

### Keep display loss separate from recording loss

The frame reader retains 64 display frames by default, overwriting the oldest
unread frame when full. Set `.with_frame_capacity(128.try_into()?)` on the builder
to change display retention. `update.missed` counts overwritten display frames;
`frames.status()` reads an independent status slot without consuming frames.

A slow, paused, or dropped reader never makes recording wait. A borrowed frame
remains valid while publication continues, but payload allocations and your own
chart history consume additional memory. The receiver and UI still share a
process failure boundary.

For async presentation, use `frames.ready().await` instead of polling. Consume
unread frames and status changes before waiting again. Custom integrations can
use `telemetry_channel` and a scheduling waker; see the
[receiver reference](./logstream-reference.md#custom-receivers).

## 4. Reduce traffic with task reconstruction

A live twin can execute ordinary synchronous tasks using captured inputs,
recorded clock values, and restored task state. Mark a suitable task in the
shared graph:

```ron
(
    id: "kinematics",
    type: "cu_logstream_demo::tasks::Kinematics",
    streaming: (replay: reconstruct),
),
```

The robot still runs the task and records its full output locally. Its streamed
capture omits the selected output payload, including in repairs and repeated
recovery boundaries. The twin reconstructs that output before downstream tasks
consume it, restoring sender metadata. Reconstructed values appear in live
frames and offline replay output; the received archive keeps the captured bytes.

Omitting `streaming` keeps the default `replay: capture`. Sources and bridge
receives stay captured. Reconstruction requires a logged, ordinary synchronous
task; background and anytime tasks are unsupported. A graph using reconstruction
must use the lossless native compressed codec and full handle capture: custom
codecs, flat CopperList encoding, and selective handle policies are rejected.

Choose tasks whose outputs depend on recorded inputs, Copper's clock, and state
covered by `Freezable`. Avoid external side effects and unrecorded inputs such as
host wall time or hardware reads. Matching code is necessary, but does not by
itself make a nondeterministic algorithm reproducible.

### Place the capture boundary where the required inputs exist

Every incoming connection of every reconstructed task must come from a node
with logging enabled. A producer can itself reconstruct, so chains of
reconstructed tasks are valid. Copper checks all incoming branches and each
mission graph at compile time, including when transports are injected in code.

For a camera pipeline, the following task settings let you omit images while
sending detections and reconstructing tracking and planning. This is a fragment
to apply to your own task types and connections:

```ron
tasks: [
    (id: "camera", type: "tasks::Camera", logging: (enabled: false)),
    (id: "detect", type: "tasks::Detect", streaming: (replay: capture)),
    (id: "track", type: "tasks::Track", streaming: (replay: reconstruct)),
    (id: "plan", type: "tasks::Plan", streaming: (replay: reconstruct)),
],
```

With `camera → detect → track → plan`, `detect` supplies captured detections;
`track` and `plan` have the inputs they need. Keep logging enabled on all three.
Changing `detect` to `reconstruct` while camera logging is disabled fails at
compile time: the diagnostic names `detect`, `camera`, and the image message
type. Either enable camera logging or keep detector output captured. Similarly,
an additional unlogged camera input directly into `track` makes that task invalid.

### Check reconstruction during development

Enable `cu29/logstream-verify` on both ends to compare reconstructed outputs
against sender digests. In the demo, use separate terminals:

```sh
just telemetry-verify
# Other terminal:
just sender-verify
```

Matching frames are labeled **Verified**. Normal operation labels them
**Reconstructed** and does not send the optional verification digest. A mismatch
suppresses reconstructed frames until the next matching recovery point; native
recording continues. Verification is opt-in even in a Rust debug build, and its
live digests do not change the native archive format.

## 5. Read structured robot logs

Configured streaming destinations automatically forward structured entries
alongside local logging. Message templates and parameter names travel as interned
IDs; values retain their types. String values are transmitted if your application
explicitly logs strings. Ground rendering needs the producing application's
`cu29_log_index`, not an unrelated ground build's string table.

The twin exposes an independent log reader once:

```rust,ignore
let mut logs = twin.take_log_reader().expect("fresh twin log reader");
// In your presentation loop, with the producing build's string table loaded:
while let Some(update) = logs.try_read() {
    let line = rebuild_logline(&strings, &update.frame.entry)?;
    show_robot_log(line, update.missed);
}
```

This ring retains 64 entries and publishes only after archival succeeds.
`CuTwinStatus::structured_logs` counts archived entries. Pausing or dropping this
reader does not stop task frames or recording.

The demo looks for `cu29_log_index` beside its executable. To select the producing
build's index explicitly, run the already-built binary from the example directory:

```sh
../../target/debug/cu-logstream-demo telemetry \
    --listen 0.0.0.0:7447 --log-base logs/telemetry-session-3.copper \
    --log-index /path/to/producing-build/cu29_log_index
```

Structured transmission uses bounded buffers and the same destination bitrate
budget. Oversized entries or exhausted buffers increment `inbox_drops`; local
records remain intact. Link loss can also leave missing remote log entries.
Keep the onboard recording when you need the complete local history.

## 6. Add feedback and inspect link health

One-way streaming works without a return path. To send receiver health reports
back and optionally adapt continuous FEC, configure both endpoints explicitly.
In the demo, run `just telemetry-two-way` and `just sender-two-way` in separate
terminals. Telemetry listens on port 7447 and reports to the robot on port 7448.
Use `just telemetry-two-way lossy` to exercise sustained source loss.

In your own sender's destination, add the following block. Also give `network`
a fixed `bind_addr`, such as `0.0.0.0:7448`, so the ground can address it:

```ron
feedback: (
    transport: (
        type: "cu29_logstream_udp::CuUdpLogStreamRx",
        resource: "network.rx",
    ),
    report_interval_ms: 100,
    timeout_ms: 1000,
    adaptation: (
        min_repair_every_source_symbols: 1,
        max_repair_every_source_symbols: 16,
    ),
),
```

On the ground, create a TX endpoint targeting that robot address and pass it to
the twin builder. Replace the example robot address below:

```rust,ignore
let mut socket = CuUdpLogStreamConfig::new("0.0.0.0:7447".parse()?);
socket.remote_addr = Some("192.168.1.10:7448".parse()?);
let (tx, rx) = socket.open()?;
let (mut twin, mut frames) = Ground::twin(rx)
    .with_feedback(tx.expect("remote_addr creates a TX endpoint"))
    .with_log_path("logs/received-two-way-session-1.copper")
    .spawn()?;
```

The sender manifest advertises feedback support and cadence. Sharing a UDP socket
does not enable feedback automatically. Give each logical receive endpoint one
owner; cloned UDP receivers compete for packets rather than broadcasting them.

Omit `adaptation` for reports only. With adaptation enabled, the baseline
`repair_every_source_symbols` must lie within the configured bounds. Loss raises
protection; sustained healthier reports allow less redundancy. After timeout,
feedback becomes stale and the repair interval gradually returns to baseline.
Bitrate, burst, memory, latency, FEC window/field/density, and object FEC stay fixed.
Feedback failure never stops capture or autonomous recovery.

In the robot's console monitor, open **BW** to see one **Telemetry / TX** panel
per destination. Arrow keys or `hjkl` scroll large panels.

| Reading | Interpretation |
| --- | --- |
| TX bytes/packets, budget, drops, recovery activity | Local submission and sender health; a successful UDP send does not confirm delivery. |
| One-way / Disabled | No feedback was configured. |
| Two-way / Waiting | Feedback is configured but no valid report has arrived. |
| Active | Receiver measurements and effective repair interval are available. |
| Stale or failed; receiver values `n/a` | Receiver measurements are unavailable or out of date. Check the return path. |
| Source loss / FEC recovery | Finalized symbol outcomes; excludes the active coding window and unseen history or tails. |

Reports are advisory, not per-record acknowledgements. Custom monitors can read
worker snapshots through `runtime.log_streams()`; the presentation thread samples
them without adding monitoring callbacks to task execution.

## 7. Inspect recordings and exercise recovery

From the demo directory, point its tools at a received archive base:

```sh
just cl logs/received-session-1.copper
just fsck logs/received-session-1.copper
just resim logs/received-session-1.copper logs/replay-session-1.copper
just resim-debug logs/replay-session-1.copper logs/debug-session-1.copper
```

For your own app, use its matching logreader and replay binaries as described in
[Logging and Replaying Data](./logging-replay.md). Keep the whole slab family
(`name.copper`, `name_0.copper`, and subsequent slabs where present), and pass the
base path to the tools. Always use a different path for replay output.

Extract received structured logs with the producing build's index:

```sh
../../target/debug/cu-logstream-demo-logreader \
    logs/received-session-1.copper extract-text-log \
    ../../target/debug/cu29_log_index
```

The received archive retains sender payload bytes, timestamps, keyframes, and
stream continuity records. `fsck` reports missing ranges and verified recovery
boundaries. Replay cannot cross a gap without a matching keyframe; resuming later
does not fill the gap. A clean receiver shutdown does not establish that an
unobserved sender tail was complete.

Exercise the failure modes before deploying:

| Demo command | What it exercises |
| --- | --- |
| `just run loss` | Recover a dropped CopperList with FEC. |
| `just run lossy` | Sustained source-packet loss. |
| `just run outage` | Resume after an interruption that leaves missing history. |
| `just run late` | Join an already running sender. |
| `just run restart` | Start a fresh receiver during a run. |
| `just run idle` | Recover the initial boundary after captures have stopped. |
| `just check` | Run all scenarios, including clean reception. |
| `just run-two-way all` | Run the scenarios with feedback enabled. |

The sender repeats its manifest and latest complete recovery bundle on a 250 ms
local deadline, even without new captures. Repetition shares the bitrate budget,
so this is a scheduling deadline rather than a delivery guarantee. Pending
bundles finish before newer ones replace them. Pacing uses `RobotClock` and does
not require clock synchronization with the ground station.

## Troubleshooting

| Symptom | Check or change |
| --- | --- |
| No packets at the ground | Verify numeric bind/remote addresses, ports, routing, and firewall access. Loopback addresses only reach the same machine. |
| Packets arrive but no frames | Inspect recording/replay status: the twin may be waiting for a valid manifest/recovery point, recovering after a gap, or configured as archive-only. |
| Compile error about an unlogged replay input | Enable the named producer's logging or capture the named consumer's output. Check every fan-in branch. |
| Startup rejects the stream/profile | Use matching application/schema/encoding features; fit the receiver's record, object, symbol, and window bounds. |
| Archive already exists | Choose a fresh base path and keep each sender session separate. |
| Display misses rise while archive progress continues | Reduce UI work or increase display capacity. These misses do not mean packets were lost. |
| Sender drops or source gaps rise | Check encoded record sizes, latency expiry, link capacity, FEC overhead, and memory limits. More repair traffic also consumes the link budget. |
| Robot log text is wrong or cannot be rendered | Load the exact producing build's string index. |
| Feedback stays Waiting or becomes Stale | Check the robot's fixed bind port, ground TX destination, `.with_feedback(...)`, and single receive ownership. |
| Reconstruction stalls while recording continues | Inspect replay queue pressure, source gaps, and verification failures; reconstruction resumes at a matching recovery point. |

For serial transport, receiver internals, and current framing details, continue
to [LogStream Transport and Receiver Reference](./logstream-reference.md).
