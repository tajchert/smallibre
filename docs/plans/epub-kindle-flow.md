# EPUB to Kindle workflow

User-approved scope: prepare supported reflowable EPUBs as native AZW3, review conversion warnings, export locally or send to a mounted Kindle. MTP remains a separate transport project.

1. Extend the hardware-proven KF8 encoder with bounded ordinary EPUB support and structural validation. Preserve the Kindle selector and content-identity fixes. Reject unsupported content explicitly.
2. Capture original hash, prepared EPUB hash, canonical settings hash, converter version and profile. Publish output and manifest together under `converted/<UUID>/`; verify cached bytes before reuse. Never replace originals or existing artifacts.
3. Transfer the exact reviewed artifact inside the reader helper through intent, upload, readback and verification. Use exclusive descriptor-relative device writes and retain uncertain outcomes in history.
4. Add warning review and conversion errors to Kindle send and local AZW3 export. Preserve cancellation, sleep and library initialization gates.
5. Test conversion, provenance/cache integrity, collision handling, receipt states and app lifecycle. Run the full suite, bundle build and signature verification. Hardware readability of broader output remains a manual acceptance check.

Contracts: `AZW3Converter.convert(Data)` returns data and warnings; `validate(Data)` checks output structure. `LibraryStore.prepareKindleArtifact(for:)` captures preparation and returns `PreparedBookArtifact`. `exportKindleArtifact(_:to:)` exports verified bytes. Reader helper accepts `sendArtifact` with the immutable manifest. No automatic device retries or artifact cleanup.
