# Self-Describing Logs

Suppose you receive a robot's `.copper` recording and want to plot wheel speed.
With an application-specific logreader, you need the Rust payload types used by
that application. A self-describing log carries a **catalog** that tells an
offline reader how to decode those payloads, including field names and storage
units. You can inspect the recording with Copper's standalone tools and export
the samples without building the robot's logreader.

Use this feature when you share recordings with another team, keep logs for later
analysis, or collect recordings from several applications. It is experimental
in Copper 1.3.0-dev; use a checkout of that version for the examples below.

## 1. Try a complete recording

From the root of a copper-rs checkout, enter the wheel-sensor example:

```sh
cd examples/cu_self_describing_logs
just
```

This records ten cycles in `logs/wheel.copper`, displays the embedded catalog,
and checks the recording with `fsck --deep`. The graph is a wheel source, a
filter, and a sink. Each cycle captures the source and filter payloads; the sink
contributes its execution metadata.

Look at the catalog's `WheelSample` fields. Alongside encoder ticks it describes
distance, speed, a timestamp, acceleration, temperatures, and sensor state. The
reader obtains those names and types from the recording itself.

Export the captured cycles from the same directory:

```sh
just extract --export-format jsonl > samples.jsonl
just extract --export-format csv > samples.csv
```

Each JSONL line is one CopperList, with its `id` and ordered `msgs`. A message
contains its payload, timestamps, and capture information. Use JSONL to process
cycles one at a time, or CSV to load the recording into a spreadsheet.

## 2. Enable it in your application

The project templates expose an application feature. For an existing app, add
this forwarding entry to its `Cargo.toml`:

```toml
[features]
self-describing-logs = ["cu29/self-describing-logs"]
```

Keep the usual build script calling `cu29_build::setup()` and your ordinary
builder:

```rust,ignore
let app = App::builder()
    .with_log_path("logs/app.copper", Some(32 * 1024 * 1024))?
    .build()?;
```

Run your application's recording binary with the feature enabled:

```sh
cargo run --features self-describing-logs
```

Copper builds and saves the catalog during application construction, before
initializing resources. It describes the output types declared in your RON
graph, including types from dependency crates. One catalog covers every compiled
mission and records each mission's output-slot order.

Payload capture still follows your logging configuration. Keep
`enable_task_logging: true` and enable logging on the outputs you want to
inspect. A catalog describes a type; a task with `logging: (enabled: false)`
does not contribute its payload bytes to the recording.

## 3. Describe your payloads

Ordinary encoding derives supply the descriptions when the feature is enabled.
For example, a wheel payload can use Copper's units directly:

```rust,ignore
use cu29::bincode::{Decode, Encode};
use cu29::prelude::*;
use cu29::units::si::f32::{Length, Velocity};

#[derive(Clone, Debug, Default, Serialize, Deserialize, Encode, Decode, Reflect)]
#[bincode(crate = "cu29::bincode")]
pub struct WheelSample {
    pub ticks: u32,
    pub distance: Length,
    pub speed: Velocity,
    pub timestamp: CuTime,
}
```

The catalog follows nested fields and enum variants automatically. A reusable
payload crate can add `#[bincode(describe)]` to provide descriptions even when
the recording feature is disabled.

Units tell you how to interpret the **stored value**. A length created from
centimetres is stored in metres, velocity uses `m·s⁻¹`, and `CuTime` stores
nanoseconds. Use the catalog's storage unit when plotting or converting exported
numbers. The unit used to construct a Rust quantity does not change its storage
unit.

If you implement `Encode` by hand, also implement `ValueDecode` with a recipe
that matches the bytes your encoder writes. For an `Orientation` wrapper whose
encoder writes exactly an array of four `f32` values:

```rust,ignore
impl cu29::bincode::ValueDecode for Orientation {
    const DECODE: &'static cu29::bincode::ValueDecodeSpec =
        <[f32; 4] as cu29::bincode::ValueDecode>::DECODE;
}
```

Check that the recipe decodes the complete encoded value, including consecutive
values. A custom logging codec also needs a recipe for its recorded representation.
If startup rejects a task/type/codec combination, check that encoder's description.

## 4. Read your own recording

From the copper-rs repository root, pass the recording's base path to the
standalone reader. Replace `logs/app.copper` below with your recording's path:

```sh
just logextract logs/app.copper catalog
just logextract logs/app.copper extract-copperlists --export-format jsonl > samples.jsonl
just logextract logs/app.copper fsck --deep
```

Keep the complete slab family with the recording. `fsck --deep` checks the
catalog and decodes every captured payload; use it before analysing a log
copied from a robot. The catalog replaces the payload decoder, while structured
text reconstruction still uses the producing build's `cu29_log_index`.

If several runs share the log, list them and select the one you want:

```sh
just logextract logs/app.copper list-runs
just logextract logs/app.copper --run 1 extract-copperlists --export-format jsonl
```

`--run` is a zero-based index from `list-runs`. The reader selects that run's
mission map from the shared catalog. See [Exporting Data](./export-formats.md)
for catalog dumps and validation reports, and [Python Support](./python.md)
for offline analysis.

## Recording on an embedded target

The producer feature supports `no_std`. Schema serialization and compression
finish at startup using bounded working memory, without allocating a complete
catalog buffer. The recording loop keeps its ordinary native encoding pass.
Your logger backend still determines its own storage allocation requirements.

The startup traversal supports up to 256 distinct reachable native types,
including nested field types. A graph exceeding that limit returns a startup
error. Host-side catalog readers enable `cu29/decode-catalog` and use `std` to
allocate decoded value trees; `cu29-export/self-describing-logs` selects that
reader feature automatically.

Matching append operations reuse the catalog and application metadata. Rollover
retains those descriptions while reclaiming old data sections, so the remaining
samples still have their type and mission information. It can remove older
samples, keyframes, and lifecycle events; archive a recording before those are
needed for analysis or replay.

The [wheel example](https://github.com/copper-project/copper-rs/tree/master/examples/cu_self_describing_logs)
provides the complete application. The
[format reference](https://github.com/copper-project/copper-rs/blob/master/doc/self-describing-logs.md)
describes the encoding for readers that implement their own tooling.
