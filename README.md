# AstroNatalEngine

A pure-Swift natal-chart engine package organized around a runtime-downloaded data model.

Current package status:
- Stage 1: schemas, facade, `prepare()` state machine, runtime data manifest and pack storage
- Stage 2: `AstroEphemeris` module with a minimum DAF/SPK reader, Type 2 Chebyshev evaluation, and regression tests for Sun, Earth, and Moon state-vector lookup
- Stage 3: `AstroTime` module with strict local-time parsing, timezone resolution precedence, DST fold/gap handling, and UTC/TT/TDB scaffolding
- Stage 4: `AstroFrames` module plus a `Stage4NatalChartComputer` that converts ephemeris vectors into geocentric tropical body positions, signs, and longitudinal speeds
- Stage 5: `AstroHouses` module plus a `Stage5NatalChartComputer` that computes angles, Placidus cusps with equal-house fallback, and assigns houses to body positions
- Stage 6: `AstroNatal` module plus a `Stage6NatalChartComputer` that computes major aspects from the Stage 5 body/house output and returns a materially complete natal-chart payload
- Stage 7: a `Stage7NatalChartComputer` path that accepts `dUT1`/EOP input, threads it into sidereal-time-sensitive house calculations, and removes the standard no-EOP warning when real Earth-orientation data is present
- Stage 8: an apparent-reduction path in `AstroFrames` plus a `Stage8NatalChartComputer` that adds one-step light-time, annual aberration, and approximate nutation handling before the Stage 7 houses/aspects pipeline
- Stage 9: runtime-backed EOP integration through `RuntimeDataEarthOrientationProvider` and a `stage9` configuration path that auto-wires local EOP packs without manual provider injection
- Stage 10: runtime-backed ephemeris integration through `RuntimeInstalledDataLocator` and a `stage10` configuration path that auto-wires the local `de442` pack into the chart pipeline without external ephemeris-provider construction
- Stage 11: real-kernel regression coverage that exercises the full Stage 10 runtime path against an actual `de442.bsp` file when one is available locally
- Stage 12: a higher-accuracy apparent-reduction path that upgrades aberration and nutation handling and exposes a `stage12` runtime configuration path on top of the Stage 10 ephemeris/EOP stack

Notes:
- The `AstroEphemeris` module intentionally implements only the minimum subset needed for the project standard.
- The package includes optional real-kernel smoke and regression tests that run when `ASTRO_DE442_PATH` points at a real kernel or when `de442.bsp` is already installed under the runtime packs directory.
- Stage 4 computes body positions using mean-of-date precession and obliquity scaffolding; full apparent corrections remain a later stage.
- Stage 5 computes houses using UTC as the UT1 proxy and preserves the `standardModeWithoutEOP` warning until EOP-backed sidereal time is added.
- Stage 6 aspect orbs are profile-based but still use simple global orb presets rather than body-specific weighting.
- Stage 8 adds approximate apparent corrections, but full IAU/SOFA-grade nutation, gravitational light bending, and real-kernel snapshot verification are still later work.
- Stage 9 reads EOP data from a local JSON pack referenced by the runtime manifest; remote EOP ingestion policy and richer pack formats remain later work.
- Stage 10 auto-locates the local ephemeris pack from the runtime manifest, but real-kernel fixture coverage and remote ephemeris lifecycle policy remain later work.
- Stage 11 adds that real-kernel fixture coverage, but only runs when a local `de442.bsp` is actually available.
- Stage 12 strengthens the apparent path, but it is still not a full SOFA/IAU reduction stack and does not yet include gravitational light bending or the full nutation series.
- In this environment, run tests with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.
