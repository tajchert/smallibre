# EPUB → Kindle: known limitations and missing features

Last reviewed: 2026-09-08. Scope: the native EPUB-to-AZW3 converter and its export/send workflow in version 0.2.0. These limitations do not necessarily prevent importing or previewing the original EPUB.

The authored workflow test works on Kindle Paperwhite (11th generation), firmware 5.19.2, as confirmed by the user. That establishes the tested sample, not compatibility with every EPUB or Kindle. Unsupported conversion content normally produces an error before transfer; originals remain unchanged.

## Major compatibility gaps

| Feature | Current behavior | Missing capability |
| --- | --- | --- |
| Embedded fonts | Font resources are rejected, including obfuscated fonts. An otherwise simple book can fail because its manifest includes fonts. | Safe fallback to reader fonts with a warning; optionally support permitted embedded fonts. |
| SVG graphics and covers | SVG resources and inline SVG are unsupported. | Safe rasterization or a supported image fallback, including SVG cover wrappers. |
| Tables | Table markup is not in the supported element set. | Basic tables, headers, captions, row/column spans and small-screen handling. |
| Broader HTML support | Unsupported elements and attributes cause rejection. Examples include definition lists, ruby annotations and ordered-list `start`/`type` attributes. | Preserve additional common markup and distinguish harmless unsupported attributes from meaningful content loss. |
| CSS | Basic inline and linked UTF-8 stylesheets work, but all at-rules, resource URLs and escapes are rejected. This includes `@media`, `@font-face`, `@import`, `@page` and background images. | A more complete CSS parser with explicit preservation, fallback and warning rules. |
| CSS matching and rendering | CSS is largely carried through; equivalent Kindle rendering is not guaranteed. The conservative token filter can reject harmless text or selectors, including selectors containing `>`. | Broader CSS compatibility fixtures and on-device layout checks. |
| External hyperlinks | Links to websites and other external destinations are rejected. | Preserve safe external links without fetching remote content during conversion. |
| Footnotes outside the spine | Internal links work only when their targets are in spine chapters. A separate notes document outside the spine is unsupported. | Include referenced local notes and preserve their navigation. Kindle popup-footnote behavior is not certified. |
| Hierarchical navigation | Nested tables of contents are flattened, with a conversion note. | Preserve parent/child navigation hierarchy. |
| Additional image types | Only PNG/JPEG resources are accepted. GIF, WebP and other image formats are unsupported. | Bounded conversion to supported raster formats. |

The resource allowlist applies to manifest entries, not only visibly used content. An unused unsupported resource can therefore block conversion.

## Structural restrictions

- EPUB 3 navigation or EPUB 2 NCX referenced by the spine is required; there is no synthesized table-of-contents fallback.
- Chapters must be unique in the spine; repeated spine entries are rejected.
- Navigation must follow reading order.
- Chapters must have the supported XHTML structure. Arbitrary malformed HTML is not repaired.
- Missing resources, duplicate anchors and unresolved link targets are rejected.
- Ambiguous or unsupported cover declarations are rejected. Kindle Library thumbnail display is not guaranteed by retaining the cover resource.

## Size and encoding limits

These are converter-specific bounds; successful library import does not guarantee successful conversion. MB below means 1024 × 1024 bytes.

| Item | Limit |
| --- | --- |
| Input EPUB archive | 16 MB |
| Unique spine chapters | 512 |
| Navigation entries | 512 |
| Serialized chapter content | 1 MB per chapter; generated markup counts toward this limit |
| Styles | 1 MB per chapter |
| Combined normalized text and styles | 24 MB |
| Individual image | 4 MB |
| Combined image bytes | 16 MB |
| Image dimensions | 8192 pixels per dimension and 16 million pixels |
| Final AZW3 | 32 MB |
| KF8 index record | 65,535 bytes |
| KF8 index string table | Less than 60,000 bytes |
| Individual emitted metadata field | 16 KB |

Index size can be exceeded before the chapter/navigation count limit, for example with long navigation labels. Multi-record index rollover and larger-book profiles are not implemented. Existing ZIP/XML safety bounds also apply; ZIP64 is unsupported.

## Deliberately outside the current scope

- DRM removal or decryption; EPUB encryption declarations, including font obfuscation, are currently rejected.
- Fixed-layout books, scripted/interactively rendered books and media overlays.
- Audio/video content and MathML.
- KFX output, legacy MOBI output, hybrid MOBI/KF8 output and reverse AZW3/MOBI-to-EPUB conversion.
- Fetching remote book resources or running book scripts.

These are scope exclusions, not commitments to implement them.

## Workflow and validation gaps

- **MTP transfers:** not implemented. The app workflow requires a reader mounted as a drive/folder; the read-only MTP diagnostic is separate.
- **Artifact storage management:** converted artifacts and transfer backups are retained. Automatic cleanup, a storage-management UI and a guided corrupt-cache recovery flow are missing.
- **Interrupted transfers:** no automatic retry or resume. An uncertain write can leave a device file that needs explicit review; cancellation is not proof that no write occurred. This is intentional safety behavior.
- **Compatibility coverage:** broader rights-cleared book corpus testing, other Kindle models/firmware and comprehensive rendering checks remain open.
- **Performance:** larger-book memory/time benchmarks and release thresholds are not established.
- **Validation scope:** the structural validator checks the native output profile. It is not a general third-party AZW3 validator or a substitute for hardware rendering checks.
- **Release packaging:** version 0.2.0 targets Apple Silicon and macOS 14+. It is ad-hoc signed, not Developer ID signed or notarized; a universal build is not provided.

## Suggested implementation priorities

These are proposed priorities, not scheduled work.

- [ ] Font fallback for ordinary reflowable books, with explicit conversion warnings.
- [ ] SVG cover/image fallback without loading remote resources.
- [ ] Basic tables and common HTML attributes.
- [ ] More tolerant, structured CSS handling with documented degradation rules.
- [ ] Safe external links and referenced notes outside the spine.
- [ ] Hierarchical navigation and navigation fallback.
- [ ] Broader corpus/hardware testing before increasing size limits.
- [ ] Artifact storage and recovery controls that preserve uncertain-transfer evidence.

## Related documents and implementation

- [Implemented workflow, safety model and test evidence](architecture/epub-kindle-workflow.md)
- [Conversion developer handoff](handoffs/epub-to-kindle.md)
- [MTP developer handoff](handoffs/mtp-readers.md)
- [EPUB normalization and resource restrictions](../Sources/SmallibreCore/Conversion/AZW3PrototypeDocument.swift)
- [Native writer](../Sources/SmallibreCore/Conversion/AZW3PrototypeWriter.swift)
- [Structural validator](../Sources/SmallibreCore/Conversion/AZW3Validator.swift)
- [Artifact storage](../Sources/SmallibreCore/Conversion/KindleArtifactStorage.swift)
