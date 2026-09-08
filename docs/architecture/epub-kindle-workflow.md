# Native EPUB to Kindle workflow

Version 0.3.0 supports EPUB preparation, conversion-note review, local AZW3 export and verified transfer to a mounted reader. MTP is not part of this workflow.

## User flow

Import an EPUB and save any metadata or typography changes. Choose **Send to device**. Smallibre checks the selected mounted reader, or `/Volumes/Kindle/documents` when none is selected, converts an EPUB automatically, and sends it. If that read-only check fails, a manual folder and reader-type sheet opens. Renamed volumes and MTP readers are not automatically discovered. Send creates a new AZW3; it never overwrites an existing device book. **Export Kindle AZW3…** offers the same preparation for local export. Original-format EPUB export remains available.

Conversion notes remain available in **Backups & history** after sending. The automatic operation pins the checked folder identity through conversion and transfer; cancellation, conversion failure, or a write error never triggers an automatic retry. Conversion errors appear before a device write. Unsupported books remain in the library unchanged. The prepared artifact captures saved settings; subsequent edits require another preparation. Device/library views identify a converted copy using its verified output hash and source provenance, separately from an identical original. A successfully transferred file is byte-verified, but rendering still needs checking on the Kindle. After ejecting, check Library navigation, font scaling, chapter links and images.

For the detailed gap list and proposed priorities, see [known limitations and missing features](../epub-kindle-limitations.md).

## Supported profile and limits

- Unencrypted reflowable EPUB 2 (NCX) or EPUB 3 navigation, in spine reading order.
- Headings, prose, emphasis, lists, common semantic blocks, basic raster images and links to spine content. PNG/JPEG covers are retained as KF8 cover resources.
- Basic UTF-8 linked stylesheets and inline CSS; saved EPUB typography is applied before conversion. CSS may render differently on Kindle. Nested tables of contents are flattened and disclosed in conversion notes.
- At most 16 MB input archive, 512 unique spine chapters/navigation entries, 1 MB serialized content per chapter and 1 MB styles per chapter, with a 24 MB aggregate text/styles budget and a 32 MB final output limit. Images: at most 16 MB combined and 4 MB each, 8192 pixels per dimension and 16 million pixels. KF8 index records remain bounded to 65535 bytes and string tables below 60000 bytes; exceeding limits produces an error.
- Version 0.3.0 omits declared custom fonts with a review warning, accepting only explicitly validated IDPF/Adobe font-only obfuscation. Custom CSS font families fall back to generic fonts; bold/italic declarations remain. Font definitions and simple publisher page margins are discarded with warnings. Font fallback was introduced in version 0.3.0.
- Reject DRM/encrypted content, fixed layout, scripts, media overlays, SVG/MathML, unsupported elements/attributes, remote images and external content links. CSS URLs outside discarded font definitions, imports, other at-rules, font shorthand, escapes and executable extensions are rejected. No remote content is fetched.

These bounds deliberately exclude some ordinary commercial EPUBs. Unsupported content produces an error rather than a partial book. This is not Calibre-equivalent conversion or a general AZW3 validator.

## Storage and provenance

`LibraryStore.prepareKindleArtifact(for:)` captures original SHA-256, prepared EPUB SHA-256, canonical metadata/typography SHA-256, converter version and profile. The cache identifier derives from this provenance. Conversion runs on a serial worker away from the main actor; cancellation is checked through preparation and encoding.

Output and its manifest are staged, validated, synchronized and published together under `converted/<artifact UUID>/book.azw3` and `artifact.json`. Reuse verifies manifest provenance, local storage paths and byte hashes. Metadata changes generate a new artifact; original and prior conversion bytes remain untouched. Corrupt cached output is never silently regenerated. Artifacts currently remain retained; automatic garbage collection and a storage-management UI are future work. Back up the whole library folder to include conversions and receipts.

## Transfer safety

`sendArtifact` runs in `SmallibreReaderHelper`. It checks the stored manifest and native structure, retains a verified local copy, and uses `ReaderArtifactTransfer` with `MountedReaderTransport`. The adapter uses root identity checks and descriptor-relative exclusive file creation. Existing regular files and symlinks are collisions, never overwrite targets. Readback is bounded and hash-checked against the captured artifact.

Receipts progress through intent, uploaded and verified; failures after intent become needsReview when persistence succeeds. A timeout can leave the last durable state at intent/uploaded. A created device file is never automatically deleted or replayed after an uncertain result. Review Backups & history and refresh the reader before retrying. Canceling or sleeping does not prove that no write occurred.

## Validation evidence

Regression tests cover long multibyte chapters, EPUB 2 navigation and covers, ordinary linked CSS, 300 chapters (including navigation index ordering above 256 entries), malformed output, cache reuse/restart, changed settings, corruption, symlink storage, cancellation, helper transfer, root replacement, filename collisions and exact readback receipts. `KindleWorkflowHardwareTests` is an opt-in authored-copy test that preserves every existing device book and retains its test book for manual reading.

Earlier prototype hardware evidence is in [AZW3 format evidence](azw3-format-evidence.md). Expanded-profile rendering, broader book corpus coverage, independent-device certification and performance thresholds remain open; automated file validation does not close those gates.

### Mounted workflow run — 2026-09-08

`KindleWorkflowHardwareTests` passed through the production helper on the connected Paperwhite. An authored Small Hours EPUB was imported, renamed, personalized (serif, 1.8 line height, 5% margins), converted and sent as **Smallibre EPUB workflow 4E394FC6.azw3**. The 4091-byte output SHA-256 is `f77cd771758d7183ca22cb98a2bf08f48af9c474babec1ae5d8b441d6a65ad71`. Full before/after scans confirmed every existing book hash unchanged, one new file, matching artifact/readback hashes and a verified provenance receipt. No existing device file was deleted or edited.

Development-only Calibre 9.14 independently decoded this output to EPUB; all source chapter headings and paragraphs were retained, and the decoded CSS retained serif/1.8 typography. Calibre is not a build or runtime dependency. The user subsequently confirmed that this exact test book works well on the Kindle. This confirms the sample workflow; it does not certify all supported EPUB features or other devices.

Final integration checks: 115 tests, seven expected opt-in skips, zero failures; release bundle built and strict ad-hoc signature verification passed (approximately 6.6 MB). The isolated app’s local Export Kindle AZW3 flow completed and exported bytes with the same SHA-256 as the reviewed artifact and mounted-device readback.

### Font fallback increment — 0.3.0

Converter version 2 accepts recognized IDPF/Adobe font-only obfuscation when every declaration references an unambiguous, declared font resource. Fonts are omitted rather than decrypted or embedded. CSS font definitions and simple page-margin rules are removed with review warnings; custom families fall back to generic reader fonts. Unknown encryption, encrypted content, conflicting manifest paths and extra encryption structures remain rejected. Version 1 artifacts still validate, while new preparation uses the version 2 cache identity.

Conversion and typography editing preserve whitespace-only nodes between inline elements. Authored regressions cover spaces, line endings, external DOCTYPE declarations, UTF-16, entity rejection and expanded XML bounds. Internal DTD subsets are unsupported in these paths. Local external-file validation also compared every non-empty paragraph/heading and distinct JPEG against an independent decoder; no personal EPUB or extracted text is stored in the repository. On-device rendering of the expanded font-fallback profile remains a manual check.
