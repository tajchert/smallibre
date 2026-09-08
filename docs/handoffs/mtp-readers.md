# MTP reader support

**Goal:** manage a supported MTP Kindle from Smallibre even though it does not appear as a mounted Finder volume. Preserve mounted-drive behavior and the existing safety guarantees.

**First release:** discovery, inventory, verified download and send; then verified-backup deletion. MTP metadata replacement is a separate safety gate and can remain unavailable initially. Automatic mirroring, collections, annotations, device database edits, DRM/KFX package reconstruction and arbitrary phone support are out of scope.

Read [shared contracts](README.md), [AGENTS.md](../../AGENTS.md) and [reader reliability](../architecture/reader-reliability.md). Existing `ReaderStore` assumes local URLs, inodes and POSIX descriptors. MTP needs object/session identities and protocol operations; it must not pretend to be a filesystem or apply POSIX guarantees to remote objects.

## Dependency decision required in M1

The accepted stack currently has no downloaded dependencies. Default investigation: a focused Swift MTP implementation over macOS USB APIs. Compare it against a thin Swift wrapper around pinned native libmtp/libusb. The latter may reduce protocol/quirk work but adds C dependencies, distribution obligations and bundle/build complexity; it is not automatically authorized by this brief. Present measured size, supported operations, licensing notices, packaging and maintainability before adopting it. Do not add Python, Rust, Homebrew runtime requirements, privileged daemons or kernel extensions.

Primary upstream references: [libmtp](https://github.com/libmtp/libmtp) and its [build dependencies](https://github.com/libmtp/libmtp/blob/master/INSTALL). Its repository identifies an LGPL license and libusb integration. Verify exact chosen revisions and distribution obligations if selected; no dependency decision is implied by linking these sources.

## Proposed code boundaries

Create `Sources/SmallibreCore/ReaderTransport.swift` for destination/item/capability contracts and `Sources/SmallibreCore/MTP/` for session management, object inventory and operations. Keep raw USB/native binding details behind the adapter and inside a helper process. Add a fake transport and deterministic fault injection under `Tests/SmallibreCoreTests`.

Adapt mounted-volume operations through their existing `ReaderStore`, preserving descriptor-relative checks. Extend `ReaderRequest`/`ReaderResponse` in `ReaderProcess.swift` with versioned transport discriminators instead of forcing MTP into `root: URL`. Extend `ReaderReceipt` compatibly; old JSON receipts must remain readable. Update helper dispatch, `ReaderModel`, `ReaderView` and `TransferView` only after the contract lands. If a persistent helper is needed for an open MTP session, explicitly design framed IPC, request IDs, cancellation, termination/reaping and one active session; current one-shot helper execution is not a session manager.

## Tasks

### M1 — Read-only feasibility and dependency decision

- [ ] Obtain an authorized real MTP Kindle; record model, firmware, USB identifiers, macOS version and mode. The existing mounted Paperwhite test does not certify MTP.
- [ ] Prove discovery, opening/closing a session, listing storage and listing book objects without writing. Test competing access from another application, device sleep, disconnect and reconnect.
- [ ] Compare focused native Swift versus libmtp/libusb using evidence from this device. Document access requirements, necessary quirks, cancellation behavior, build dependencies and incremental release size.
- [ ] Select the backend with the project owner before shipping new dependencies. If hardware is unavailable, complete the fake transport but mark certification blocked.

**Exit:** a repeatable read-only device probe and a recorded backend decision. No broad compatibility claim based only on USB detection.

### M2 — Transport identities and mounted-drive parity

- [ ] Introduce `ReaderDestination`, `ReaderItemID`, `ReaderCapabilities` and typed errors/progress. Methods should cover list, fetch-to-local, upload-new, delete-selected and optional replacement; exact names can follow existing style.
- [ ] Model connection generation, device identity, storage ID, object handle and parent identity. Handles may change or be reused after reconnect; never treat them as globally stable IDs. If durable device identity is unavailable, require reselection and prohibit destructive reconciliation.
- [ ] Represent unverified content hashes explicitly. Object names, timestamps and sizes are hints, not exact library matches or authorization to mutate.
- [ ] Adapt existing mounted-drive code and migrate/cache receipts with backwards decoding. Test old receipts, old library startup and all existing filesystem safety cases.

**Exit:** the fake and mounted transports pass a shared contract suite; existing device functionality is unchanged.

### M3 — Session lifecycle and inventory

- [ ] Run MTP access in the helper with serialized protocol operations, bounded responses, timeouts and cancellation. Prevent a second writer while a previous helper is still stopping.
- [ ] Enumerate storage and known book locations with object/count/size bounds. Handle duplicate filenames, missing optional properties, unknown formats, multiple devices and multiple storages.
- [ ] Show connect/busy/disconnected/unsupported states in the UI. Exclude companion resources appropriately; do not infer KFX package completeness from one object.
- [ ] Cache metadata per device/storage/session context; invalidate on uncertain identity or reconnect. Fetch metadata lazily where practical; do not download the entire library just to populate filenames. Only mark an exact match after hashing verified bytes or equally strong evidence established by this app.

**Exit:** read-only inventory stays responsive during a stalled operation and stale UI results cannot attach to a replacement connection.

### M4 — Verified downloads and backups

- [ ] Stream objects to bounded local staging files; detect short/oversized reads and storage exhaustion. Validate declared size and actual content before library import.
- [ ] Create and verify durable local backups with hashes and receipt identity before allowing later deletion. Keep raw backup separate from supported-format import; no DRM bypass.
- [ ] Test disconnect mid-read, object replacement, reused handles, malformed names, invalid sizes and local disk-full. Partial files must never enter the library or count as verified backups.

**Exit:** supported downloads reuse `LibraryStore`'s immutable import/dedup pipeline; failed reads leave existing local/device books untouched.

### M5 — Upload and interrupted-operation reconciliation

- [ ] Consume the shared immutable artifact, including its output hash; no conversion inside transport. MTP development can use authored already-compatible fixtures before the converter is ready.
- [ ] Select a supported storage/parent, check available space when reported, choose a collision-safe unique name and upload as a new object. Recheck collision results; filenames are not necessarily unique on MTP.
- [ ] Persist intent before upload and returned object identity as soon as available. Download/read back the finished object and compare SHA-256 before marking verified/completed; do not assume the device supplies trustworthy hashes.
- [ ] Design receipts for partial/unknown uploads, especially a disconnect before an object handle is returned. Reconnect must freshly enumerate and verify candidates. Offer review/retry; never blindly retry a possibly completed upload or delete a similarly named object.
- [ ] Capability-gate rename/staging behavior; do not assume hidden names or atomic remote rename are available. Abort/cleanup only when the adapter can prove ownership and target identity; otherwise preserve uncertainty in history.

**Exit:** upload of an existing AZW3 verifies and opens on hardware. Disconnect at every upload/receipt transition produces an honest recoverable state without silent duplication or overwriting.

### M6 — Backup-before-delete and optional metadata replacement

- [ ] Enable deletion only for selected, freshly resolved objects on the same validated connection, with a verified durable backup. Revalidate immediately before delete; detect identity/content changes and refuse.
- [ ] Document residual protocol races: MTP may not offer atomic compare-and-delete. Disable mutation when identity checks cannot provide an acceptable guarantee. Never recursively delete folders, sidecars or device databases.
- [ ] Confirm deletion outcome by fresh listing where possible; disconnect/ambiguous protocol responses produce `needsReview`, not false success.
- [ ] Keep metadata editing disabled unless a separately reviewed strategy preserves a backup and can safely handle replacement. Download/edit/upload/delete is not an atomic update: it can duplicate books and affect annotations. Do not implement it as an invisible substitute for in-place metadata editing.

**Exit:** disposable-file deletion is certified with backup/hash evidence. A capability-disabled metadata button with a clear explanation is acceptable for the first MTP release.

### M7 — Packaging, regression and hardware certification

- [ ] If dependencies were approved, pin sources, include required notices, bundle the required native libraries, fix load paths and sign nested components. Verify no Homebrew or developer-machine paths are required at runtime.
- [ ] Run deterministic fake-transport tests for busy sessions, malformed replies, collisions, stale handles, short reads, upload uncertainty, backup failure, cancellation and old receipt decoding. Run all mounted-drive regression tests.
- [ ] On a clean Mac, certify discover → list → download → upload → verify → reconnect → delete disposable copy. Test unplug, device lock/sleep and a competing MTP client. Record results per model/firmware; unsupported cases remain explicit.
- [ ] Report bundle-size delta, scan time, transfer throughput, peak memory and cancellation latency on identified hardware. Update README and AGENTS only for delivered behavior.

**Definition of done:** M1–M5 and M7 pass for a named device; destructive controls stay disabled until M6 passes. Existing mounted readers still work. No existing owner book is changed during testing. End-to-end converted EPUB transfer is a shared follow-up once the independent conversion milestone passes.
