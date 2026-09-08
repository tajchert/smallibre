# Working on Smallibre

## Product direction

Build a small native macOS ebook manager: quick local import, useful metadata, restrained EPUB personalization, and reliable reader transfers. Prefer focused Swift implementations and system frameworks over adding runtimes or general-purpose conversion stacks. macOS is the target; cross-platform support is not an accepted requirement. GPL-3.0-only. A local ignored `calibre/` checkout may exist as reference material; it is not a dependency or shipped implementation.

Read the current code and README before using older design plans. Documents under `docs/superpowers/` include proposals and unimplemented stages. `docs/architecture/kindle-management.md` describes the first reader increment; `reader-reliability.md` supersedes its cache/helper/edit limitations.

## Architecture

| Location | Responsibility |
| --- | --- |
| `Sources/SmallibreApp` | SwiftUI interface with AppKit panels and WebKit preview. `AppModel` and `ReaderModel` are main-actor observable UI state. |
| `Sources/SmallibreCore` | Book inspection, bounded ZIP handling, EPUB editing, SQLite library, metadata lookup, device operations and receipts. |
| `Sources/SmallibreReaderHelper` | Separate executable for potentially blocking mounted-device I/O; JSON request/response via `ReaderClient`. |
| `Sources/CSQLite`, `Sources/CZlib` | System library module maps; no downloaded package dependencies. |
| `Tests/SmallibreCoreTests` | Core regression tests and independently authored fixtures. |
| `Tests/SmallibreAppTests` | App startup/reader gating regression tests. |
| `scripts/build-app.sh`, `Resources/Info.plist` | Release bundle assembly, helper inclusion, icon generation, identifiers and versions. |

`LibraryStore` is an actor owning library operations and its SQLite wrapper. Import stages a file, hashes it, detects/validates its format, deduplicates by SHA-256, saves its immutable original, and then inserts its database record. `EPUBEditor` prepares a separate archive; MOBI/AZW3 library exports keep original bytes. `MOBIMetadataEditor` only rewrites supported standalone device metadata, not book content.

`ReaderModel` tracks connection state and serializes UI operations. `ReaderClient` starts the helper through `ReaderProcess`; `ReaderStore` performs device work. A process gate prevents overlapping helpers, with cancellation and deadlines. A kernel-blocked process can outlive a cancellation request: never interpret cancellation as proof a write did not happen.

## Invariants to preserve

- Keep imported originals immutable. Never overwrite an export destination. Back up and verify before device deletion or metadata replacement.
- Identify books by bytes, not title. Revalidate file hashes, connection tokens and root identity before acting on cached device selections.
- Keep device I/O in the helper. Preserve path containment, symlink rejection and descriptor-relative mutation checks; do not simplify them to unchecked path operations.
- Preserve sidecars, annotations and device databases. Deletes are nonrecursive and apply only to selected files. KFX main-file backups are not complete package backups.
- Preserve operation receipts and uncertain outcomes. Do not automatically replay interrupted writes or remove uncertain staging files.
- Enable reader actions only after library initialization succeeds. `LibraryLocation` migrates legacy storage, preserves conflicting copies and repairs interrupted migration. Legacy names in migration and typography compatibility code are intentional.
- Treat ebook content as untrusted data. Keep resource limits, archive validation and XML protections. Current limits include 256 MB book/archive, 64 MB resource, 8 MB XML, and 10,000 ZIP entries; ZIP64 and DRM are unsupported.
- Preview uses `smallibre-book` URLs, sanitization, CSP and WebKit network blocking. Keep the scheme handler, navigation policy and content rules consistent; never enable book scripts or remote requests for convenience.
- Open Library lookup is explicit and bounded, with caching and throttling. Review suggestions before applying; no bulk automatic lookup on import.
- Device metadata writing supports a narrow set of DRM-free standalone layouts. Preserve unknown EXTH fields and all following records; reject unsupported/hybrid layouts rather than guessing.

## Build and verify

Requires macOS 14+ and a Swift 6 Xcode toolchain. From the repository root:

```sh
swift test
bash scripts/build-app.sh
codesign --verify --strict build/Smallibre.app
git diff --check
```

`swift test` builds the app/helper and tests. Four external-file/hardware tests skip unless opted in. The rename baseline was 45 tests: 41 passed, 4 skipped. Test counts are historical, not a hard-coded requirement. Use a focused `swift test --filter TestClassName` while iterating, then the relevant full suite for code changes. Documentation-only work needs link/content checks, not a new app build.

Packaging produces `build/Smallibre.app` for the host architecture, including `SmallibreReaderHelper`, icon, license and sample book. Signing is ad hoc: do not claim Developer ID signing, notarization, universal architecture support or a validated public release. CI currently uses `macos-latest`; it does not certify the minimum supported OS.

Use a disposable library for manual development:

```sh
build/Smallibre.app/Contents/MacOS/Smallibre --library /tmp/smallibre-dev-library
```

Optional `--import /absolute/path/book.epub` imports into that library. Default storage is `~/Library/Application Support/Smallibre/`, including SQLite, `originals/`, `covers/`, `staging/`, reader cache and `reader-backups/`. Do not use a user's real library for destructive experiments.

External tests are explicit opt-ins; read their source before enabling:

- `SMALLIBRE_TEST_EPUB`: local EPUB round trip.
- `SMALLIBRE_TEST_NATIVE_KINDLE` and `SMALLIBRE_TEST_NATIVE_KINDLE_LOCAL`: helper-only native AZW3 hardware workflow; use a new Mac-local evidence directory. Writes two authored copies, backs up/edits/deletes the second, and retains the first for physical reading.
- `SMALLIBRE_TEST_READER_SCAN`: device inventory scan.
- `SMALLIBRE_TEST_READER_BOOK` and `SMALLIBRE_TEST_READER_FOLDER`: mounted-reader transfer; writes a new copy.
- `SMALLIBRE_HARDWARE_DEVICE`, `SMALLIBRE_HARDWARE_SOURCE`, `SMALLIBRE_HARDWARE_LOCAL`: creates, edits and deletes a disposable device copy, with local backups.

Use temporary fixture folders by default. Real device writes require user authorization for that workflow; preserve existing books. Never commit personal ebooks, libraries, receipts, device dumps, signing material or generated builds. Use authored/minimal fixtures for regression coverage. Keep file mutation, disconnection and malformed-input tests meaningful; don't replace them with tests that merely mirror implementation.

## Workflow and boundaries

Keep changes focused, inspect existing work before editing, and commit completed increments when requested. Do not push, publish or rewrite Git history without authorization. Match the existing actor/Sendable boundaries; keep expensive work away from the main actor. Explain behavioral changes and validation in the final handoff.

The Swift package and bundles are named Smallibre; a developer's checkout folder may still use the old name. Do not hard-code local paths. Update README claims when capabilities change. Converter implementation, MTP, automatic mirroring, one-click restore and 10k-book performance are not currently delivered.
