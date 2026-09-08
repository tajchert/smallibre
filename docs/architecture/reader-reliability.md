# Reader reliability and management — second increment

## Shipped behavior

- A bundled native Swift helper performs scans, imports, backups, device deletes, metadata writes and mounted-volume sends. The UI waits asynchronously with a 30-second deadline (60 seconds for sends) and cancellation. A process gate rejects a new helper until the previous process has exited, including after cancellation. A kernel-blocked process can remain pending termination; Nova reports that it is still stopping instead of starting another write.
- Device connection tokens and root identity prevent stale selections from acting on a replacement connection. Disconnect/cancel invalidates in-flight UI results.
- Refresh caches entries using root identity and file inode/size/modification/change timestamps. Recheck every file bypasses the cache. Cached matches are an optimization, not mutation authorization: writes/downloads rehash the source. Timestamp granularity means Recheck is appropriate after external edits that preserve attributes.
- The inventory excludes `.sdr` companion directories so KFX resources do not appear as individual books. Main KFX entries remain visible by filename. Protected MOBI metadata can be displayed without decrypting content. Protected/KFX imports and edits remain disabled. File backups of a main KFX entry are not complete package backups.
- Multiple selection supports batch import, file backup and deletion. Batches stop on the first failure, and cancellation prevents starting remaining items.
- Deletes and device metadata updates first create and verify a local backup. Receipts survive interruption under `reader-backups/<uuid>/receipt.json`; the app exposes these in Backups & history. A receipt not marked completed needs review. No automatic replay of an uncertain write occurs.
- Sends back up the exact prepared snapshot, export those same bytes without overwriting existing files, and record the outcome. Interrupted writes can leave hidden `.nova-*` device staging files; they are not automatically removed because their state may be uncertain.
- Device metadata editing supports DRM-free standalone MOBI 6 / AZW3 8 in UTF-8 or Windows-1252, with title, authors and publisher in the UI. Unknown EXTH fields are retained. Hybrid MOBI/KF8, protected books and unsupported header layouts are rejected. This is metadata rewriting, not content conversion. Library-copy editing remains separate.

Metadata updates use descriptor-relative staging and rename with parent/file identity checks. Deletes use nonrecursive unlink. These checks reduce concurrent replacement risks; the filesystem does not provide atomic compare-and-replace semantics here. Sidecars, annotations and device databases are preserved.

Backups are ordinary files, exposed in Finder for recovery/import/copy-back. Full KFX package reconstruction, automatic device-index repair and one-click restore are not claimed.

## Verification on 2026-09-08

- Helper timeout and cancellation tests passed, including rejection of concurrent helper launches.
- Backup failure prevents deletion; successful deletion leaves a verified backup and completed receipt.
- Interrupted send leaves backup and needs-review receipt; concurrent library editing cannot change the backed-up/exported snapshot.
- Parent-directory swap tests preserve external sentinel files during metadata replacement.
- Metadata growth preserves every following Palm record; protected and hybrid files are rejected.
- Cache reuse and `.sdr` exclusion tested. Initial new inventory: 61 main entries, 40 readable metadata entries and 20 editable standalone files. The disposable test book increases inventory to 62.
- Actual Paperwhite: created one uniquely named disposable copy, verified backup-before-delete, recreated it and updated its title. Source book stayed byte-identical. No existing device books were deleted or edited.
- Native UI: helper scan, selecting test book, editing publisher and viewing completed backup history passed.
- Independent Python check after UI update: all 374 non-metadata records were identical to the source, and the new publisher was present.
- Independent review findings about path replacement, send snapshots and helper termination were fixed, regression-tested and re-reviewed with no new material findings.
- Kindle was safely ejected for physical verification. Screen indexing/opening/page-turning awaits the owner's observation; this cannot be established from the mounted filesystem.

Disposable file left for the screen check: `Nova Reader Test EF0922DC-3F40-4FC2-A2A8-3629F4CD0A46.mobi`, with title `Nova Reader Test — ready to read`. Hardware-test backups are under `build/reader-hardware/reader-backups`; the UI publisher-edit backup is in the default library's `reader-backups` directory. Neither book bytes nor backups are tracked by Git.

## Format references

The custom Swift implementation was checked against the local Calibre metadata code and [libmobi's public structure documentation](https://www.fabiszewski.net/libmobi/structMOBIMobiHeader.html). No Calibre or libmobi implementation is bundled.

Final build: 4,840,697 summed bundle bytes (4.84 MB decimal); ZIP 2,289,464 bytes (2.29 MB decimal). Local ad-hoc signature verification passed. Final default suite: 35 passed, 4 opt-in tests skipped, zero failures. Disposable hardware tests were separately enabled and passed. Public notarization remains outside this increment.
