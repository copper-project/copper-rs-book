# Shared reference time

<span class="version-marker" data-version="1.3">v1.3</span>
Two robots exchanging timestamped measurements need timestamps with the same
meaning. A shared reference clock gives `ctx.now()` a named epoch and lets the
runtime stop consuming measurements when its synchronization uncertainty exceeds
your chosen limit. Task code still uses ordinary Copper timestamps.

## See synchronization in the monitor

Use this experimental feature from the copper-rs checkout named in the
[edition notice](./introduction.md#reading-version-markers). The
Linux demo needs Rust, `just`, `ptp4l`, `phc2sys`, `pmc`, `ethtool`, and `ip`, plus
an active Ethernet interface exposing `/dev/ptp0` and read access to that device.
Use a test network: the demo advertises a local PTP master on that interface.
From the repository root, in an interactive terminal, run:

```sh
cd examples/cu_clock_sync
just
```

The recipe asks for sudo to start the PTP services it needs, then opens
ConsoleMon's **CLK** panel. It cleans up the services it started when you exit;
existing services are reused. If services are already configured with suitable
permissions, `just run` starts only the Copper application.

Look for **Clock / reference**, a shared epoch, **Offset from reference**, and
**Estimated uncertainty**. The demo's 20 ms uncertainty limit decides when the
clock becomes unusable; it is not an accuracy target. A local reference sourced
from the host's own clock demonstrates synchronization without establishing
absolute accuracy. Local calendar time appears only when the provider supplies
a valid TAI minus UTC offset.

For another PHC device or software timestamping, follow the example's
[Linux setup guide](https://github.com/copper-project/copper-rs/blob/master/examples/cu_clock_sync/docs/linux-setup.md).

## Configure your application's reference

The `clock-sync` feature makes `ctx.now()` use a shared
reference epoch. The provider chooses that epoch: Linux PTP adapters expose TAI,
while board and GNSS providers can supply bare GPS or application-defined
nanoseconds without conversion. Enable
`clock-sync` on `cu29`, enable `linux-phc` on `cu-ptp`, then select an owned resource:

```ron
resources: [(
    id: "ptp",
    provider: "cu_ptp::LinuxPtpBundle",
    config: {
        "device": "/dev/ptp0",
        "management": "/var/run/ptp4l",
        "reference_error_ns": 10000,
    },
)],
runtime: (clock: (parent: "ptp.reference", max_error_ns: 100000, sample_interval_ns: 100000000)),
```

The resource reads a PHC already disciplined by ptp4l. Match its device, port and
domain to the service. Choose a measured upstream uncertainty bound through
`reference_error_ns`; Copper adds capture, drift and remaining phase error.
Acquisition finishes before tasks start. Task code continues to stamp messages
with ordinary `ctx.now()` and `Tov::Time`.

The generated Serial runtime samples references outside task `process` hooks and
checks clock health before each iteration. Clock clones share the same monotonic
curve. `ctx.clock.sync_status()` reports domain/session, sample age, phase,
drift and estimated error. Reference loss enters bounded holdover. Exceeding the
error budget or age limit fails the iteration before consumers execute;
restarting acquires the reference again. This experimental API supports the Serial plan. Pipeline scheduling is rejected
because correction changes must be coordinated across in-flight CopperLists.

Optional runtime fields are `acquisition_timeout_ns` (10000000000),
`sample_interval_ns` (1000000000), `max_age_ns` (5000000000),
`drift_bound_ppb` (100000) and `max_slew_ppb` (500000). The error budget can expire
before the maximum age. Raw time drives cadence and deadlines independently of
corrections.

Each `RobotClock` owns its hardware-counter calibration, including when
`clock-sync` is disabled. `clock.raw_now()` returns a `CuInstant` on the
undisciplined local timeline, while `clock.now()` and `clock.recent()` return
execution timestamps as `CuTime`. Both use nanoseconds; intervals use
`CuDuration`. These distinct types prevent raw readings from being used as
message timestamps or execution timestamps from being used as raw deadlines. Clones share its origin and calibration; independently
constructed clocks have separate raw origins. Use `ctx.now()` for message
timestamps and raw time for reference capture and elapsed-time measurements.

`CuInstant` readings use an explicit clock handle. Use `clock.raw_now()` for counter reads, `clock.busy_wait_for(duration)`
for a raw elapsed-time wait, and `clock.busy_wait_until(raw_deadline)` for a
deadline from that clock or one of its clones. Raw reads and waits are available
with or without synchronization. Mock clocks require their control handle to
advance time while waiting. For typed readings from the control handle, use
`control.raw_now()`. Its existing `now()` accessor retains the legacy view of
the raw counter as `CuTime`; execution time comes from the associated clock.

For a captured raw reading, `CuInstant::from_nanos(nanos)` reconstructs an
instant using the capturing clock's origin. `ClockSnapshot::at(instant)` maps
it to execution `CuTime` through the recorded epoch and rate.

For a local experiment without a PHC, `LinuxSystemPtpBundle` reads the system UTC
clock associated with software-timestamped ptp4l. It requires the known TAI−UTC
offset. A board bundle can export `BoardPtp<HZ>` with BSP hooks for its existing
PTP service and a known counter frequency. Initialize and extend the board timer
in the BSP; keep Cortex-M counter reads in the foreground.

Unified logs record each published correction in the RuntimeLifecycle stream.
Enable `clock-sync` in recorded replay applications and matching logreaders.
Replay restores curves, quality, source and epoch without starting reference I/O. Unconfigured
clocks keep their local epoch and constructor APIs.

`ctx.clock.origin()` identifies both the advertised upstream source and the epoch
of `ctx.now()`. For example, a GNSS receiver distributed through PTP can report
`ClockSource::Gnss` with `ClockEpoch::Tai`; a provider supplying bare GPS time
reports `ClockSource::Gnss` with `ClockEpoch::Gps`. Source describes provenance,
while epoch identifies what timestamp zero means. Unknown provenance stays unknown.
The accessor performs no counter read, allocation, reference I/O or conversion.

Board providers return source and epoch through `BoardPtpHooks::origin`, matching
the nanoseconds returned by `read`. Reference observations carry this metadata with
the captured time. For initialization without live synchronization,
`RobotClock::from_ref_time_with_origin(ns, origin)` selects a named epoch; use
`from_ref_time_with_rtc_and_origin` when supplying RTC calibration functions.
An already synchronized clock keeps its epoch during resynchronization; selecting
a different epoch requires a new clock.

ConsoleMon's CLK panel shows numeric robot time, source and epoch. For TAI with
a valid provider-supplied `tai_minus_utc_seconds`, it also shows the local timezone
as an ISO 8601 date to whole seconds, including the timezone offset. The monitor
performs this conversion only while drawing CLK. If the TAI minus UTC offset is
unknown, local time is unavailable. GPS and application-defined values stay numeric;
calendar conversion belongs to application display/debug code.

Follow the [runnable Linux example](https://github.com/copper-project/copper-rs/tree/master/examples/cu_clock_sync)
for software-grandmaster and hardware-grandmaster setup. The component's
[reference guide](https://github.com/copper-project/copper-rs/tree/master/components/res/cu_ptp)
describes Linux resource parameters and the board contract.
