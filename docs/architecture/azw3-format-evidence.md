# Native AZW3 prototype format evidence

This describes a deliberately narrow C1 experiment, not delivered conversion support. The initial output profile is standalone, DRM-free KF8 (MOBI version 8), UTF-8, PalmDOC compression type 1 (uncompressed). EPUB parsing, arbitrary document conversion and Kindle hardware acceptance remain separate gates.

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

Neither a successful diagnostic nor a successful reference conversion proves that a physical Kindle renders the book. C1 remains incomplete until an identified AZW3-capable Kindle's model and firmware, compression support, text order, Unicode, image, chapter navigation and cross-chapter link are recorded from actual reading. No device writes or hardware result are implied here.

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

The tested corrected file is also retained at `build/prototypes/Smallibre-native-proof.azw3` (ignored build output). No device copy was written. Physical validation must cover opening, chapter order, Unicode, checker image, chapter menu and both cross-chapter links on the identified Paperwhite. The user reports firmware possibly 5.19.6; exact model generation, firmware and connection mode are unconfirmed.

Local checks on macOS 26.6.2/arm64, Apple Swift 6.3.3: `swift test` executed 75 tests, with 70 passed and five skipped (four existing external/hardware opt-ins plus prototype-file retention); all seven AZW3 tests passed separately with file retention enabled. Release packaging and strict ad-hoc signature verification passed. The release bundle is 5,901,172 logical bytes, +197,504 bytes over the shared-contract build. No external runtime was added. Full converter/MTP throughput, peak runtime memory and physical cancellation measurements remain pending; small fixture test durations are not performance claims.
