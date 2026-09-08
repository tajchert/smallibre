# Native AZW3 prototype format evidence

This describes a deliberately narrow C1 experiment, not delivered conversion support. The initial output profile is standalone, DRM-free KF8 (MOBI version 8), UTF-8, PalmDOC compression type 1 (uncompressed). EPUB parsing, arbitrary document conversion and Kindle hardware acceptance remain separate gates.

**Current result:** the user confirmed that both UUID-bearing native probes restore Home/Library navigation on Paperwhite 11th generation, firmware 5.19.2. The writer now includes a stable EXTH 113 UUID while retaining PDOC. Use `build/prototypes/Smallibre-native-identifier-fixed.azw3` for the final generated-output retest; earlier artifacts below are historical and may fail the expanded diagnostic.

## Sources and independence

Format behavior was researched from the ignored local Calibre checkout at revision `025d9cf3a1ef5ce6c9576a29a0963d2175b02d4c`. Relevant primary implementation sources are the [KF8 reader](https://github.com/kovidgoyal/calibre/blob/025d9cf3a1ef5ce6c9576a29a0963d2175b02d4c/src/calibre/ebooks/mobi/reader/mobi8.py), [index reader](https://github.com/kovidgoyal/calibre/blob/025d9cf3a1ef5ce6c9576a29a0963d2175b02d4c/src/calibre/ebooks/mobi/reader/index.py), [header reader](https://github.com/kovidgoyal/calibre/blob/025d9cf3a1ef5ce6c9576a29a0963d2175b02d4c/src/calibre/ebooks/mobi/reader/headers.py), and [index writer](https://github.com/kovidgoyal/calibre/blob/025d9cf3a1ef5ce6c9576a29a0963d2175b02d4c/src/calibre/ebooks/mobi/writer8/index.py). These are interoperability evidence, not an Amazon normative specification or certification.

The Swift serializer and [diagnostic script](../../scripts/inspect-azw3-prototype.py) are independently authored. The diagnostic uses Python's standard library only, does not import the Swift implementation or Calibre, and is a development tool. Calibre is not bundled, linked or required by Smallibre. A separate installed Calibre 9.14.0 decoder is available on a mounted distribution volume for an additional independent readback.

## Record structure

All integers here are big-endian. Offsets in the following header table are relative to record 0, including its 16-byte PalmDOC prefix.

| Field | Offset | Interpretation |
| --- | --- | --- |
| Compression | 0 | UInt16, 1 = uncompressed |
| Text bytes / record count | 4 / 8 | UInt32 / UInt16 |
| Encryption | 12 | UInt16, must be zero |
| MOBI signature / header length | 16 / 20 | `MOBI`, UInt32 |
| Text encoding / format version | 28 / 36 | 65001 / 8 |
| Title offset / byte length | 84 / 88 | Relative to record 0 |
| Minimum reader version | 104 | 8 |
| First resource record | 108 | PalmDB record index |
| EXTH flags | 128 | Bit 0x40 announces EXTH |
| FDST record / flow count | 192 / 196 | Main text is first flow |
| FCIS record / count | 200 / 204 | Auxiliary text information; count 1 |
| FLIS record / count | 208 / 212 | Auxiliary fixed-profile information; count 1 |
| Extra text data flags | 242 | UInt16; zero in prototype |
| Navigation / fragment / skeleton indexes | 244 / 248 / 252 | PalmDB record indexes |

PalmDB identifies `BOOKMOBI` at file offset 60; its UInt16 record count at 76 precedes 8-byte directory entries beginning at 78. Each entry begins with an absolute file byte offset. Strict increasing offsets delimit nonempty records. EXTH follows the declared MOBI header and contains length-delimited typed metadata entries. Text records concatenate into one byte stream; neither character counts nor Swift grapheme counts determine positions. Uncompressed text does not need to end at UTF-8 scalar boundaries between records, but every resolved content position must.

An `FDST` record has signature, header length (12), flow count and pairs of UInt32 start/end byte positions. The prototype explicitly emits its main flow. Calibre ignores the FDST pointer when the header announces only one flow, treating all text as main flow.

The prototype includes auxiliary `FCIS` and `FLIS` records. The pinned [MOBI serializer](https://github.com/kovidgoyal/calibre/blob/025d9cf3a1ef5ce6c9576a29a0963d2175b02d4c/src/calibre/ebooks/mobi/writer8/mobi.py) provides reference field values: after `FCIS`, twelve UInt32 values are `(20, 16, 2, 0, textBytes, 0, 40, 0, 40, 8, 65537, 0)`; after `FLIS`, eight are `(8, 4259840, 0, 4294967295, 65539, 3, 1, 4294967295)`. Their semantics are incompletely documented; the bounded profile preserves these reference values and the diagnostic checks pointers, counts, sizes, signatures and each field. Decoder acceptance alone does not validate these auxiliary records.

Each index group has a 192-byte `INDX` header, `TAGX` definitions, one or more entry records and optional CNCX string records. Entry records use an `IDXT` table of UInt16 entry offsets. An entry has a byte-length-prefixed identifier, control byte and variable-width integers (7 payload bits per byte, high bit set on the final byte). TAGX describes tag number, values per entry, control mask and end-of-control-byte marker. CNCX strings are variable-integer byte length plus UTF-8 data; references count from each record's start, with a 65536-byte namespace stride between records.

| Index | Tags required by the prototype |
| --- | --- |
| Skeleton | 1: fragment count (duplicated); 6: skeleton start and length (pair duplicated) |
| Fragment | 2: CNCX selector offset; 3: file ordinal; 4: global fragment sequence; 6: relative start and length |
| Navigation | 1: position; 2: length; 3: CNCX label; 4: depth; 6: fragment ordinal and byte offset |

For one fragment per chapter, raw text contains the skeleton followed immediately by its fragment. The fragment entry's decimal identifier is its insertion position in the reconstructed chapter's absolute position space. Reconstruction takes the skeleton at its indexed start/length, takes the following fragment bytes, and inserts them at `identifier − skeleton start`. This makes opening/closing HTML outside the body separable from body content without losing positions. Multiple-fragment semantics and production-scale indexes are not claimed by the prototype.

`kindle:pos:fid:…:off:…` uses base-32 numbers (digits 0–9 and A–V). `fid` selects a fragment index entry; `off` counts bytes from that fragment's insertion position. A cross-chapter target following multibyte characters must still land at the intended tag boundary. Navigation uses the same pair as integer index values. Image `kindle:embed:0001?mime=image/png` selects first resource plus one-based decoded reference minus one. A valid metadata header alone does not establish these relationships.

## Development verification

Run the independent bounded reader after generating the native fixture:

```sh
python3 scripts/inspect-azw3-prototype.py /tmp/smallibre-native-prototype-v2.azw3 --extract /tmp/smallibre-native-inspection-v2
```

It checks PalmDB ranges, standalone/uncompressed/unencrypted UTF-8 headers, EXTH bounds, FCIS/FLIS fields, FDST coverage, index tables and string references, reconstructs chapters, checks link destinations at UTF-8/tag boundaries, and checks referenced image signatures. It rejects unsupported profiles; it is not a full hostile-input production AZW3 validator.

The installed independent decoder can run with disposable configuration and output:

```sh
CALIBRE_CONFIG_DIRECTORY=/tmp/smallibre-calibre-reference-config \
  /Volumes/calibre-9.14.0/calibre.app/Contents/MacOS/ebook-convert \
  /tmp/smallibre-native-prototype-v2.azw3 /tmp/smallibre-native-reference-v2.epub
```

Neither a successful diagnostic nor a successful reference conversion proves that a physical Kindle renders the book. C1 remains incomplete until an identified AZW3-capable Kindle's model and firmware, compression support, text order, Unicode, image, chapter navigation and cross-chapter link are recorded from actual reading. Physical transfer verification is recorded below; it does not establish reading compatibility.

### Initial diagnostic result — 2026-09-08 (superseded)

The 3,557-byte native output had SHA-256 `940e0793ebdcadfc33ef40ef16f5d0ca6490236eb7f2890882514f32e247366b`. The independent diagnostic passed: 15 records, 1,107 text bytes, one flow and two reconstructed chapters. The outgoing link resolves to chapter two at UTF-8 byte 218 (`note`); the return resolves to chapter one at byte 101 (`evening`). Navigation labels `One — Evening` and `Two — Morning` resolve to byte 101 in their respective chapters. Image record 10 contains the authored PNG.

Installed Calibre **9.14.0** independently recognized the output as standalone KF8 and converted it to EPUB with exit status 0. Parsing that EPUB verified the exact `Zażółć gęślą jaźń — café 日本語 🌙.` text, emphasis and strong text, the two chapters in spine order, both chapter navigation destinations, and reciprocal links `part0001.html#note` / `part0000.html#evening` with the destination anchors present. The extracted PNG was byte-identical to native image record 10: 16 × 16 source pixels, displayed at 96 × 96 by the source markup, SHA-256 `f09adb2f3531ae2cd204082015e49330047a3fc6bb0e4cca82f45e359473d622`. Calibre generated a default cover for its EPUB output; that cover is not evidence that the native fixture has cover metadata.

Diagnostic mutation checks rejected a truncated PalmDB directory, overlapping record offsets, an absent fragment index, an invalid image reference and an invalid link fragment. These checks supplement the native tests; they do not certify arbitrary book handling. Physical Kindle opening and reading remain unverified. A user-reported Paperwhite firmware estimate must be confirmed on the device before recording compatibility evidence.

The initial artifact above had incorrect FCIS fixed words at record offsets 40 and 44. Calibre decoded its content despite these fields, and the original diagnostic did not check them. Subsequent independent reference review identified the discrepancy; the diagnostic now rejects the original artifact. This is evidence that successful content extraction alone is insufficient. The corrected artifact is recorded below.

### Corrected native fixture result — 2026-09-08

The corrected 3,557-byte artifact `/tmp/smallibre-native-prototype-v2.azw3` has SHA-256 `32170b8db3e2c3c161c597579abecc7ea037293a95e7d30a38482e8219dc298c`. It passes the expanded diagnostic, including FCIS record 13 and FLIS record 12 with their reference fixed fields. Text, links, image and navigation results remain as described above. The original artifact is superseded and must not be used for hardware acceptance.

Calibre 9.14.0 independently decoded this corrected artifact to `/tmp/smallibre-native-reference-v2.epub` with exit status 0. Repeated semantic assertions passed for exact Unicode text, emphasis/strong, both cross-chapter links and destination anchors, spine order, both navigation destinations and byte-identical PNG. Additional mutations of FCIS and FLIS fixed fields and the FCIS pointer were rejected by the expanded diagnostic. This remains a development proof; physical Kindle acceptance is pending.


## Prototype boundaries and local build checks

The input is an authored EPUB, not raw hand-written KF8 text. `AZW3PrototypeDocument` uses existing bounded ZIP/XML inspection and implements a deliberately narrow C1 profile: EPUB 3 flat navigation, unique spine chapters, ordinary prose tags, PNG/JPEG resources and internal links. It rejects CSS/styles, fonts, encryption, scripts, SVG and other unsupported content. Limits include 16 MB EPUB input, 64 chapters, one 8 KB fragment per chapter, 4 MB per image with bounded dimensions, single-record indexes and 32 MB output. It is not suitable for arbitrary user books and is not connected to the export/send UI. C2/C3 production normalization, C4 full validation and C5/C6 persistence/integration remain open.

Reproduce the native fixture in a new local path (existing destinations are not overwritten):

```sh
SMALLIBRE_AZW3_PROTOTYPE_OUTPUT=/tmp/smallibre-proof-new.azw3 \
  swift test --filter AZW3PrototypeTests/testWriteOptInPrototypeForIndependentDecoder
```

The tested corrected file is also retained at `build/prototypes/Smallibre-native-proof.azw3` (ignored build output). A device copy was subsequently written in the mounted-reader verification below. Physical reading validation must cover opening, chapter order, Unicode, checker image, chapter menu and both cross-chapter links on the identified Paperwhite. The user confirmed Kindle Paperwhite (11th generation), firmware 5.19.2, superseding the earlier firmware estimate. The tested connection is mounted USB storage (FAT32).

Local checks on macOS 26.6.2/arm64, Apple Swift 6.3.3: `swift test` executed 75 tests, with 70 passed and five skipped (four existing external/hardware opt-ins plus prototype-file retention); all seven AZW3 tests passed separately with file retention enabled. Release packaging and strict ad-hoc signature verification passed. The release bundle is 5,901,172 logical bytes, +197,504 bytes over the shared-contract build. No external runtime was added. Full converter/MTP throughput, peak runtime memory and physical cancellation measurements remain pending; small fixture test durations are not performance claims.

### Mounted Paperwhite verification — 2026-09-08

Reviewed recent conversion/MTP foundations, keyboard/search commands, and reader wakeup/sleep changes (`9ab3266`, `4c67b6f`, `5c142fd`). The connected user-identified Paperwhite exposed writable USB/FAT32 storage. The bounded MTP probe saw one interface and no standard MTP candidate; this run provides no MTP hardware certification.

`NativeKindleHardwareTests` passed against the physical reader using only the production helper for device operations. It converted the authored EPUB to the corrected SHA-256 above, transferred and read back identical bytes, verified download deduplication, rejected a stale selection with a changed connection UUID, and sent a second copy without overwriting the first. Metadata replacement on the second copy preserved all subsequent Palm records and backed up original bytes. Deletion of that second copy completed only after verified backup. Six operation receipts completed. All 62 existing main-book hashes remained unchanged; the final inventory contained 63 books. This hash comparison does not constitute a recursive audit of annotations or sidecars. The stale-connection check was simulated, not a physical unplug or sleep test.

One uniquely named authored AZW3 remains on the reader, with internal title **Smallibre native Kindle proof**, for physical reading. The volume was safely ejected afterward. Receipts, backups and the local result JSON are retained under ignored `build/reader-validation-*`; no device inventory or personal ebook is committed. After safe eject, the user confirmed: “Smallibre native Kindle proof works.” Basic native AZW3 opening/reading is therefore confirmed on this Paperwhite. The reply is an overall success report, not separate observations for Unicode, image, chapter menu and reciprocal links. The user subsequently identified the device as Kindle Paperwhite (11th generation), running firmware 5.19.2; this supersedes the earlier 5.19.6 estimate. This initial opening report is superseded by the rendering/navigation failures recorded below. C1 hardware acceptance has not passed.

The final default suite executed 85 tests: 79 passed, six explicit opt-ins skipped, zero failures. The separate native hardware opt-in executed one test with zero failures. Release packaging, strict ad-hoc signature verification and whitespace checks passed. UI automation selected a different library window than the requested disposable instance, so it was left untouched; manual shortcut/sheet behavior is not certified by this run. Automated reader sleep/lifecycle and keyboard command regressions passed in the full suite.

### Hardware failures and fragment-selector correction — 2026-09-08

On Paperwhite (11th generation), firmware 5.19.2, the user subsequently confirmed the content/navigation checklist but reported three failures: the Library return button is missing and exiting requires a reset; enlarging fonts clips the bottom of the first page; large black rectangles sometimes appear near the tops of pages and disappear after paging back and forth. The user confirmed these symptoms occur only in this book. Opening and extraction success do not establish reliable reading. C1 remains blocked on a symptom-specific hardware retest.

Comparing the authored EPUB's native output with a development-only Calibre 9.14.0 AZW3 exposed a definite structural discrepancy: the native fragment CNCX selectors were `0-//*[@aid='B0']` and `1-//*[@aid='B1']`. The prefix is not the chapter ordinal. The reference serializer uses `P-` when inserting content into its parent, switching to `S-` for sibling content (see [reference Chunker implementation](https://github.com/kovidgoyal/calibre/blob/master/src/calibre/ebooks/mobi/writer8/skeleton.py), `step_into_tag` and `Chunk`). Our one-fragment-per-body profile needs `P-` for both chapters. Its separate file-ordinal index field was already correct. The prior diagnostic checked selector presence but ignored its semantics, explaining why that diagnostic missed the error. An independent decoder can also reconstruct content using numeric insertion positions without detecting this discrepancy.

The writer now emits parent selectors. A new Swift regression failed on the old output and passes on the corrected output. The diagnostic now requires the parent-selector form, resolves it to the skeleton body and checks that insertion follows the body's opening tag. It rejects both the original numeric prefix and a mutated selector referencing a missing parent. No CSS or fixed page-height styling exists in the prototype markup. Other reference differences, including generated anchor identifiers and text trailers, have not been established as causes and were deliberately left unchanged in this candidate.

The candidate `build/prototypes/Smallibre-selector-fix.azw3` is 3,557 bytes, SHA-256 `ff4e1324a53911b1f5a7c52b0775b51e78339452741ea9b9393860c37e7e89e7`. Relative to the hardware-tested `32170b…` file, exactly two bytes change: file offsets 2312 and 2329 become ASCII `P`. Title, identifiers, text, image, navigation offsets and all other bytes remain identical. The original artifact is preserved for comparison. Calibre independently decoded the candidate successfully; the expanded diagnostic verified both chapter destinations, reciprocal links and image reference. This isolates a format correction, not a proven explanation for all three device symptoms. A repeated hardware test must also account for existing Kindle layout cache because the candidate retains the original identifiers. After the user rebooted the Kindle and requested transfer, the candidate was sent through the production helper to a new, collision-safe `Smallibre Selector Fix … .azw3` path. Full scan and helper readback verified the exact candidate SHA-256 and bytes; all pre-existing main-book hashes remained unchanged. The original test copy was retained. After successful readback, the eject attempt reported that the volume was no longer present; safe ejection by this run is not confirmed. Physical symptom retesting remains pending.

Validation after the fix: eight focused AZW3 tests passed with authored-file retention enabled; the full suite ran 86 tests with 80 passed, six opt-ins skipped and zero failures. Release packaging and strict ad-hoc signature verification passed. Retest must explicitly cover Library exit without reset, font enlargement/reflow at the previously failing size, and fresh-open/page-turn painting, as well as existing content/navigation checks. A locally generated reference AZW3 of the same authored EPUB is available for a subsequent control test; it is not yet hardware-certified either. No production converter integration or hardware acceptance is claimed.

### Selector-fix retest and missing Library control investigation — 2026-09-08

The user reports that font scaling now works and content issues are fixed after the selector correction. The Home/Library arrow remains absent. Tapping the top of the page shows working Aa/search/menu controls; only the Home/Library arrow is missing. Treat the exit failure separately from the corrected content layout. C1 remains incomplete because reliable exit from the book is required.

Review of the local Calibre writer and Kindle driver found no field or workaround explicitly controlling visibility of the Home/Library arrow. `writer8/exth.py:build_exth` emits EXTH 501 `EBOK` plus EXTH 113 containing a generated UUID under normal AZW3 output defaults (`share_not_sync=False`). Native output uses `PDOC` and no 113. `ebooks/metadata/mobi.py:MetadataUpdater.update` also explicitly supports writing `PDOC`, so personal-document classification alone is not established as an error. The UUID comment describes synchronization, not Home-button behavior. A missing Library arrow cannot yet be attributed to either field.

Both writers use book type 2 and EXTH flags 0x50 for this fixture, not periodical flags. Guide references in `writer8/main.py:create_guide` are optional in-book targets and do not encode a route to the device library; the no-inline-TOC reference output and native file both omit a guide index. Native output includes EXTH 116 (start reading), whereas this reference does not. Calibre additionally supplies creator/resource metadata and text-record index trailers; none has been isolated as the cause. The selector-only retest retained the original content identity; stale device state is a hypothesis, not an observed cache diagnosis. Do not delete device databases/sidecars to investigate it.

Prepared `build/prototypes/Smallibre-Calibre-Control.azw3`, displayed title **Smallibre Calibre Control**, using Calibre 9.14.0 and the same authored EPUB, with `--dont-compress --no-inline-toc` and a distinct title/identity. Header inspection confirms standalone KF8, `EBOK`, and a UUID identifier. It has not been tested on the Kindle. First compare its Home/Library arrow on the same device. If it works, use fresh-identity native probes to isolate classification/identifier metadata from native content/index differences, changing one factor per test. Do not claim a native fix or add speculative metadata changes before that evidence.

The user also confirmed that **Nova Reader Test** has a working Home/Library return control. Header-only inspection of its matching retained hardware-test backups identifies MOBI version 6, book type 2, EXTH 501 `EBOK` and an EXTH 113 UUID. This is a useful known-working control on the same reader, but it differs from the native proof in both format generation (MOBI 6 versus KF8 8) and identity/classification metadata. It does not isolate `PDOC` or missing 113 as the cause. The separately generated Calibre AZW3 control is still needed to compare KF8 behavior. No personal content was extracted and no device files were changed for this comparison.

The user reconnected the Kindle and authorized the Calibre control transfer. The production helper sent `Smallibre Calibre Control.azw3` without overwriting, then full scan and readback verified SHA-256 `45163070885396e3e0482733ac980f62ff3ffd4e19f0202884d0fa71be8261d8` and exact source bytes. Existing main-book hashes were preserved. The isolated transfer check passed, receipts/backups remain under ignored `build/calibre-control-transfer-*`, and `diskutil eject` succeeded. The Home/Library-arrow result for this control is pending the user's on-device check.

### Calibre control result and native metadata probes — 2026-09-08

The user confirmed that **Smallibre Calibre Control** has a working Home/Library return control. KF8/AZW3 itself is therefore not sufficient to explain the failure on this Paperwhite; the unresolved difference is specific to the native artifact or its associated device state.

Prepared three local diagnostic variants of the selector-corrected native artifact: **Smallibre A Fresh PDOC** retains `PDOC` without EXTH 113 but has a fresh title, PalmDB name, MOBI UID and source identity; **Smallibre B PDOC UUID** additionally supplies EXTH 113; **Smallibre C EBOK UUID** uses that identifier with `EBOK`. Each variant has its own fresh identity to avoid intentionally reusing prior state. This means hardware comparisons isolate metadata profiles, not literally a single changed byte. All Palm records after record zero are byte-identical to the corrected native artifact, and all three pass the expanded bounded diagnostic. Paths and SHA-256 values are in ignored `build/prototypes/navigation-probes.json`. These are development-only probes, not changes to the production writer's metadata policy; none is yet transferred or hardware-tested. Test A first, then B/C if needed. If A restores the arrow, investigate identity/state before attributing the problem to document classification. If only B/C do, investigate the identifier/type behavior. If none do, continue comparing native content/index structures with the working Calibre control.

Probe A (**Smallibre A Fresh PDOC**) was subsequently transferred at the user's request through the production helper. Full scan and readback verified SHA-256 `8c910523de56abd195c3083fb403b7850340a87022c19ba5881bbd28f3ba5bb4` and exact bytes; existing main-book hashes remained unchanged. The isolated transfer check passed, local receipts/backups remain under ignored `build/probe-a-transfer-*`, and safe ejection succeeded. The user confirmed that Probe A still has no Home/Library arrow. A fresh title, PalmDB name, MOBI UID and source identity were insufficient to restore the control; this weakens, but does not conclusively exclude, a device-state explanation. Probes B and C remain local and untested. Next compare B (PDOC plus EXTH 113 UUID) and C (EBOK plus EXTH 113 UUID), whose content/index records remain unchanged.

Probes B (**Smallibre B PDOC UUID**) and C (**Smallibre C EBOK UUID**) were subsequently transferred through the production helper at the user's request. Their full readbacks matched the local artifacts, SHA-256 `e10bbfdf6b9b5b527202b89bb61ec4e7c492a06c371f82cef510ce34a90939c9` and `864d64e5b46dfd0cbf7c6eb0fd6c62010c2df3165e9b6d2ef080050ac865fe8d` respectively. All pre-existing main-book hashes were preserved, the isolated transfer check passed, and safe ejection succeeded. Receipts/backups remain under ignored `build/probe-bc-transfer-*`. Both on-device Library-arrow results are pending.

### Stable document identifier implementation — 2026-09-08

The user confirmed that both B (PDOC plus UUID) and C (EBOK plus UUID) have working Home/Library navigation. A (fresh PDOC without UUID) failed. This strongly supports EXTH 113 as the necessary compatibility addition for the tested native profile; changing PDOC classification is unnecessary. The native writer now emits exactly one EXTH 113 UUID and retains `PDOC`.

The identifier is deterministic UUIDv5 using the standard URL namespace and name `urn:smallibre:azw3:prototype:v1:sha256:<prepared EPUB SHA-256>`, following [RFC 9562 UUIDv5](https://www.rfc-editor.org/rfc/rfc9562.html#section-5.5). SHA-1 is confined to that standard UUID naming algorithm; integrity checks remain SHA-256. This profile-specific naming domain must change if a future conversion profile requires distinct document identity for the same input. No random per-export identity or title-only deduplication is introduced. All output records after record zero remain byte-identical to the selector-corrected artifact.

The new Swift regression first failed on absent EXTH 113, then passed with UUID presence, uniqueness, deterministic output and distinct identities for different input bytes sharing the same title. The standalone diagnostic now rejects missing or malformed UUIDs; both mutations were checked. Python's independent `uuid.uuid5` implementation matched the generated identifier `4a8dfcfb-0309-596d-9ca7-b3d246f09d6c`. The final artifact is `build/prototypes/Smallibre-native-identifier-fixed.azw3`, SHA-256 `d479c5fd03c8ecdc494c57cae809f2f8b4267de1604c794c0aac4235edafa52c`. Expanded structural inspection and independent Calibre decoding passed. The exact deterministic-UUID writer output has not yet been physically retested; the working diagnostic probes used fresh random UUIDs.

Nine focused AZW3 tests passed with output retention enabled. The full suite ran 87 tests: 81 passed, six opt-ins skipped, zero failures. Release packaging and strict ad-hoc signature verification passed. Changes remain scoped to the prototype and its validation; production conversion/export/send integration is still not delivered.
