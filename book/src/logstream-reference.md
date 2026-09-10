# LogStream Transport and Receiver Reference

Start with [Streaming Logs and Live Telemetry](./logstream-telemetry.md) for the
UDP walkthrough. This reference covers custom carriers, receiver ownership, and
format details needed when sizing or extending an integration.

## Serial and transparent radios

A raw serial byte stream needs packet framing before LogStream can decode it.
`cu29-logstream-serial` supplies `SerialLogStreamTx<S, N>` and
`SerialLogStreamRx<S, N>` over `cu_serial::SerialIo`.
`SerialLogStreamTxResources<S, N>` consumes a `serial` resource and exports `tx`;
the RX provider consumes `serial` and exports `rx`. Each provider owns its serial
resource; choose one direction per carrier with these adapters.

A UART can feed an HC-12 radio resource, whose serial output feeds the LogStream
framing resource. Define concrete application aliases for those generic
providers, then bind the final `tx` slot to your streaming destination. The
[serial adapter](https://github.com/copper-project/copper-rs/tree/master/components/res/cu29_logstream_serial)
and [HC-12 examples](https://github.com/copper-project/copper-rs/tree/master/components/res/cu_hc12)
provide the transport and radio details. Do not mix raw application bytes and
LogStream packets on the same stream without an explicit multiplexing protocol.

The serial adapter wraps each packet in `0x7e` delimiters, escapes `0x7e` and
`0x7d`, and appends an escaped four-byte big-endian CRC32C of the unescaped packet.
RX verifies and removes that checksum before handing the packet to LogStream.
Invalid or oversized frames are discarded; the next delimiter resynchronizes RX.
Both serial peers must use this framing.

The compile-time frame capacity `N` bounds packets to `(N - 2) / 2 - 4` bytes,
allowing worst-case escaping. The default `N = 514` therefore permits a **252-byte
packet**, not the UDP demo's 1200-byte MTU. Configure MTU within this bound, use a
small burst (one for slow links), and budget for checksum, escaping, and UART
start/stop bits as well as Copper traffic.

The scheduled sender drains pending serial writes while idle and during bounded
shutdown. If you drive an endpoint directly, including in `no_std`, keep calling
`CuStreamTx::poll_pending()` until it returns false. Each poll performs at most
one nonblocking UART write. `WouldBlock` means retry the packet after the current
frame drains; successful submission only means the adapter accepted it.

## Custom receivers

Use the generated twin when its profile fits. For explicit receiver bounds or a
custom archive pipeline, construct `SessionRouter` and supply packets through
`CuStreamRx`. Its manifest describes decoder geometry and the application schema;
the receiver checks those requirements against its own allocation limits before
constructing decoders.

| API | Use |
| --- | --- |
| `NativeArchive<P>` | Archive full captures using the application's generated dataset type. |
| `CaptureArchive<P>` | Preserve selective captures for live or offline reconstruction; used by the generated twin. |
| `cu29_export::stream_continuity_reader` | Read archived manifests, gap ranges, and recovery boundaries programmatically. |
| `telemetry::telemetry_channel` | Publish typed, already decoded values to an independent presentation reader. |

`SessionRouter` lends `SessionEventRef` values to callbacks. Encoded bytes remain
receiver-owned; if a callback fails, `drain_events` can retry delivery. Copy with
`event.to_owned()` only when you need a separately owned event. Make your callback
safe for retries; the generated twin reports archive failures instead of hiding
them behind an application retry loop.

`ReceivedManifest` includes the decoded manifest and its original verified
record. Pass it to the archive constructor. Recovery events also carry their
original record, allowing archival without recreating the bytes. Publish frames
only after `archive.accept(...)` succeeds. To publish structured logs yourself,
take the owned entry with `archive.take_structured_log()` immediately afterward.

The telemetry channel has one publisher and one reader, bounded retention, and
an independent coalesced status slot. `ready().await`, `wait_timeout`, and
`register_waker` support different event loops. A registered waker should only
schedule work or unpark a thread. It must not process data or block the receiving
worker. Consume frames, changed status, and publisher closure before waiting again.

Assembly buffers are recycled and grow within configured bounds as needed.
Borrowed delivery avoids mandatory per-event copies, but session discovery,
RaptorQ decoding, task-state restoration, and payload decoding can allocate.
The presentation ring is also a host-side queue, not a real-time wait-free
primitive. Consult the [receiver source](https://github.com/copper-project/copper-rs/blob/master/core/cu29_logstream/src/router.rs)
when changing capacities or callback ownership.

## Storage, pacing, and shutdown

Each generated destination has a sender worker with bounded encoded-record pools,
packet queues, continuous FEC storage, and retained recovery data. CopperLists
and keyframe capture objects are released before transmission waits on the
carrier. Structured logging adds a bounded copy of the successful local encoded
entry into each destination's preallocated storage.

The destination reserves four structured-record buffers, each capped at 4096
bytes including the record header, or `max_object_bytes` if smaller. These buffers
count toward `memory_budget_kib`. Thread stacks, allocator/channel bookkeeping,
and bounded-input RaptorQ scratch allocations are additional; this setting is a
buffer budget, not a whole-process memory ceiling.

Replay traffic, recovery traffic, and structured logs share byte-deficit
scheduling with weights **3:1:1**. Unused capacity is available to other ready
lanes. The bitrate/burst budget covers every lane, while separate bounded packet
queues keep structured traffic from filling the replay queue. Ordinary data
expires after `max_latency_ms`; the latest complete recovery bundle remains
available for periodic retransmission until replaced or stopped.

Pool exhaustion, queue overflow, expiry, carrier backpressure, and shutdown
shedding have counters. `SenderMonitor::snapshot()` publishes worker health at
10 Hz, and shutdown statistics/failures are written through Copper structured
logging. Shutdown stops repetition and drains only to the configured latency
deadline. The `no_std` `SenderCore` needs a caller to provide `CuTime` and drive
`poll`; immediate codec sinks do not enforce pacing themselves.

## Compatibility and wire sizing

Build sender, receiver, and logreader for the same producing application and
Copper revision. Packets, semantic records, RLC fragments, and session manifests
carry no version fields. Schema validation is not a compatibility negotiation
mechanism. Unified-log encapsulation version **1** describes the file and section
layout, not the encoded application content.

Serialized CopperLists contain `id` and `msgs`; lifecycle state stays in memory.
The move to `cu-bincode` ULEB128 timestamp-delta and backreference helpers preserves
the compressed metadata bytes. It does not change ordinary integer encoding.

Current packed header sizes are:

| Layer | Bytes |
| --- | ---: |
| Continuous RLC source packet | 32 |
| Continuous RLC repair packet | 36 |
| RaptorQ object packet | 51 |
| Semantic record | 45 |
| Protected RLC fragment | 20 |

Multi-byte packet-header fields are big endian. The generated sender uses `min(mtu_bytes - 51, 1128)` bytes per symbol,
reserving the largest current packet header and respecting its fixed storage cap.
At MTU 1200, symbols are therefore at most 1128 bytes. Maximum RLC source, RLC repair, and RaptorQ packets are therefore 1160,
1164, and 1179 bytes respectively. Use actual packet lengths for bandwidth
accounting. The [wire encoder](https://github.com/copper-project/copper-rs/blob/master/core/cu29_logstream/src/wire.rs)
is the authority for a custom implementation.

Packet extent comes from the carrier; there is no redundant payload length or
packet sequence counter. FEC identifiers and record identities provide recovery
and deduplication. Protected fragments retain record length and fragment index;
fragment count and payload extent are derived. The 11-byte RaptorQ OTI omits the
library's reserved zero byte, which decoding restores.

A semantic record's payload length comes from its reassembled extent. Its BLAKE3
digest covers record kind, object ID, derived length, and payload; appended or
truncated payloads fail validation. Recovery points reference the exact manifest
and keyframe digests.

Manifests carry identity, decoder requirements, optional feedback cadence and
destination key, and application schema. Sender bitrate, latency, adaptation,
repair policy, and memory limits remain local. The receiver also enforces its
own finite-object and buffering limits; a sender cannot raise them through a
manifest.

Both data and feedback packets require **carrier-provided packet integrity**;
neither has an inner CRC. UDP relies on normal network/link checksum protection,
while the serial adapter supplies CRC32C. Delivery, ordering, and uniqueness are
not guaranteed. Feedback reports retain receiver sequence numbers so stale or
duplicate reports do not refresh health. Record digests independently check
reassembled content and recovery references.
