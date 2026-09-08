# Calibre source audit for Smallibre

Inspected 2026-09-08. Local checkout: `calibre/`, upstream commit `025d9cf3a1ef5ce6c9576a29a0963d2175b02d4c` dated 2026-09-07. `src/calibre/constants.py:15` declares 9.14.0. This is a targeted static architecture review, not an exhaustive security audit, runtime benchmark or compiled dependency analysis.

## Evidence map

Paths below are relative to the supplied `calibre/` tree. Line anchors refer to that pinned checkout.

| Area | Evidence | Implication for Smallibre |
|---|---|---|
| Runtime/license | `pyproject.toml`: Python >=3.14, GPL-3.0-only, PyQt6 and PyQt6_WebEngine; `COPYRIGHT` contains per-file exceptions | Bundle a compatible worker runtime and audit dependencies; do not assume every resource has identical licensing |
| UI | `src/calibre/gui2/`, 581 files in this checkout | A large, feature-rich interface is outside Smallibre's initial scope; no need to transplant it |
| Conversion | `src/calibre/ebooks/conversion/plumber.py:1188`, `run()` | Input plugins produce OEB, then shared transforms and an output plugin; avoid this entire pipeline for small EPUB edits |
| Transform behavior | `plumber.py:1286–1450` | Structure detection, CSS flattening, metadata, font and output-specific operations can change more than requested |
| MOBI import | `src/calibre/ebooks/conversion/plugins/mobi_input.py` | Distinguishes legacy and KF8/joint MOBI; formats cannot be handled solely from extension |
| EPUB import | `src/calibre/ebooks/conversion/plugins/epub_input.py:47`, `process_encryption()` | Recognizes standard font obfuscation separately from unsupported encryption; Smallibre must preserve that distinction |
| AZW3 writing | `src/calibre/ebooks/conversion/plugins/mobi_output.py:345`, plus `ebooks/mobi/writer8/` | Existing KF8 writer is a substantial reuse opportunity |
| Targeted polishing | `src/calibre/ebooks/oeb/polish/main.py`, `container.py`, `css.py:366` | Container-level edits and explicit CSS transforms are better suited to basic improvements than whole-book conversion |
| Image dependencies | `src/calibre/utils/img.py:13` and `:22`; `ebooks/mobi/writer2/resources.py:130` and `:209` | Image utilities use Qt image classes and native `imageops`; converter extraction needs a real dependency trace |
| Native dependencies | `src/calibre/__init__.py:506`; `startup.py`; `utils/icu.py` | Copying Python source alone does not package the engine |
| Plugin coupling | `src/calibre/customize/ui.py`, imports built-in plugin registry and several plugin categories | A narrow explicit worker registry is preferable to loading the general plugin environment |
| Metadata | `src/calibre/ebooks/metadata/sources/identify.py` | Provider workers, timeouts/abort, ranking/merging are existing patterns; a smaller provider set is sufficient for Smallibre |
| Library cache | `src/calibre/db/cache.py:146`, `Cache` | Calibre caches metadata and reimplements search/sort above SQLite; Smallibre can favor paginated SQL with a narrower feature set |
| Library writes | `cache.py:2271`, `:2423`, `:2683` | Metadata, formats and book creation are separate operations; Smallibre should explicitly model them too |
| Mounted device upload | `src/calibre/devices/usbms/driver.py:320` | Upload path handling and cover transfer are separate concerns; cover failure is nonfatal |
| MTP dispatch | `src/calibre/devices/mtp/driver.py:25–34` | Windows and Unix use different backends |
| MTP upload | `src/calibre/devices/mtp/driver.py:545` | Parent objects, size and stream-based writes; this is not a mounted-filesystem copy |
| MTP Mac detection | `src/calibre/devices/mtp/unix/driver.py` | Uses libmtp and macOS USB observer/IOKit-related detection; file picker alone is insufficient |
| Amazon defaults | `src/calibre/devices/mtp/defaults.py:19–36` | Amazon format map includes AZW3/MOBI/KFX/PDF but not EPUB; preferred destination folders are model policy |
| Kindle variation | `src/calibre/devices/kindle/driver.py:93`, `:709` | Format support differs across generations; avoid a universal Kindle extension list |
| Cover/page extras | `src/calibre/devices/kindle/driver.py`; MTP upload-cover/APNX steps | Extras are useful but can fail independently of book delivery; model them as optional steps |
| Existing process isolation | `src/calibre/utils/ipc/simple_worker.py` | Subprocess offload, abort and timeout are already part of Calibre's design |
| Distribution | `bypy/README.rst`, `bypy/sources.json` | Calibre builds dependencies and installers across platforms; Smallibre needs its own packaging proof, not a GUI-only size comparison |

## Scope measurements

Direct recursive file counts, excluding directories but not generated files, in the supplied checkout:

| Subtree | Files | Source/resource bytes |
|---|---:|---:|
| `src/calibre/gui2` | 581 | 7,599,932 |
| `src/calibre/ebooks` | 466 | 10,368,428 |
| `src/calibre/devices` | 114 | 1,370,217 |
| `src/calibre/db` | 77 | 1,354,186 |
| `src/calibre/utils` | 192 | 2,249,802 |
| `recipes` | 2,145 | 4,171,640 |
| `resources` | 323 | 5,828,435 |

These counts show scope only. They do not measure installer footprint, memory or speed. Native dependencies, generated build resources and runtime bundles are not represented by these totals. No claimed percentage reduction has been measured.

## Keep, adapt, exclude

**Keep conceptually and selectively reuse:** proven format parsers/writers, targeted polish operations, format/device quirks, metadata reader behavior, useful tests, separation of book/format/metadata, subprocess isolation.

**Adapt:** replace broad plugin discovery with explicit worker operations; wrap conversion behind versioned jobs; retain upstream layout and patches; build Smallibre-specific model capability data with evidence. A transitive dependency may require retaining more modules than the entry-point list suggests.

**Exclude from the first product:** old GUI, general plugin compatibility, news recipes, stores, AI, server, broad input-format support, full editor/viewer runtime, custom column/template systems and device database editing. Excluding a feature from Smallibre's UI does not prove its dependency can be removed from the worker; runtime trace and tests decide that.

## Unverified matters and the required experiments

1. Smallest working converter dependency closure and whether Qt Core/Gui can be removed economically.
2. Signed/notarized helper operation on a clean Mac without a Calibre/Python installation.
3. Exact physical device models/firmware and MTP behavior, including object reconciliation after interruption.
4. Corpus conversion/rendering quality after dependency trimming.
5. Total installed size, peak worker memory, startup and UI responsiveness relative to a measured baseline.

The main [architecture proposal](../superpowers/specs/2026-09-08-smallibre-design.md) turns these into Stage 0 and release gates. The supplied source checkout was not modified or built during this review.
