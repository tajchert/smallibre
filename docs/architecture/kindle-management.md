# Mounted Kindle management

This document records the first increment. See [reader-reliability.md](reader-reliability.md) for the current helper, caching, bulk actions, backups and metadata editing.

The Kindle sidebar provides a refreshed inventory of supported ebook file extensions under a mounted documents folder. Nova automatically locates a single `/Volumes/Kindle*` volume, also accepts a user-selected folder, and observes mount/unmount notifications. Scanning happens off the main actor. The initial scan hashes file contents; it is not yet cached or incremental.

ReaderStore owns device reads, download verification and guarded deletion. ReaderModel owns the UI snapshot and serializes device operations. LibraryStore remains the sole writer of the Mac library. SHA-256 matches drive “In library” and “On Kindle” indicators; titles are not used to infer identity. Converted/edited editions can appear separately. This is inventory synchronization with explicit actions, not automatic mirroring or deletion.

Downloading supported unprotected files uses a verified temporary copy and the existing immutable import pipeline. Editing downloads a library copy first and opens Nova's editor. MOBI/AZW3 metadata is not written back to the reader. Unsupported/protected formats remain visible with filename and an explanation; their import/edit actions are disabled. KFX component files may appear separately: this version does not reconstruct KFX packages.

Delete requires app confirmation, validates the source hash and root identity, rejects links/path traversal and uses nonrecursive unlinkat through directory descriptors. Only the selected book file is removed. Sidecars, annotations, folders and Kindle databases are untouched. Deletion is permanent; downloaded library copies survive. A changed connection requires choosing the folder again. Individual oversized/unreadable files do not discard readable scan results.

## Verification, 2026-09-08

- Real Paperwhite inventory: 118 files, 38 with supported metadata. Cold development scan approximately 16 seconds; no comparative performance claim.
- Native UI: Kindle sidebar/list rendered, downloading one existing MOBI succeeded and changed its row to “In library”. The device source was not changed.
- Unit checks: download/deduplication, changed file refusal, directory replacement preservation, root replacement refusal, symlink exclusion, oversized-file partial scan.
- Device deletion tested only against temporary fixture folders, not the owner's existing books.

Next improvements: cached/incremental scans, cancellation/progress detail, grouped KFX entries, bulk selection, durable transfer receipts and native metadata writing after format-specific compatibility tests.

Final validation: 23 default tests passed; three opt-in external-file/device tests skipped. The real-device scan was separately enabled and passed. Independent review findings were fixed and re-reviewed with no additional material findings. Deletion checks narrow concurrent-replacement races; POSIX unlink does not offer atomic compare-and-delete. Connection tokens also reject records retained across reconnects. The final release bundle is approximately 3.6 MB.

Final rescan caveat: after the final build, a repeat UI scan and opt-in test stalled in macOS `__open` called by NSURLDirectoryEnumerator (confirmed with a process sample), rather than in hashing/parsing. The earlier 118-file scan and UI download succeeded. The repeat test was interrupted. Connection recovery/retry and isolating potentially blocking device I/O in a helper process remain follow-up work; the final rescan was not verified to completion.

After the owner reconnected the Kindle, the final read-only scan passed: 118 files, 38 supported metadata records, approximately 0.45 seconds in this warm run. The native app also displayed the inventory and accepted Refresh without an error. This closes the pending final-rescan verification; robust handling of future blocked device I/O remains a reliability improvement.
