# Reader reliability and management implementation plan

Goal: finish the agreed reader-management improvements while preserving existing device books.

Architecture: a small bundled Swift helper performs USB I/O using JSON requests and responses. The app enforces deadlines/cancellation outside that process. Local backups/receipts make destructive operations reviewable and ambiguous interruptions visible. Scanner cache keys include connection identity and file stats; mutations always rehash.

- [x] Add process deadline/cancellation tests and helper target/protocol, then route device operations through it.
- [x] Add verified backup-before-delete, download-to-folder and interrupted-operation receipts; test failure before mutation and recovery evidence.
- [x] Add incremental cache and KFX grouping/format labels; test cache invalidation and companion exclusion.
- [x] Add bounded native standalone MOBI/AZW3 metadata rewrite with content-preservation tests. Reject protected/hybrid forms explicitly.
- [x] Add bulk selection, progress/cancel, backup access, metadata editor and retry UI.
- [x] Review, run full suite and release build, test read-only inventory plus disposable-book write/delete on hardware. Eject for physical indexing verification; user must observe the reader screen.
- [x] Document results/limits and commit increments.

The user approved these items and iterative implementation. No further design approval is pending.

Physical screen verification remains pending the owner’s observation after eject; filesystem and content-integrity checks completed.
