# Python Support

Copper has first-class Python support, but there are two very different ways to use
it.

If you only remember one thing from this chapter, remember this:

> Python for **offline log analysis** is reasonable.
> Python on the **live task path** is a prototyping hack and should not be treated as
> a production architecture.

## Catalog-Based Offline Analysis

<span class="version-marker" data-version="1.3">v1.3+</span>

If you want to analyse a self-describing recording without rebuilding its
application or registering Rust payload types, use Copper's catalog reader.
It returns ordinary Python dictionaries for the recorded values.

Reuse the wheel recording from
[Self-Describing Logs](./self-describing-logs.md#1-try-a-complete-recording).
On Linux, with Rust and Python 3 available, run this complete sequence from the
copper-rs repository root, using the checkout named in the
[edition notice](./introduction.md#reading-version-markers):

```sh
cargo build -p cu29-export --lib --features python-extension-module,self-describing-logs
mkdir -p target/python
cp target/debug/libcu29_export.so target/python/libcu29_export.so
PYTHONPATH=target/python python3 - <<'PYTHON'
import libcu29_export as cu

path = "examples/cu_self_describing_logs/logs/wheel.copper"
catalog = cu.value_decode_catalog_unified(path)
count = 0
for cl in cu.copperlist_value_iterator_unified(path):
    print(cl["id"], cl["msgs"][0]["payload"])
    count += 1
assert count == 10
PYTHON
```

`python-extension-module` builds an importable extension and enables the Python
API; `self-describing-logs` enables the catalog reader. The temporary
`PYTHONPATH` makes this built module available to that Python command.

You see the source wheel sample for each of the ten cycles. Inspect the catalog
when you need field descriptions or storage units for plotting.

For a multi-run recording, pass `run=1` to
`copperlist_value_iterator_unified` to select the zero-based run index you found
with `list-runs`. A single-run log needs no `run` argument.
`value_decode_catalog_unified` takes only the path: its shared catalog describes
all compiled missions. Each CopperList uses the selected run's mission and output
order.

Each cycle dictionary has `id` and `msgs`, whose entries retain payload, time
of validity, metadata, and capture status. Integers keep full precision. A
corrupt record raises `IOError` and stops iteration. These APIs are experimental
and run offline.

## Application-Specific Offline Analysis

If you already expose Rust payload types through an application-specific PyO3
module, you can read typed CopperLists alongside structured logs and runtime
lifecycle records. The `cu_flight_controller` example shows this approach in
`src/python_module.rs`. Use it when your analysis needs those Rust types; the
catalog reader above supplies ordinary dictionaries without that registration.

## Runtime Python Tasks

Copper also provides `cu-python-task`, which lets one task delegate its
`process(...)` body to a Python script.

This is intentionally a prototyping feature, not a performance feature.

The reason is simple: as soon as Python enters the live execution path, you lose the
main properties Copper is designed to preserve:

- low latency
- low jitter
- predictable allocation behavior
- tight control over the realtime path

Python allocates constantly, and the Rust/Python boundary adds even more overhead.
That is enough to ruin the realtime characteristics of the stack. Compared to a
native Rust Copper task, the performance is abysmal.

## The Two Execution Modes

### `process`

In process mode, Copper spawns a separate Python interpreter and exchanges
length-prefixed CBOR frames over stdin/stdout.

Advantages:

- the GIL is not inside the Copper process
- interpreter failures are more isolated

Costs:

- CBOR serialization and deserialization every cycle
- copies and allocations every cycle
- interprocess overhead
- more latency and jitter

### `embedded`

In embedded mode, Copper calls Python directly inside the process through PyO3.

Advantages:

- no child process
- no extra CBOR IPC layer
- usually somewhat less overhead than `process`

Costs:

- the GIL is now inside the Copper process
- Python exceptions happen inside the runtime process
- values still have to be converted and allocated every cycle
- still not suitable for realtime use

In this workspace, embedded mode is also not supported on macOS.

## What It Is Actually For

The intended workflow is narrow:

1. prototype one task quickly in Python
2. confirm the algorithm is doing the right thing
3. rewrite that task in Rust immediately afterward

If you want, you can use an LLM to draft the Rust rewrite once the Python behavior is
stable. But the final destination should still be Rust, not a permanent Python task.

Use this feature as a disposable bridge, not as the architecture.
