# Artifact and reader contract v1

Implemented foundation, 2026-09-08. This is not a delivered converter or MTP backend. The current mounted-reader UI and helper request format still use their existing implementations.

## Ownership and entry points

- `Sources/SmallibreCore/Conversion/PreparedBookArtifact.swift`: conversion-owned manifest, source provenance and bounded local byte verification.
- `Sources/SmallibreCore/ReaderTransport.swift`: transport-owned session identities, explicit hash knowledge, read/list/new-upload capabilities and adapter protocol.
- `Sources/SmallibreCore/ReaderArtifactTransfer.swift`: versioned transfer record and helper-side verification coordinator.
- `Sources/SmallibreCore/ReaderBackup.swift`: optional `transfer` metadata in the existing receipt format.
- `Tests/SmallibreCoreTests/PreparedBookArtifactTests.swift` and `ReaderArtifactTransferTests.swift`: authored MOBI artifact fixture, test-only actor adapter, real on-disk receipt persistence and deterministic failures.

The adapter protocol currently exposes list, fetch-to-new-local-file and upload-new. Destructive methods/capabilities await M6's backup and identity design. It must not be used to implement download/edit/upload/delete as an implicit metadata replacement.

## Artifact wire format

`PreparedBookArtifact` encodes a JSON object with required `schemaVersion: 1`, `id`, `provenance`, `outputFormat`, `suggestedFilename`, `localURL`, `byteCount`, `outputSHA256` and `warnings`. Unknown schema versions are rejected; unknown additional JSON fields are ignored. SHA-256 values encode as validated 64-character lowercase hexadecimal strings. Output format is `epub`, `mobi` or `azw3`.

Provenance records `sourceLibraryID`, `sourceOriginalSHA256`, `preparedInputSHA256`, `settingsSHA256`, `converterVersion` and `profile`. Keep all these fields plus output format when defining cache identity; do not persist Swift's randomized `hashValue`. The converter must define/version the canonical settings representation before C5 implements a persistent cache. A digest records the captured settings identity; it is not a reversible settings document.

The manifest has immutable fields. That does not enforce filesystem immutability: publication and retention remain C5 work. `verifiedData()` rejects missing files, symlink leaves, nonregular files, changed sizes and wrong hashes, with a 256 MB ceiling and bounded reads. It returns one captured `Data` value; upload consumes that value even if the file subsequently changes. This is an integrity check, not an AZW3 semantic validator. The producer must validate the format before publishing a manifest. Parent directories must be app-controlled local storage; this helper does not replace device path containment or descriptor-relative mutation checks.

## Identity and verification

`ReaderDestination` contains a connection UUID and a tagged endpoint:

- `mounted`: local root URL and root identity.
- `mtp`: optional durable device identity, storage ID and selected parent object.

`ReaderItemID` includes its destination and a tagged locator: mounted relative path, or MTP object handle plus parent identity. Codable uses Swift's associated-value enum representation with named labels; these names are part of v1's contract. `requireCurrent` rejects a changed connection/endpoint, a mismatched locator type, unsafe relative paths and invalid MTP handles/parents. It does not perform device I/O or authorize deletion.

Every reconnect must receive a new UUID, including when the device reuses an object handle. Missing durable device identity permits only current-session work; it does not permit destructive reconciliation across reconnects. Metadata names, sizes and timestamps are hints. `ReaderContentHash.unverified` cannot be interpreted as an exact or derived-edition match.

The adapter must serialize device I/O inside the helper, enforce bounds while streaming, create only new destination objects/files, and enforce no-overwrite behavior. The coordinator does not implement USB protocol operations, collision resolution, helper process gating, session ownership or arbitrary adapter concurrency. Those remain required adapter integration work.

## Upload and receipt transitions

`ReaderArtifactTransfer.send` accepts an artifact, selected destination, adapter, app-controlled readback directory, durable persistence callback and optional phase callback. Phases are preparing, uploading, verifying and completed. There is no byte-level progress contract yet.

1. Check current destination/capabilities and validate/capture the artifact bytes.
2. Create private local readback staging. Construct and durably persist an `intent` record. If this fails, do not upload.
3. Recheck connection/cancellation and upload the captured bytes once.
4. Retain the returned identity and durably persist `uploaded`.
5. Recheck connection, fetch bounded bytes, verify size/SHA-256 locally and recheck connection again.
6. Durably persist `verified` before reporting completion.

Any error after persisted intent—including cancellation or a receipt-write failure—attempts to persist `needsReview`. No automatic retry or device cleanup occurs. `ReaderArtifactTransferFailure` carries the review record and indicates whether its persistence also failed. The last durable record can then remain `intent` or `uploaded`, both uncertain. If the adapter never returned a handle, keep the unknown outcome without inventing an object identity.

`ReaderTransferRecord` has `schemaVersion: 1`, operation UUID, full artifact manifest, destination, optional item ID, state and optional detail. Uploaded/verified records require a matching valid item identity when decoded. Review records may retain an invalid returned identity for diagnostics; it must never authorize a subsequent operation. Unknown schema versions fail decoding.

The existing outer `ReaderReceipt` now has optional `transfer`; historical JSON without it continues to decode, including historical string hashes and state names. Future integration must keep outer state semantics (`inProgress`, `completed`, `needsReview`) for existing UI consumers while storing typed state in `transfer`. The new coordinator is not yet connected to the existing send path. A persistence callback must save durably, including when its task is cancelled, and must not silently swallow errors.

`requiresArtifactRetention` is true for intent/uploaded/review records. It is a cleanup constraint, not a cleanup implementation. C5 must preserve artifacts referenced by incomplete records, preserve unknown/unreadable receipt data conservatively, and fail explicitly when a retry's artifact is missing or invalid. Verified source/output provenance can later support derived-edition matches, but no library matching behavior changes in this increment.

## Evidence and remaining gates

Tests cover manifest tampering, missing/symlink artifacts, snapshot changes after intent, stale/reused handles, invalid identities, short/oversized/corrupt readback, disconnect before handle return, actual task cancellation, receipt failures at each stage, legacy decoding and future-version rejection. Device calls use an authored test adapter; receipt files and coordinator logic are real.

Not implemented here: persistent artifact storage/cache and settings canonicalization, EPUB normalization, AZW3 writing/validation, mounted adapter parity, MTP USB backend, helper IPC versioning/session lifecycle, UI integration, automatic provenance matching, deletion or metadata replacement. C1 and M1 hardware gates remain unpassed; no connected-device tests or device writes were performed.

### Local validation (2026-09-08)

- macOS 26.6.2 (25G83), arm64; Apple Swift 6.3.3. This does not establish macOS 14 runtime certification.
- `swift test`: 59 tests executed, 55 passed, four opt-in external/hardware tests skipped, zero failures. New coverage accounts for 14 tests.
- `bash scripts/build-app.sh` and `codesign --verify --strict build/Smallibre.app`: passed with ad-hoc signing.
- `git diff --check` and relative documentation link checks: passed.
- Clean release baseline built from `0efca1b` using the same toolchain: 4,916,132 logical bundle bytes. This increment: 5,703,668 bytes. Delta: +787,536 bytes (+16.02%). Both app and helper include the new Codable contracts through receipt decoding. Figures sum regular-file logical sizes, not disk allocation or compressed download sizes.
- Converter/MTP throughput, peak runtime memory and cancellation latency on hardware are not measured because those implementations are not present. The in-memory artifact/readback coordinator is bounded by the 256 MB per-file ceiling, but this is not a measured process-memory budget; streaming refinements remain an integration consideration.
