# Library Organization Implementation Plan

**Goal:** Deliver organization, bulk metadata edits, and saved library filters in that order.
**Architecture:** Library-only organization and filters live in SmallibreCore and SQLite;
AppModel owns selection/filter state, SwiftUI uses existing design components.
**Tech Stack:** Swift 6, SwiftUI/AppKit, system SQLite, macOS 14+.
**Spec:** ../specs/2026-09-11-library-organization-design.md

## Constraints
- Original ebooks remain immutable; organization does not alter embedded metadata.
- No new runtimes, dependencies or device write workflows.
- Preserve legacy library records and device command gating.

## 1. Organization
- [x] Add failing LibraryOrganizationTests for legacy decode, normalized persistence, invalid
  sequence values and byte-identical exports; run focused tests before implementation.
- [x] Add BookOrganization model, backwards-compatible LibraryBook decoding and update validation.
- [x] Add organization fields to detail editor and inspector; series sort and read filters.
- [x] Run core tests and build app.

## 2. Bulk editing
- [x] Add failing atomic update/selection tests.
- [x] Implement explicit BulkMetadataEdit patch and transactional library API.
- [x] Add native list selection and grid modifiers, multi-book inspector, checked-field sheet.
- [x] Gate single-book commands and hidden selections; test filtered selections and rollback.

## 3. Search and saved filters
- [x] Add failing search and saved-filter roundtrip tests.
- [x] Implement shared LibraryQuery and SQLite saved filters; persist per library.
- [x] Add filter controls, save/apply/delete UI and sidebar saved views.
- [x] Update README and run full tests, release build, signatures, diff checks.
- [x] Run packaged UI on a disposable library; inspect changes and fix issues found.

## Verification outcome

- `swift test`: 165 tests executed, 8 external/hardware skips, zero failures.
- `bash scripts/build-app.sh`: release app and helper built successfully.
- Strict codesign checks passed for app and helper; `git diff --check` passed.
- Packaged app checked under a separate QA bundle identifier with authored temporary EPUBs:
  organization save/reopen, native Shift-selection + Command-I, bulk publisher/tag update,
  multiword search, exact tag filter, saved view creation/application/relaunch, empty results,
  inline invalid-number feedback, and compact window layout.
- Readback confirmed both temporary originals still matched their stored SHA-256 hashes.
- Independent review found a list-to-grid range-anchor issue; a failing regression test
  reproduced it and the final suite includes the fix.
- No hardware writes performed.
