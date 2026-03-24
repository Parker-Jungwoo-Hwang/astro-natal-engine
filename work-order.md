# Work Order — AstroNatalEngine Stage 2 Handoff

## Objective

You are receiving the current Swift package baseline for the Swift Natal Engine project through the end of Stage 2.
Your job is to assemble it, verify that the package matches the handoff expectations, and continue from this point without rewriting working components.

This is a Stage 2 baseline, not a finished natal-chart engine.

## Primary source of truth

Use these artifacts in this order.

1. `Swift-Natal-Engine-Manual-EN.md`
2. `AstroNatalEngine-Stage2-clean-with-work-order.zip` or the extracted package root
3. `HANDOFF.md`
4. `FILE_INDEX.txt`
5. `SHA256SUMS.txt`
6. `AstroNatalEngine-Stage2-full-source-dump.md`

If the code and the manual disagree on broad architecture, the manual wins.
If the question is about the exact current baseline behavior, the code wins.

## Architectural constraints that must be preserved

Preserve these decisions unless there is an explicit change request.

- Keep the core engine pure Swift.
- Keep the public product name as `AstroNatalEngine`.
- Keep engine code bundled with the app or backend, and keep large astronomy/time data as runtime-downloaded packs.
- Keep `de442.bsp` as the default kernel target.
- Keep `ResolvedBirthRequest` as the internal source-of-truth input.
- Keep `prepare()` as the only network-allowed phase.
- Keep `generate()` offline.
- Keep the Stage 2 ephemeris scope minimal rather than broadening into a generic SPICE clone.
- Do not introduce Swiss Ephemeris, paid libraries, or copyleft dependencies.

## Handoff contents

The package currently contains these targets.

- `AstroSchemas`
- `AstroRuntimeData`
- `AstroEphemeris`
- `AstroNatalEngine`

Tests currently exist for these areas.

- `AstroSchemasTests`
- `AstroRuntimeDataTests`
- `AstroEphemerisTests`
- `AstroNatalEngineTests`

Important root files.

- `Package.swift`
- `HANDOFF.md`
- `FILE_INDEX.txt`
- `SHA256SUMS.txt`
- `SOURCE_DUMP.md`
- `work-order.md`

Key implementation files by area.

```text
Sources/AstroSchemas/
  SchemaVersion.swift
  Enums.swift
  Errors.swift
  Protocols.swift
  Requests.swift
  Responses.swift
  Validation.swift

Sources/AstroRuntimeData/
  RuntimeDataModels.swift
  HTTPClient.swift
  SHA256.swift
  FileSystemDataPackStore.swift

Sources/AstroEphemeris/
  NAIFBody.swift
  KernelTypes.swift
  Chebyshev.swift
  SPKKernel.swift
  JPLEphemerisProvider.swift

Sources/AstroNatalEngine/
  Exports.swift
  NatalChartComputer.swift
  NatalEngineConfiguration.swift
  StrictBirthResolver.swift
  NatalChartEngine.swift
```

## Verified current status

The clean bundle was re-extracted and re-tested before this work order was written.

Verified result:

- `swift test` succeeded
- 16 tests passed
- 1 test was skipped intentionally
- 0 tests failed

The skipped test is:

- `DE442SmokeTests.testReadsRealDE442KernelWhenAvailable`

It is skipped unless `ASTRO_DE442_PATH` points to a local `de442.bsp` file.

## What is implemented now

### Stage 1 baseline

- request and response DTOs
- schema version constants
- enums, warning codes, and error types
- request validation
- public protocols
- engine facade
- `prepare()` state machine
- manifest and pack storage models
- SHA-256 verification
- atomic pack replacement
- offline-friendly installed-data version reporting

### Stage 2 baseline

- DAF header parsing
- summary record parsing
- name record parsing
- SPK segment descriptor indexing
- overlapping-segment selection with later segment precedence
- SPK Type 2 Chebyshev evaluation
- recursive center-chain state resolution
- `JPLEphemerisProvider` adapter for public `EphemerisProvider`
- regression tests for Sun / Earth / Moon-oriented state-vector paths using synthetic fixtures
- optional smoke-test hook for a real `de442.bsp`

## What is intentionally not finished

These are expected gaps, not accidental omissions.

- `AstroTime`
- full strict birth-time processing
- timezone rule resolution from `timeZoneId`
- DST fold / gap handling
- UTC -> TT -> TDB pipeline
- ΔT table/polynomial logic
- `AstroFrames`
- geocentric apparent-of-date conversion
- ecliptic longitude / latitude / speed calculation
- sign conversion from real planetary results
- `AstroHouses`
- ASC / MC / IC / DC
- Placidus and Equal-house fallback
- `AstroNatal`
- aspect calculation
- final populated natal chart generation

The default `StubNatalChartComputer` still throws `featureNotImplemented(...)`.
That is intentional at this baseline.

## Known limitations that the next agent must understand

1. `StrictBirthResolver` is a strict placeholder.
   It currently requires `utcOffsetMinutesAtBirth`.
   If the raw request only supplies `timeZoneId`, the resolver does not yet perform historical timezone resolution.
   That work belongs to Stage 3.

2. `JPLEphemerisProvider` currently returns barycentric J2000 Cartesian state vectors in kilometers and kilometers per second.
   Later stages must convert these into the geocentric apparent tropical quantities used by the natal chart response.

3. The runtime-data layer manages manifests and pack files, but this handoff does not include a real `de442.bsp` payload.
   The real-kernel path is wired for validation, not bundled as data.

4. `generateJSON()` is operational as a transport bridge, but actual astronomical chart production still depends on later-stage computation modules.

## Receiver actions

Perform these steps in order.

### 1. Unpack and inspect

```bash
unzip AstroNatalEngine-Stage2-clean-with-work-order.zip
cd AstroNatalEngine-Stage2-clean
```

If you are using the earlier bundle instead, extract `AstroNatalEngine-Stage2-clean.zip` and place `work-order.md` in the package root.

### 2. Verify integrity

Linux:

```bash
sha256sum -c SHA256SUMS.txt
```

macOS:

```bash
shasum -a 256 -c SHA256SUMS.txt
```

If your local `shasum` does not support `-c` cleanly in your shell environment, verify the listed files manually against `SHA256SUMS.txt`.

### 3. Run the test baseline

```bash
swift test
```

Expected result without a real kernel file:

- 16 tests passed
- 1 skipped
- 0 failed

### 4. Run the real-kernel smoke test when a kernel is available

```bash
ASTRO_DE442_PATH=/absolute/path/to/de442.bsp swift test --filter DE442SmokeTests
```

If the path is correct, the smoke test should execute instead of skipping.

### 5. Freeze the baseline before new work

Before starting Stage 3, create a clean commit or tag for the verified Stage 2 baseline.

### 6. Preserve public API and module boundaries

Do not rename the library product, collapse targets together, or widen the public surface unless there is an explicit versioning decision.

## Recommended next implementation scope: Stage 3

The next agent should move to Stage 3 and stop there.

Deliverables for Stage 3:

1. Add the `AstroTime` target to `Package.swift`.
2. Add the `ResolvedTime` model aligned with the manual.
3. Implement local civil-time parsing.
4. Implement strict timezone handling with this precedence:
   - `utcOffsetMinutesAtBirth` first
   - then `timeZoneId`
   - then host-assisted fallback if designed
5. Implement DST fold / gap handling and ambiguity policy enforcement.
6. Implement UTC, TT, and TDB conversion scaffolding.
7. Implement ΔT handling suitable for the project date range.
8. Expand test coverage for:
   - DST fold
   - DST gap
   - early 1900s births
   - late 2150 births
   - invalid offsets
   - unresolved timezone cases
9. Keep `AstroFrames`, `AstroHouses`, and `AstroNatal` out of Stage 3 unless Stage 3 is already green.

## Acceptance gates for this handoff

Treat the handoff as accepted only when all are true.

- all files are present
- checksum verification passes
- `swift test` is green at the Stage 2 baseline
- no public product rename has occurred
- no new third-party dependency has been added
- the agent understands that actual natal chart math is not complete yet
- the agent understands that real `de442.bsp` validation requires an external kernel file

## Discrepancy policy

If you find a mismatch, follow this rule.

- For project direction and scope boundaries, follow the manual.
- For exact current behavior, follow the code and tests.
- Do not silently “improve” broad areas during assembly.
- If you must change behavior, document it explicitly as a new stage delta.

## Final summary for the receiving agent

This package is a verified Stage 2 baseline consisting of:

- the schema layer
- runtime pack preparation and verification
- the engine facade and `prepare()` orchestration
- a minimal SPK reader for natal-chart use
- regression tests around the ephemeris core

It is not yet a full natal chart engine.
Your immediate task is to verify and preserve this baseline, then implement Stage 3 (`AstroTime`) in a controlled way.
