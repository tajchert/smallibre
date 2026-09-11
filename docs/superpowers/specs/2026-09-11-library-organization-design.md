# Library organization, bulk editing and saved filters

Approved direction: implement organization, then bulk editing, then search/saved filters.

Keep organization on LibraryBook, separate from embedded BookMetadata: tags, series name,
optional nonnegative finite sequence number, read/unread. Older records decode with empty
organization and unread. Organization-only edits must not change export bytes or conversion
identity. Use the existing detail editor and inspector, plus series sorting and filters.

Bulk editing starts with explicit multi-selection. Preserve the cover grid and add a native
list for range selection and keyboard navigation. Grid selection supports Command/Shift too.
Only visible selected books are eligible. A sheet captures IDs and applies only checked fields:
authors, publisher, language, tags (add/remove/replace), series and number, read state.
Validate all changes, reread records, then save in one SQLite transaction. No device writes.

Search matches all whitespace-separated words across title/authors/publisher/description/
identifier/tags/series (case and diacritic insensitive). Combine with format/personalized,
read state, tag and series filters. Named saved filters persist in the library database, can
be applied and deleted, and do not freeze a list of books. Empty-result saved filters remain
usable. Existing device search remains unchanged. No full-text indexing or remote lookup.

Use Swift/system frameworks, macOS 14+, existing actor boundaries and design tokens. Tests
cover legacy decode, persistence, original-byte preservation, invalid numbers, atomic rollback,
selection gating, search semantics and saved-filter persistence. Build/signature verification
and disposable-library packaged UI checks are required. Update README capability claims.
