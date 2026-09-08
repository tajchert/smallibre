# Pre-publication Git history audit

Audited September 8, 2026, through `e4a55df`, before the publication documentation changes. No history was rewritten and nothing was pushed.

## Scope and method

Enumerated all objects reachable from every local Git ref using `git rev-list --objects --all`: 14 commits, 104 trees and 146 unique blobs. This includes local Codex refs as well as the development branch. Inspected historical filenames, commit author/committer identities, text matches and binary inventory; scanned blob contents and decompressed ZIP/EPUB entries for private-key headers, common GitHub/AWS/OpenAI/Slack token formats, quoted credential assignments, email addresses and local user paths. Reviewed broader credential keywords to distinguish fixtures and license text from secrets.

This was a local scripted pattern audit, not a dedicated secret-scanner run: neither gitleaks nor trufflehog was installed. Pattern matching cannot prove the absence of arbitrary or encoded secrets. Unreachable objects, reflogs, ignored working files and external services are outside the published-history scope. Recheck any new commits before publication.

## Findings

- No matches for the scanned private-key, access-token or credential-assignment patterns. Keyword matches were test content, license prose or design discussion.
- All binary blobs are small authored/synthetic ebook fixtures, including older versions before the rename. No binary blob exceeds 100 KB. No personal ebook, library database, device backup, signing key or generated app was found in reachable tracked history.
- All 14 commits contain the owner's real author/committer name and Gmail address. Publishing the existing history will expose that identity. A privacy decision is needed before publishing; changing Git configuration alone does not change old commits.
- Two historical documentation blobs contain absolute paths with the owner's macOS account name and checkout location. Current versions use relative links, but older revisions still expose those paths.
- Verification documents disclose a local test book's filename, book/archive counts and device test details. They do not contain that book's bytes. These details remain in current documentation and history.
- No Git remote is configured. There are no tracked private dependency URLs. The local Calibre reference checkout and generated builds are ignored.

## Publication decision

There is no detected credential requiring rotation based on this audit. The outstanding issue is whether the owner accepts publishing the commit identity and historical personal/test details. If not, prepare an explicitly authorized history cleanup or clean initial public snapshot before pushing. Do not silently rewrite existing commits or assume removing a current file removes it from history.

The current source is GPL-3.0-only with a license file and authored fixtures. This inventory check is not a comprehensive legal provenance review.
