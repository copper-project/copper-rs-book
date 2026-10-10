# Shared reference time

Copper's experimental `clock-sync` feature makes `ctx.now()` use a shared
reference epoch. PTP references expose nanoseconds on the TAI timeline. Enable
`clock-sync` on `cu29`, enable `linux-phc` on `cu-ptp`, then select an owned resource:

```ron
resources: [(
    id: "ptp",
    provider: "cu_ptp::LinuxPtpBundle",
    config: {
        "device": "/dev/ptp0",
        "management": "/var/run/ptp4lro",
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
restarting acquires the reference again. Pipeline scheduling is rejected in v0
until a correction barrier can coordinate in-flight CopperLists.

Optional runtime fields are `acquisition_timeout_ns` (10000000000),
`sample_interval_ns` (1000000000), `max_age_ns` (5000000000),
`drift_bound_ppb` (100000) and `max_slew_ppb` (500000). The error budget can expire
before the maximum age. Raw time drives cadence and deadlines independently of
corrections.

For a local experiment without a PHC, `LinuxSystemPtpBundle` reads the system UTC
clock associated with software-timestamped ptp4l. It requires the known TAI−UTC
offset. A board bundle can export `BoardPtp<HZ>` with BSP hooks for its existing
PTP service and a known counter frequency. Initialize and extend the board timer
in the BSP; keep Cortex-M counter reads in the foreground.

Unified logs record each published correction in the RuntimeLifecycle stream.
Enable `clock-sync` in recorded replay applications and matching logreaders.
Replay restores curves and quality without starting reference I/O. Unconfigured
clocks keep their local epoch and existing APIs.

Follow the [runnable Linux example](https://github.com/copper-project/copper-rs/tree/master/examples/cu_clock_sync)
for mock, software-grandmaster and hardware-grandmaster setup. The component's
[reference guide](https://github.com/copper-project/copper-rs/tree/master/components/res/cu_ptp)
describes Linux resource parameters and the board contract.
