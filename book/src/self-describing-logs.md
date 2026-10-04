# Self-describing logs

The experimental `self-describing-logs` feature records a payload catalog during
application startup. Offline tools use it to decode recorded payloads and
inspect their fields, types, and units. This workflow is introduced by the
[automatic catalog PR](https://github.com/copper-project/copper-rs/pull/1447)
and [standalone tools PR](https://github.com/copper-project/copper-rs/pull/1449).

## Application setup

Both project templates expose an application feature:

```toml
[features]
self-describing-logs = ["cu29/self-describing-logs"]
```

Enable it with `cargo run --features self-describing-logs`. Keep the ordinary
builder and log path:

```rust,ignore
let app = App::builder()
    .with_log_path("logs/app.copper", Some(32 * 1024 * 1024))?
    .build()?;
```

The existing `cu29_build::setup()` call is sufficient. The runtime macro obtains
the catalog's output types from the RON graph, including types declared in other
crates. Payloads keep their existing `Encode` derives. Cargo enables the codec's
companion descriptions, and typed references follow nested and recursive fields.
Reusable payload authors may use `#[bincode(describe)]` to provide descriptions
independently of feature forwarding.

A manually implemented encoder supplies a matching `ValueDecode` recipe. For
example, a wrapper encoding four float components can reuse the array recipe:

```rust,ignore
impl cu29::bincode::ValueDecode for Orientation {
    const DECODE: &'static cu29::bincode::ValueDecodeSpec =
        <[f32; 4] as cu29::bincode::ValueDecode>::DECODE;
}
```

Copper units and time carry their coherent storage units in the catalog. A
length created from centimetres still records metres. Captured custom logging
codecs need an explicit catalog for their chosen representation; startup errors
identify the task, output type, and codec.

## Embedded startup

`self-describing-logs` supports `no_std`. The generated builder serializes static
encoding recipes and compresses them with Heatshrink before initializing the
runtime. The serializer and compressor allocate no heap memory on success. Their
working memory is bounded: 256 reachable native type references, a 2 KiB compressor
buffer, and small output buffers. The logger reserves 4 KiB catalog sections using
its existing backend storage policy. Exceeding the type limit returns a startup
error.

Catalog chunks continue across sections and slabs. Readers check chunk sequence,
uncompressed length, and checksum. V2 Heatshrink catalogs and V1 Brotli catalogs
are both readable. Payload recording keeps its ordinary native encoding pass.

## Reading a recorded log

From a Copper checkout:

```sh
just logextract logs/app.copper catalog
just logextract logs/app.copper extract-copperlists --export-format jsonl
just logextract logs/app.copper fsck --deep
```

Appended logs require selecting a run with `--run N`; use `list-runs` to find its
zero-based index. The standalone reader uses the catalog stored in that run.

Host Rust tools enable `cu29/decode-catalog`; `cu29-export/self-describing-logs`
selects it automatically. Reader features use `std` and allocate value trees.

With `python` and `self-describing-logs` enabled on `cu29-export`:

```python
import libcu29_export as cu

catalog = cu.value_decode_catalog_unified("logs/app.copper", run=0)
for cl in cu.copperlist_value_iterator_unified("logs/app.copper", run=0):
    print(cl["msgs"][0]["payload"])
```

See the [single-crate wheel example](https://github.com/copper-project/copper-rs/tree/gbin/self-describing-logs-save/examples/cu_self_describing_logs)
for complete application setup and the
[format reference](https://github.com/copper-project/copper-rs/blob/gbin/self-describing-logs-load-tools/doc/self-describing-logs.md)
for wire details and offline limits.
