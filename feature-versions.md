# Feature/version mapping

This is the contributor audit behind the book's minimum-version markers. Match a
feature's name and API to the
[Copper wiki release notes](https://github.com/copper-project/copper-rs/wiki/Copper-Release-Notes),
then check the release tag in the sibling `../copper-rs` checkout. The notes
currently cover releases through 1.2; the 1.3 entries below were verified in the
development checkout and are absent from 1.2. A chapter's old version prose is
not evidence of when a feature first appeared.

The book deliberately separates a capability's introduction from newer APIs for
that capability. Examples follow the edition named in the introduction. A marker
under a heading covers the section, while an inline marker covers that paragraph
or list item; nested sections can have a different minimum. Unreleased status is
centralized in the introduction so markers survive a release unchanged.

## Released features

| Minimum | Feature / searchable API | Book location | Evidence |
| --- | --- | --- | --- |
| 1.0 | `cargo-cunew` project/workspace scaffolding | [Setup](book/src/setup.md), [Workspace](book/src/workspace.md) | Release notes: 1.0 rc1, bootstrap/template paths; `support/cargo_cunew` exists in 1.0 and is absent in 0.15. |
| 1.0 | Explicit `kind: source`, `task`, `sink` | [Task graph](book/src/task-graph.md) | Release notes: 1.0 rc1, task roles in config; check `TaskKind` in `core/cu29_runtime/src/config.rs`. The underlying task traits predate 1.0. |
| 1.0 | Background sources | [Task graph](book/src/task-graph.md) | Release notes: 1.0 rc1, background execution includes sources. Regular background tasks predate 1.0. |
| 1.0 | Named thread pools, affinity, scheduling policies, `rt-scheduling` | [Thread pools](book/src/thread-pools.md), [Performance](book/src/performance-basics.md) | Release notes: 1.0, named pools; `ThreadPoolConfig` and `BackgroundConfig::Pool` in `core/cu29_runtime/src/config.rs`. |
| 1.0 | `CuLatchedStateUpdate`, `CuLatchedState` | [Messages](book/src/messages.md), [Task anatomy](book/src/task-anatomy.md) | Not enumerated in the notes: `core/cu29_runtime/src/payload.rs` in 1.0 contains the types; 0.15 does not. |
| 1.0 | Typed `logging.codec` / `logging.codecs`, PNG / FFV1 codecs | [Logging](book/src/logging-replay.md) | Release notes: 1.0 rc1, typed log codecs. The current frame-writing contract is a separate 1.3 entry below. |
| 1.0 | `ReplayCli` / `ReplayArgs`, structured-log debug queries | [Logging](book/src/logging-replay.md) | Release notes: 1.0 rc1, shared replay CLI, and 1.0, structured-log access; `core/cu29_runtime/src/replay.rs`, `core/cu29_runtime/src/debug.rs`. Remote debugging itself predates 1.0. |
| 1.1 | Feature-selected includes (`Feature`, `Not`, `All`, `Any`) | [Modular config](book/src/modular-config.md) | Release notes: 1.1, static configuration; `ConfigPredicate` in `core/cu29_runtime/src/config.rs`. Ordinary includes predate 1.0. |
| 1.1 | `cu29_build::setup()` | [Startup](book/src/main-rs.md), [Modular config](book/src/modular-config.md) | Release notes: 1.1, centralized build setup; `core/cu29_build/src/lib.rs`. Align its dependency source/release with the application's `cu29`. |
| 1.1 | Generated numeric/expression constants, `TypedTransform3D` const composition | [Task graph](book/src/task-graph.md) | Release notes: 1.1, static configuration and geometry; `core/cu29_runtime/src/config.rs`, `components/libs/cu_transform`. |
| 1.1 | Generated schedule visualization and observed schedule timing | [Just](book/src/justfile.md) | Release notes: 1.1, `plan` / `plan-log`; `core/cu29_schedule_view/src/main.rs` (formerly `plan.rs` in the 1.1 runtime) and `core/cu29_export/src/logstats.rs`. Current viewer recipe names are a separate 1.3 entry. Basic `log-stats` is older. |
| 1.1 | Debug-session lease, deferred handle attachments, richer schemas, Linux SHM preflight | [Logging](book/src/logging-replay.md) | Release notes: 1.1, remote debugging; `core/cu29_runtime/src/remote_debug.rs`, `core/cu29_value/src/lib.rs`. |
| 1.1 | Public CUDA pools and `CuHandle::storage_id()` | [Advanced tasks](book/src/advanced-tasks.md) | Release notes: 1.1, CUDA pools for applications; `core/cu29/src/lib.rs`, `core/cu29_runtime/src/pool.rs`. CUDA and pool internals already existed earlier. |
| 1.2 | Typed application handles, `run_until_shutdown()`, typed `start()` / `stop()` | [Startup](book/src/main-rs.md) | Release notes: 1.2, lifecycle checks; `core/cu29_runtime/src/app.rs`, generated application methods in `core/cu29_derive/src/lib.rs`. |
| 1.2 | Composing resource bundles; nonblocking serial and HC-12 composition | [Advanced tasks](book/src/advanced-tasks.md), [Transport reference](book/src/logstream-reference.md) | Release notes: 1.2, serial devices/resources; `ResourceBundleConfig::resources` and `components/res/cu_hc12`. Basic resource injection predates 1.0. |
| 1.2 | LogStream, native receiver archives, live twins, reconstruction, feedback, serial framing | [Telemetry](book/src/logstream-telemetry.md), [Transport reference](book/src/logstream-reference.md), [Monitor](book/src/monitoring.md), [Logging](book/src/logging-replay.md) | Release notes: 1.2, live logging and serial adapters; `core/cu29_logstream`, `components/res/cu29_logstream_serial`. |
| 1.2 | Compile-time `enable_keyframe_logging: false` | [Logging](book/src/logging-replay.md), [Troubleshooting](book/src/troubleshooting-performance.md) | Not enumerated in the notes: field in `core/cu29_runtime/src/config.rs` at 1.2, absent in 1.1. Keyframes themselves predate 1.0. |
| 1.2 | Payload-owned `SerializedPayloadSchema` discovery | [Exports](book/src/export-formats.md) | Not enumerated in the notes: `core/cu29_traits/src/lib.rs` and `core/cu29_export/src/serde_to_jsonschema.rs` at 1.2, absent in 1.1. MCAP and reflected schemas predate 1.0. |
| 1.2 | `UnifiedLoggerBuilder::append(true)` | [Logging](book/src/logging-replay.md) | Release notes: 1.2, append to closed recordings; builder in `core/cu29_unifiedlog/src/memmap.rs`. Earlier section-level `append()` methods are unrelated. The full book exercise also uses 1.3 run selection/rollover. |
| 1.1.4 on 1.1; 1.2.2 on 1.2 and newer | Empty-input skip/one-shot results and `background_process_empty` | [Task graph](book/src/task-graph.md), [Thread pools](book/src/thread-pools.md), [Troubleshooting](book/src/troubleshooting-performance.md) | Release notes: paired 1.2.2 / 1.1.4 entry. Check `background_process_empty` in each tag's `core/cu29_runtime/src/config.rs`; it is absent in 1.1.0 and 1.2.0. Paired markers avoid falsely claiming support in 1.2.0/1.2.1. |

## Development features targeting 1.3

All of these use `v1.3+`, with Catppuccin Mocha Lavender styling. Check the named symbol in the current
source and confirm it is absent from the released 1.2 implementation. The
implementation history also establishes that these were added after the 1.2
release; there are no 1.3 wiki release notes yet.

| Feature / searchable API | Book location | Source to check |
| --- | --- | --- |
| `CuStatelessTask`, `kind: stateless_task`, no `Freezable` requirement | [Advanced tasks](book/src/advanced-tasks.md), [Task graph](book/src/task-graph.md), [Lifecycle](book/src/task-lifecycle.md) | `core/cu29_runtime/src/cutask.rs`, `core/cu29_runtime/src/config.rs`, `core/cu29_derive/src`. |
| Explicit `Serial` / `Pipeline` planning and `max_in_flight` | [Performance](book/src/performance-basics.md), [Troubleshooting](book/src/troubleshooting-performance.md), [Thread pools](book/src/thread-pools.md) | `PlannerKind` in `core/cu29_runtime/src/config.rs`; `core/cu29_runtime/src/planner/pipeline.rs`. The old `parallel-rt` feature predates 1.0; these markers describe the current planner API. |
| Portable explicit plans and `optimize-schedule` / PGS | [PGS](book/src/profile-guided-scheduling.md) | `core/cu29_runtime/src/config.rs`, `core/cu29_export/src/pgs.rs`, `core/cu29_runtime/src/planner`. |
| Viewer `graph` / `sched` / `graph-log` / `sched-log`, positional template recipe arguments | [Just](book/src/justfile.md) | `support/cargo_cunew/templates/cu_project/justfile`, `support/cargo_cunew/templates/cu_full/justfile`, `core/cu29_graph_view`, `core/cu29_schedule_view`. Schedule visualization first shipped in 1.1 as `plan` / `plan-log`. |
| Per-channel Zenoh `queue_mode` / `rx_capacity` | [Bridges](book/src/bridges.md) | `components/bridges/cu_zenoh_bridge/src/lib.rs`. Bridges and the Zenoh transport predate 1.0. |
| `.rollover(size)` with retained static metadata | [Logging](book/src/logging-replay.md) | `core/cu29_unifiedlog/src/memmap.rs`. Append first shipped in 1.2. |
| `list-runs` / global `--run`, retained run identity | [Exports](book/src/export-formats.md), [Logging](book/src/logging-replay.md) | `core/cu29_export/src/lib.rs`, `core/cu29_unifiedlog/src/memmap.rs`. |
| In-place four-byte logging codec frames, writer `position` / `overwrite` contract | [Logging](book/src/logging-replay.md) | `core/cu29_runtime/src/logcodec.rs`, `core/cu29_traits/src/lib.rs`. Typed codecs first shipped in 1.0. |
| `self-describing-logs`, startup catalogs, `ValueDecode`, standalone catalog/deep validation tools | [Self-describing logs](book/src/self-describing-logs.md), [Exports](book/src/export-formats.md) | `core/cu29_runtime/src/catalog.rs`, `core/cu29_export/src`, `examples/cu_self_describing_logs`. |
| Python `value_decode_catalog_unified`, `copperlist_value_iterator_unified` | [Python](book/src/python.md) | `core/cu29_export/src/catalog_python.rs`. Typed offline analysis and runtime Python tasks predate 1.0. |
| Twin builder receiver/storage limits and buffer capacities | [Telemetry](book/src/logstream-telemetry.md) | `with_receiver_limits`, `with_section_size`, `with_replay_capacity`, `with_frame_capacity`, `with_log_capacity` in `core/cu29_logstream/src/twin_session.rs`. Live twins first shipped in 1.2. |
| Twin catalogs and `.with_log_rollover()` | [Telemetry](book/src/logstream-telemetry.md) | `core/cu29_derive/src/live_twin.rs`, `core/cu29_logstream/src/twin_session.rs`, `core/cu29_logstream/src/archive.rs`. |
| `clock-sync`, raw `CuInstant`, source/epoch metadata, PTP providers, monitor CLK panel | [Shared reference time](book/src/clock-sync.md) | `core/cu29_clock`, `components/res/cu_ptp`, `examples/cu_clock_sync`, `components/monitors/cu_consolemon`. Ordinary `RobotClock` timestamps predate 1.0. |

## Features intentionally left unmarked

Task sources/processors/sinks, ordinary lifecycle hooks, graph connections,
`CuMsg`/payload derives, `CuContext`, local robot time, units, `Reflect`,
`Freezable`/keyframes, ordinary logging and export, basic `log-stats`, MCAP,
remote debugging, simulation, missions, workspaces, basic resource injection,
parameterized/recursive includes, per-instance overrides, regular background
tasks, `async-cl-io`, the original `parallel-rt`, `mmap-fsync`, buffer pools,
Python task prototyping, and typed offline Python analysis all exist before 1.0.
Keep them unmarked even if a tutorial uses newer startup code or helper recipes.

In particular, `cu29::bincode` was already exported in 0.15. This edition uses
Copper's current codec through that path, but the import path itself is not a new
1.3 feature. Do not stamp every payload example with 1.3.
