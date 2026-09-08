# Reader artifact contract implementation plan

> Execute inline with test-first verification. The user approved this first increment on 2026-09-08; later hardware and dependency decisions remain separate.

**Goal:** Establish the shared conversion/transport boundary with immutable manifests, contextual identities, durable receipt metadata and fault-injected verification tests.

**Architecture:** Conversion owns a versioned local artifact manifest. Transport consumes verified captured bytes. A small coordinator persists intent before upload and records verification or uncertainty; adapters remain responsible for serialized helper I/O and no-overwrite behavior.

**Tech stack:** Swift 6, Foundation, CryptoKit, Darwin; macOS 14+; no downloaded dependencies.

**Spec:** [Approved handoff](../../handoffs/README.md) and the first-increment design approved in this task.

## Constraints

- GPL-3.0-only; imported originals immutable; no device writes in this increment.
- Existing mounted-reader I/O, helper IPC and UI remain active through their existing implementations.
- Prepared artifact verification checks size, SHA-256 and local regular-file status; file presence alone is insufficient.
- Session-scoped MTP handles cannot identify a book across reconnects. Hashes are explicitly unknown until verified.
- Intent persistence must succeed before upload. Interrupted writes are uncertain, even on cancellation. Never retry or clean up automatically.
- New receipt metadata is optional so historical receipts decode unchanged. Unknown new schema versions are rejected.

## Tasks

- [x] Add failing artifact tests: manifest version/field validation, tampered/missing/symlink files, source/output separation and profile/settings identity.
- [x] Implement `Conversion/PreparedBookArtifact.swift` with validated SHA-256 values, provenance, manifest decoding and bounded verified reads.
- [x] Add failing transfer tests using a test-only actor adapter: valid readback, stale connection, changed bytes, failed intent persistence, disconnect before/after returning a handle, and cancellation.
- [x] Implement `ReaderTransport.swift`: destination/item identities, capabilities, errors, progress and list/fetch/upload contract. Destructive operations require a later safety design.
- [x] Implement `ReaderArtifactTransfer.swift`: persist versioned intent, upload once, retain returned identity, verify bounded readback, persist completion; preserve review state on any post-intent failure.
- [x] Extend `ReaderReceipt` with optional transfer metadata and test old JSON plus uncertain record round trips through real receipt files.
- [x] Update handoff status and document ownership, wire schemas, fake-only scope and remaining milestones.
- [x] Run focused tests, full `swift test`, bundle build, strict signature verification and `git diff --check`.

No automatic commit or push: the current request authorizes implementation, not publishing.
