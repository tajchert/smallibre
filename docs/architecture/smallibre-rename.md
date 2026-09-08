# Smallibre rename verification

The application, Swift package, app/core/helper/test targets, bundle and imported type identifiers, preview scheme, build scripts, CI artifact and documentation now use Smallibre. Legacy names remain only for library migration, replacing earlier typography markers, and historical hardware evidence.

The default library moves from `Application Support/Calibre Nova` to `Application Support/Smallibre`. A compatibility symlink preserves existing backup receipt paths. Migration can recover after an interrupted move; conflicting libraries are preserved rather than merged. Reader actions stay disabled until library initialization succeeds.

Verification on September 8, 2026: a clean Swift test run executed 45 tests, with 4 opt-in tests skipped and no failures. The existing two-book library migrated successfully; hashes of all four original/backup files checked were unchanged. The native app opened the library and rendered an EPUB using the new preview scheme. A second code review found no remaining material migration issues.

The physical checkout remains named `calibre-nova`: this active Codex workspace rejects a symlinked writable root. Its saved sidebar project label also remains unchanged. These host workspace names are independent of the renamed Swift package and app.
