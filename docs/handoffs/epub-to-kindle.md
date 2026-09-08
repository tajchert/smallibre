# EPUB → Kindle conversion

**Goal:** select a DRM-free reflowable EPUB, choose Send to Kindle, and receive a readable standalone AZW3 with book details, reading order, navigation, images and supported typography preserved. Also provide local AZW3 export without a device.

**Approach:** custom Swift KF8/AZW3 writer, following the accepted native-engine direction. Do not bundle Calibre, Python, KindleGen, a cloud converter, or disguise EPUB by changing its extension. Legacy MOBI output, hybrid MOBI/KF8, KFX, reverse conversion, fixed-layout publishing and DRM handling are separate projects.

Read [shared contracts](README.md) and [native decision](../architecture/native-swift-decision.md). Current `EPUBBook` supplies metadata and spine paths, not a complete conversion document. `MOBIMetadataEditor` rewrites existing metadata; it is not an encoder. A valid MOBI header alone does not prove Kindle readability.

The initial artifact/provenance contract is implemented; see [contract v1](artifact-transport-contract.md). A narrow native C1 prototype produces an authored standalone KF8 book; see [format evidence](../architecture/azw3-format-evidence.md). Hardware testing on Paperwhite 11th generation, firmware 5.19.2 found and isolated two compatibility defects: fragment selectors affected layout, and missing EXTH 113 UUID affected Library navigation. The selector correction and UUID-bearing native probes worked on hardware. Both corrections are now in the writer; the exact final generated artifact awaits a final hardware check. The bounded conversion workflow is now enabled in current source; see [implemented workflow and limits](../architecture/epub-kindle-workflow.md). The milestones below retain broader acceptance criteria that are not all satisfied by this increment.

## Proposed code boundaries

Create focused files under `Sources/SmallibreCore/Conversion/`: `PreparedBookArtifact.swift`, `EPUBConversionDocument.swift`, `EPUBConversionNormalizer.swift`, `AZW3Writer.swift`, `AZW3Validator.swift`, `ConversionService.swift`. Split record serialization/indexing into additional files when needed. Add `Tests/SmallibreCoreTests/ConversionTests.swift` and authored fixtures.

Integrate snapshot preparation with `LibraryStore.swift` / `EPUBEditor.swift`; provenance with `Database.swift`; transport consumption with `ReaderBackup.swift`; export/send states with `TransferView.swift` and `ReaderModel.swift`. Extend these selectively; do not move all device logic into the converter. Run expensive conversion outside the main actor and avoid holding the library actor for the entire operation. A separate Swift conversion helper is an option if memory/time isolation requires it; measure and document before adding one.

## Tasks

### C1 — Prove a minimal native AZW3 on hardware

- [x] Build an isolated writer prototype for an authored two-chapter EPUB with Unicode text, one image, one cross-chapter link and a navigation entry.
- [x] Document the required Palm database records, MOBI/KF8 headers, EXTH metadata, text encoding/compression, resource references, skeleton/fragment indexes and navigation records. Resolve offsets from serialized UTF-8 bytes, not Swift character counts.
- [x] Specify the initially supported compression and validate it on target hardware. Do not expand to multiple compression schemes without evidence they are needed.
- [ ] Independently inspect/decode output using a development-only reference tool and open/read it on a real AZW3-capable Kindle. Record model/firmware and results.

**Hardware status (2026-09-08):** native content/navigation and font scaling were confirmed after correcting fragment selectors. Probe A (fresh PDOC without UUID) still lacked the Library arrow; probes B (PDOC with UUID) and C (EBOK with UUID) both worked. The writer now preserves PDOC and emits a stable input-specific EXTH 113 UUID. Independent decoding and local regressions pass; the final deterministic-UUID artifact is retained for a last hardware retest. Exact model: Kindle Paperwhite (11th generation), firmware 5.19.2.

**Exit:** correct text order, image, navigation and link work on hardware. If this fails, report the unsupported format detail before building UI around the prototype. This is the highest-risk milestone.

### C2 — Parse a bounded conversion document

- [ ] Add fixtures for EPUB 2 NCX and EPUB 3 navigation, nested paths, percent-encoded names, Unicode, duplicate/missing anchors, cover selection and missing resources.
- [ ] Build a normalized internal model of metadata, ordered content, resources, navigation tree and resolved links. Keep source locations for useful errors. Reuse bounded ZIP/XML primitives.
- [ ] Define a feature matrix: preserve supported content, emit warnings for cosmetic degradation, reject unsupported structural/content loss. Reject fixed-layout, scripted/media-overlay content and unsupported encryption. Treat font obfuscation separately from DRM; never emit obfuscated font bytes as usable fonts.

**Exit:** deterministic model and typed diagnostics; malformed paths and resource bombs rejected before encoding. No silent lost chapters or broken internal links.

### C3 — Normalize supported content and typography

- [x] Snapshot current library metadata and `TypographySettings` into a prepared EPUB before conversion. Do not reuse the preview sanitizer as a lossless conversion engine.
- [ ] Support headings, paragraphs, emphasis, lists, basic tables, page breaks, raster images and internal/footnote links. Normalize CSS with a documented supported subset; preserve generic font choice, line spacing and margins where supported.
- [ ] Bound image dimensions, decoded pixel memory, CSS recursion/imports and output size. Never fetch remote resources. Define explicit rejection/warning behavior for SVG, MathML, remote images and unsupported CSS; no silent removal of meaningful content.
- [ ] Add assertions for semantic preservation and navigation destinations, plus visual checks on sample pages.

**Exit:** ordinary prose fixtures retain text, order, links and images. Cosmetic warnings can be reviewed before send; unsupported content produces actionable failure.

### C4 — Implement production serialization and validation

- [ ] Replace prototype shortcuts with checked record offsets, length arithmetic, resource ordering and deterministic identifiers. Include title/authors/language/publisher, cover resource, navigation and start-reading position where supported.
- [ ] Test multibyte text across record boundaries, large metadata, many chapters, empty content, repeated images and invalid offsets. Preserve Unicode without truncation.
- [ ] Independently validate record ranges, resource references, indexes and navigation targets. Reopening with `BookInspector` is a useful check but insufficient alone because it primarily reads metadata.
- [ ] Compare a rights-cleared corpus against an independent decoder and inspect actual Kindle rendering. Keep external reference tools out of app/runtime dependencies.

**Exit:** all declared supported fixtures validate and render; invalid or truncated output never becomes a completed artifact.

### C5 — Artifacts, provenance and cancellation

- [x] Implement the shared artifact contract. Cache key includes prepared input bytes/settings, output profile and converter version; prevent stale reuse after edits.
- [ ] Write to a private staging file, validate, hash, then publish atomically to local artifact storage. Bound concurrent conversions, memory and disk consumption. Check cancellation between stages and within long loops.
- [ ] Persist source-to-output provenance and migrate the database additively. Preserve originals and old reader receipts. Test restart, failed disk writes, stale cache, cancellation and editing while conversion is running.

**Exit:** conversion failure leaves no advertised output; retry can reuse a verified artifact, and derived-edition device matches use its actual output SHA-256.

### C6 — Local export and reader integration

- [x] Add local AZW3 export and an explicit conversion step in Send to Kindle. Show preparation/conversion/verification/transfer progress and readable errors.
- [x] Transfer only the captured artifact; back up those exact bytes, verify readback and record output hash and source provenance. Preserve no-overwrite behavior.
- [ ] Test without MTP using a temporary mounted folder. Then certify physical Kindle opening, cover within the book, chapter navigation, footnotes, Unicode and reader font adjustment. Library thumbnail display is firmware-dependent and must be reported separately.
- [ ] Update README support matrix and publish compatibility/size/timing evidence. A proposed performance benchmark is a 5 MB prose EPUB and a 50 MB image-heavy EPUB on an identified Mac; set release thresholds from C1 measurements rather than promising arbitrary speeds.

**Definition of done:** all C1–C6 gates pass; users can export and send supported EPUBs as AZW3; unsupported books fail clearly; no original changes; no mandatory network or runtime added. MTP is not a dependency for this milestone.

## Research starting points

The ignored local `calibre/src/calibre/ebooks/mobi/writer8/` and `reader/mobi8.py` provide useful format evidence. Online primary source: [Calibre KF8 writer](https://github.com/kovidgoyal/calibre/tree/master/src/calibre/ebooks/mobi/writer8), [KF8 reader](https://github.com/kovidgoyal/calibre/blob/master/src/calibre/ebooks/mobi/reader/mobi8.py). Pin any research revisions in implementation notes. References explain behavior; copying implementation requires revisiting the project's current custom-code/provenance claims.
