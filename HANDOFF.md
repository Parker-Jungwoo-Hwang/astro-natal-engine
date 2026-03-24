# HANDOFF

This bundle is a clean Stage 2 Swift package snapshot for the Swift Natal Engine project.

Included scope
- Stage 1 foundation: schemas, runtime data pack store, public engine facade, prepare() orchestration.
- Stage 2 ephemeris work: DAF header parsing, SPK summary parsing, segment indexing, Type 2 Chebyshev evaluation, and an ephemeris provider for Earth/Sun/Moon/planet state lookup.

Not included yet
- AstroTime
- AstroFrames
- AstroHouses
- AstroNatal computation
- final longitude/latitude/speed, houses, aspects, or JSON chart generation beyond the stubbed facade path

How to run
1. cd into the package root.
2. Run `swift test`.
3. To enable the real-kernel smoke test, set `ASTRO_DE442_PATH` to a local `de442.bsp` path before running tests.

Expected current behavior
- The package should compile and tests should pass without a real kernel.
- The `DE442SmokeTests` test is skipped unless `ASTRO_DE442_PATH` is set.
- `NatalChartEngine` still uses a stub chart computer and throws `featureNotImplemented` for actual chart math. That is intentional at Stage 2.

Notes for integration
- The package product exposed to consumers is `AstroNatalEngine`.
- `AstroEphemeris` is a target dependency, not the public product.
- The request/response DTOs and shared protocols are in `AstroSchemas`.
- Runtime pack management is in `AstroRuntimeData`.
