# Native Kindle feasibility implementation plan

**Goal:** Resolve the first native AZW3 and MTP feasibility gates for the requested EPUB-to-modern-Kindle workflow.

**Architecture:** Keep format experiments separate from user-facing export. Build a narrow standalone KF8 writer from bounded authored EPUB input and validate it with an independent decoder. Independently add a helper-only read-only native USB/MTP probe. Integrate product flows only after the corresponding gates pass.

**Spec:** [Conversion handoff](../../handoffs/epub-to-kindle.md), [MTP handoff](../../handoffs/mtp-readers.md), [shared contract](../../handoffs/artifact-transport-contract.md). The user authorized work on both blockers on 2026-09-08.

**Constraints:** Swift 6, macOS 14+, GPL-3.0-only; no downloaded runtime dependencies; immutable originals; bounded untrusted input; no unapproved hardware writes; no converter/MTP shipping claims from fake tests.

## Native AZW3 gate

- [x] Add an authored two-chapter EPUB fixture with Unicode, raster image, cross-chapter anchor and navigation.
- [x] Write failing tests for standalone KF8 metadata, text bytes, no-overwrite prototype output and explicit unsupported input.
- [x] Implement a narrow bounded EPUB-to-prototype model and uncompressed PalmDB/KF8 writer with skeleton/fragment/navigation indexes, FDST and resources. Derive offsets from UTF-8 bytes.
- [x] Decode output independently, verify chapter reconstruction, links, image and navigation. Pin format research revision and document limitations.
- [ ] On authorized hardware, open/read the generated disposable file and record model/firmware and feature checks. Do not mark C1 complete without this.

## Native MTP gate

- [x] Implement bounded protocol codec with malformed/short/count/transaction tests.
- [x] Implement helper-only native USB discovery, session open/close and read-only storage/object listing.
- [x] Add helper probe dispatch; distinguish unsupported/busy/disconnected/no-device outcomes.
- [x] Run local read-only probe; evaluate native API and dependency alternatives without adopting libraries.
- [ ] On MTP hardware, verify list, sleep/disconnect/reconnect and competing access; record backend decision with evidence.

## Integration gate

- [x] Review both implementations and run focused/full tests, package and verify signature.
- [x] Update handoffs with actual evidence, pending hardware gates and next work. Artifact persistence, full normalization, production validation, reader adapter/IPC/session integration and UI remain subsequent work; complete locally independent work while waiting for hardware.

No commits or publishing requested.
