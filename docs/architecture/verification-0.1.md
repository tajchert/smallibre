# First native increment verification

Verified locally on 2026-09-08, Apple Silicon, macOS 26.6.2 (25G83), Xcode 26.6 and Apple Swift 6.3.3. Deployment target is macOS 14; older OS versions and Intel have not been exercised.

## Measured artifact

- `build/Calibre Nova.app`: 3,362,615 bytes summed across bundle files (3.36 MB decimal; approximately 3.3 MB allocated on this filesystem).
- `build/Calibre-Nova-0.1.zip`: 1,853,871 bytes (1.85 MB decimal).
- Release executable links Apple/system frameworks, Swift libraries, SQLite and zlib. No third-party runtime is bundled.
- Bundle plist validation and strict local code-signature verification passed. Signing is ad hoc, not Developer ID signing or notarization.

These measurements exclude the user's library, generated covers and database. Small binary size is demonstrated; comparative speed and memory claims are not yet benchmarked.

## Checks completed

- `swift test`: 18 tests, zero failures. Includes format sniffing, EPUB/MOBI metadata, malformed archives, overlapping ZIP payloads, immutable originals, deduplication, database reopen, collision-safe export, metadata refinement preservation, UTF-16 input, XHTML namespaces, typography eligibility, preview sanitization and metadata response bounds.
- `bash scripts/build-app.sh`: successful release build, icon generation, bundle assembly and signature verification.
- Live native UI: sample import, selection, typography editing, EPUB chapter preview, folder export and library persistence after restart.
- Independently inspected the UI-exported EPUB using Python ZIP/XML readers: CRCs passed, mimetype was first and uncompressed, and typography markup used the XHTML namespace.
- Live Open Library search returned real title/author suggestions; cancelled the sheet without applying unrelated metadata to the sample.
- Independent code review identified archive, XML fidelity, preview and typography issues. Fixes were regression-tested and re-reviewed with no additional critical findings.
- Independent WebKit probe loaded raw SVG referencing a temporary loopback server. Control without content rules made a request; the production rules made zero requests during an eight-second observation. The temporary server was stopped.

The included original sample and synthetic fixtures were used; no personal books were needed. GitHub Actions configuration is included, but no remote CI run was performed.

## Still to verify or build

No large real-world book corpus, physical reader transfer, EPUBCheck validation, 10,000-book benchmark, Intel build or older macOS test has been completed. Native MOBI content conversion, AZW3 writing and MTP transport are not implemented. Folder export and EPUB personalization are the supported preparation/transfer paths in this increment. See README for format limits and the next increments.

## User-provided EPUB compatibility check

Also tested the owner's `Silos.epub` locally on 2026-09-08: 1,871,289 bytes, 143 archive resources and 96 spine items. The optional `LocalBookTests` check passed import, duplicate detection, unchanged byte-identical preparation, metadata and typography export, every exported resource's integrity check, preview HTML preparation for every spine item, database reopen and source byte preservation. This exercises preview preparation, not visual rendering of all chapters or physical-reader fidelity. The complete check took approximately 0.42 seconds on this host; this is a single warm development test, not a product benchmark. Temporary library/export files were removed and the book was not added to Git.

Repeat with `NOVA_TEST_EPUB=/absolute/path/to/book.epub swift test --filter LocalBookTests`. The test skips when the environment variable is absent.

## Mounted Kindle hardware transfer

On 2026-09-08 the owner authorized testing a connected Paperwhite, mounted as `/Volumes/Kindle`. The production LibraryStore imported an existing 4,152,217-byte MOBI into a temporary library and exported two uniquely named copies to the device's documents folder. Both readbacks were byte-identical to the source; exporting twice selected different filenames and preserved the first copy. The original source remained byte-identical. Test copies and temporary library were removed afterward. No existing books or device configuration were changed.

This verifies the mounted-volume core transfer path on real hardware, including collision handling. It does not verify Kindle indexing/rendering after eject, interrupted transfers, MTP or EPUB conversion. The earlier statement that no physical transfer had been tested is superseded by this check.

Repeat only with an authorized device: set `NOVA_TEST_READER_BOOK` to an existing compatible book and `NOVA_TEST_READER_FOLDER` to the mounted documents folder, then run `swift test --filter ReaderTransferTests`. The test skips when these variables are absent.
