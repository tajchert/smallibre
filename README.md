# Calibre Nova

A small native macOS home for your ebooks. SwiftUI/AppKit interface, custom Swift book engine, SQLite library, and system zlib. No Python, Qt, Electron, Rust runtime, or downloaded package dependencies.

## Run

Requires macOS 14 or newer and an Xcode toolchain with Swift 6.

```sh
swift test
bash scripts/build-app.sh
open "build/Calibre Nova.app"
```

Open `Package.swift` in Xcode for development. The packaging script creates a locally ad-hoc-signed Apple Silicon app when run on Apple Silicon; it is not Developer ID signed or notarized for public distribution. Build on Intel for an Intel binary. Choose **Explore with a sample book** to try the included original sample.

## Working in 0.1

- Import EPUB, MOBI and standalone AZW3 files using Add Books, drag/drop, or Open With.
- Detect actual format, read embedded metadata, and thumbnail raster covers.
- Keep immutable private originals and deduplicate identical files by SHA-256.
- Persist a SQLite library, search titles/authors, sort, and browse format collections.
- Edit library title/authors/language/publisher/description.
- Personalize reflowable EPUB body fonts, spacing and margins; export changes as a new EPUB.
- Preview EPUB chapters in an isolated, network-blocked WebKit view.
- Search Open Library on demand and review title/author suggestions before applying them.
- Export verified copies without overwriting existing files, including to a selected mounted reader folder.
- Browse a mounted Kindle, refresh its inventory, see exact library matches, download supported books and delete selected device files with confirmation.

## Deliberate limits

This is the first working increment, not a complete Calibre replacement. **It does not yet convert EPUB to MOBI/AZW3, convert MOBI to EPUB, or access MTP devices.** MOBI/AZW3 exports preserve original bytes; library metadata edits are not embedded in those formats. The reader sheet rejects incompatible formats rather than renaming them. Modern MTP Kindles require a later transport increment.

Typography targets ordinary reflowable EPUBs, not fixed-layout books, scripted books or media overlays. Fonts use the device's generic serif/sans-serif families; there is no font embedding/subsetting. SVG covers fall back to a generated jacket. SVG spine chapters cannot be previewed. DRM, ZIP64, multipart archives, ambiguous resource paths and oversized resources are rejected. Limits: 256 MB compressed/expanded book, 64 MB per resource, 8 MB per XML document, 10,000 ZIP entries.

The SQLite database queries are simple and the UI currently loads library summaries in memory. A 10k-book performance target from the design has **not** been demonstrated. Corpus compatibility, update/backup UX, undo history, broader device discovery and recoverable MTP job receipts are future work. The current app exposes folder export, not automatic device synchronization.

## Your files

By default Nova stores its database, originals and cover thumbnails under:

```text
~/Library/Application Support/Calibre Nova/
  library.sqlite
  originals/<sha256>.<format>
  covers/<sha256>.png
  staging/
```

Deleting or editing the source file outside Nova does not change the imported copy. Exporting makes another file. Quit Nova before manually backing up the entire library folder, including any SQLite WAL files. Do not edit files in `originals/` or place the active database on a network share.

For isolated development launch the bundle executable with `--library /absolute/path` and optionally `--import /absolute/book.epub`. These flags select a separate test library and import a fixture; they are not required for normal use.

## Development

- `Sources/NovaCore`: bounded ZIP I/O, EPUB/MOBI inspection, EPUB edits, SQLite, imports/exports, metadata suggestions and preview sanitization.
- `Sources/NovaApp`: native library/inspector, panels, editor, chapter viewer and reader export sheet.
- `Tests/NovaCoreTests`: independently authored valid/malformed fixtures and regression tests.
- `scripts/build-app.sh`: release build, generated icon, bundle assembly and local signing.

The locally supplied `calibre/` checkout is reference material and is ignored by Nova's git repository. No Calibre implementation is shipped in this build. License: GPL-3.0-only; see `LICENSE`. The sample book “Small Hours” and synthetic fixtures were authored for this project and are distributed under the same license.

## Next increments

1. Expand EPUB fixtures, metadata fidelity, pagination/search and reversible library management.
2. Implement native MOBI content decoding and EPUB output, with text/navigation/image fidelity tests.
3. Implement a focused native AZW3 writer and certify output on actual Kindle models.
4. Add MTP transport and durable transfer reconciliation; certify unplug/retry behavior on hardware.

See `docs/architecture/native-swift-decision.md` for the accepted direction and `docs/architecture/verification-0.1.md` for the measured first build.

See `docs/architecture/kindle-management.md` for Kindle management behavior and hardware verification.
