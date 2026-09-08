# Conversion and MTP developer handoff

Baseline: Smallibre at `a5249ce`. Read [AGENTS.md](../../AGENTS.md) first. These are proposed implementation task briefs for other developers, not claims of shipped functionality. Each checkbox is a separately reviewable deliverable; developers should break it into regression test, implementation, validation and commit steps.

| Workstream | Deliverable | Can start independently? |
| --- | --- | --- |
| [EPUB → Kindle](epub-to-kindle.md) | Custom Swift EPUB → standalone AZW3 conversion, local export and mounted-reader send | Yes; no MTP required |
| [MTP readers](mtp-readers.md) | Detect, list, download and safely send/manage books over MTP | Yes; use authored existing AZW3/MOBI fixtures |

## Agree on this boundary first

Conversion produces a local immutable `PreparedBookArtifact`; a reader transport consumes it without converting or rereading mutable library settings. Proposed fields: artifact ID, source library ID, source original SHA-256, prepared-input SHA-256, settings digest, converter version/profile, output format, safe suggested filename, local URL, byte count, output SHA-256 and conversion warnings. Store the metadata durably with the artifact. These types do not exist yet.

The conversion developer owns `PreparedBookArtifact`, preparation/cache persistence and output validation. The MTP developer owns `ReaderDestination`, opaque item/session identities, capabilities and transport receipt extensions. Agree on Codable versioning and error/progress contracts before either edits `ReaderProcess.swift`, `ReaderBackup.swift`, `ReaderModel.swift` or `TransferView.swift`; land those shared changes in one small PR.

Separate stages: snapshot → prepare/convert → validate → retain exact artifact → transfer → verify → record outcome. Conversion failure must never start a transfer. Device failure must never require conversion again unless the retained artifact is invalid. Preserve source provenance so converted AZW3 can show as “On device” for its EPUB source, without matching by title. Distinguish byte-identical matches from verified derived-edition matches. Unknown external files remain unmatched until verified.

Keep the original EPUB SHA separate from the converted file SHA. If a book changes after preparation, the queued operation uses its captured snapshot; the next operation uses the new settings. A missing artifact on retry produces an explicit error, not a silent replacement with different bytes. Retention/cleanup must preserve artifacts referenced by incomplete receipts.

## Delivery and review

1. Merge the small shared contract and fake transport/artifact fixtures.
2. Develop both workstreams separately, with local export as the converter's first product and read-only inventory as MTP's first product.
3. Integrate converted AZW3 transfer over MTP only after each works independently.
4. Run `swift test`, `bash scripts/build-app.sh`, signature verification and `git diff --check`. Add focused suites for each workstream. Document toolchain, bundle-size delta, peak memory and representative timing; do not invent performance claims.
5. Hardware certification must identify exact model, firmware, macOS and connection mode. A mounted Paperwhite does not validate MTP. Use only authorized disposable device books.

Shared final acceptance: import an authored EPUB, edit it, convert once, send through each supported transport, verify returned bytes, open/read it on the device, reconnect, recognize its library provenance and preserve original/backup hashes. Force an unplug during upload and reconcile without silently overwriting, duplicating or deleting unrelated books.

No GitHub issues, repositories or developer assignments have been created by this handoff. Suggested issue IDs below are local task labels.
