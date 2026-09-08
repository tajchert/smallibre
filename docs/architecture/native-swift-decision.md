# Native Swift implementation

Accepted 2026-09-08: native Swift/SwiftUI/AppKit, custom focused book processing, no Python, Qt or Rust runtime. This supersedes the worker/portable-core recommendation in the original design proposal. The Calibre checkout is reference material and is excluded from Smallibre git history.

Iteration 1 is a usable, independently packaged macOS application: immutable local EPUB/MOBI import, embedded metadata and covers, persistent SQLite library, search, metadata changes, conservative EPUB typography/export, chapter preview, and verified file export to a selected mounted reader folder. Unsupported conversions must be visible and never disguised by renaming an extension. MTP and native AZW3 encoding remain subsequent engine milestones requiring physical-device testing.

Use macOS 14+, Swift Package Manager, system SQLite/zlib, Foundation XML, CryptoKit, SwiftUI/AppKit and WebKit. No downloaded dependencies. Keep UI state on the main actor and library operations on a dedicated actor. Bound archive sizes; preserve originals. Stage output, validate it, and use collision-safe exports. No mandatory network, accounts or background services.

First iteration acceptance: tests for real archive parsing, malformed input, metadata, duplicate import/persistence and EPUB edit/export; release app bundle launches; source files unchanged; measured installed size; versioned commits. Ship honest capability labels. Later iterations add online metadata suggestions, richer typography and native conversion/device compatibility.
