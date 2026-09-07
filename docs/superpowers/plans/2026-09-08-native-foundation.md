# Native foundation implementation plan

Goal: deliver the first working native Calibre Nova increment under the accepted native Swift decision.

Architecture: NovaCore contains format inspection, immutable library/storage and export; NovaApp contains SwiftUI views, AppKit panels and a restricted chapter preview. System SQLite and zlib provide persistence and ZIP primitives. No Calibre runtime is shipped.

## Iterations

1. Package and book engine: `Package.swift`, `Sources/NovaCore/{ZIPArchive,BookMetadata,EPUBBook,MOBIBook}.swift`, system module maps, `Tests/NovaCoreTests/BookEngineTests.swift`. Write failing fixtures for EPUB metadata, deflate, unsafe ZIP paths and MOBI metadata; implement parser/writer and run `swift test`. Contract: `BookInspector.inspect(URL) -> BookMetadata`, `EPUBBook(data:)`, named archive resources.
2. Library and preparation: `LibraryStore.swift`, `EPUBEditor.swift`, `LibraryTests.swift`. Test reimport deduplication, database reopen, immutable originals, metadata revision and edited EPUB round-trip. Contract: library actor imports/queries/updates and prepares validated export files. Run tests and commit.
3. Native application: `Sources/NovaApp/`, `scripts/build-app.sh`, `Resources/Info.plist`. Library/cover grid, inspector, import/search, edit sheet, export, restricted chapter preview. Build release app, launch and inspect actual UI. Add focused integration tests when UI work exposes core behavior gaps; commit.
4. Verification and handoff: independent review, fix findings, run tests/release build, measure bundle size, document supported behavior/limitations and future milestones, commit. Leave runnable app under `build/Calibre Nova.app`.

The implementation is authorized by the owner's instruction to build iteratively and use git. No design approval is pending.
