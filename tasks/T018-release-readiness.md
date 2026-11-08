# T018 — Adoption release readiness

Status: see [TASKS.md](../TASKS.md). Dependencies: T014, T015, T016, T017.
Goal: prepare a reproducible package release that users can install and learn.

## Inputs and scope

Read Project.toml, optional-integration decisions, NOTICE/LICENSE, CI, and the
new gallery/tutorials. Recheck registry name/UUID suitability at execution time;
historical availability is not evidence of current availability. Prepare release
notes/version metadata and registration instructions; do not publish or tag.

## Acceptance criteria

- Install from the checkout in a fresh project/depot; verify core-only and
  optional-integration configurations, with documented Julia compatibility.
- Test Julia 1.10 and current supported Julia in the existing OS matrix where
  available; record actual local/CI evidence and any unmet platform checks.
- Dependencies have appropriate compat bounds, extension coverage is enforced,
  package-load/namespace checks pass, and licenses cover all shipped assets.
- Docs build from clean setup and show the final ergonomic/interoperability/
  display APIs; no reliance on ignored files already present on the developer's
  machine. Install examples switch to registry syntax only after registration.
- Release notes distinguish pinned compatibility from new optional features,
  and link measurements rather than promise universal performance.

## Validation

Run [shared validation](../docs/ROADMAP.md#shared-validation), install/load
subprocesses in isolated temporary projects, and the documented clean docs build.
Record exact environment setup commands, versions, logs, and CI results.

## Results and handoff

Status: done (2026-11-07). The verified release candidate is handed to T019;
nothing is published or tagged.

### Registry / identity (re-verified at execution time)

- `name = "Vetra"`, `uuid = 273bb84c-244c-4f17-9eb9-5a651004d3c7`.
- General-registry name check (2026-11-07): `P/Vetra` → **404**, still
  unregistered. (Historical 404s are not treated as current evidence; this
  was re-fetched now.)

### Fresh project/depot install (core-only + optional-integration)

Worked from a release-candidate snapshot of the working tree
(`/tmp/opencode/t018-rc`, no `.git`, `.reference` present) into a
**clean depot** (`JULIA_DEPOT_PATH=/tmp/opencode/t018-depot-*`):

- **Core-only**: fresh project + `Pkg.develop(path=rc)`. `using Vetra` loads;
  drawing with plain `Int` args works (T014); `encodePNG` and `toColors`
  raise the correct opt-in install hints; `showable(MIME"image/png",
  image) == false` (text fallback). Verified.
- **Optional-integration**: fresh project + `Pkg.develop(path=rc)` +
  `Pkg.add(["PNGFiles","XML","JpegTurbo","ColorTypes"])` (resolved:
  PNGFiles 0.4.5, XML 0.4.8, JpegTurbo 0.1.6, ColorTypes 0.12.5). PNG
  round-trip byte-exact, SVG parse, `toColors`/`fromColors` both work,
  `showable(MIME"image/png") == true`. Verified.
- **Install nuance recorded**: `Pkg.add(path=<git checkout>)` installs at
  **git HEAD**, i.e. the last *committed* state — uncommitted T014–T017 work
  is not picked up. A non-git snapshot installs via `Pkg.develop(path=)`.
  Users of the real repo get the committed state until T019 tags the release.

### Full gate in a clean environment

- `scripts/check.jl` (tests + coverage) run on the faithful rc snapshot in a
  fresh depot: **exit 0, all suites green, coverage 97.97% (5462/5575)**,
  assertion total unchanged at **811,472** (T018 adds no new tests).
  Log: `/tmp/opencode/t018-fresh-gate2.log`.
- The same gate also passed on the main repo in a fresh depot
  (`/tmp/opencode/t018-main-fresh.log`). An earlier rc attempt failed only
  because the harness `rsync` had excluded `.reference/` (the JPEG/font
  fixtures the suite reads); with `.reference` present it is green — a
  harness artifact, not a package defect. `.reference` is fetched by
  `scripts/fetch_upstream.jl` in CI and in the documented setup, so it is a
  declared prerequisite, not hidden developer-machine state.

### Julia compatibility / platform evidence

- `Project.toml` declares `julia = "1.10"` (lower bound); version bumped to
  **0.1.0** (resolved and loaded clean).
- **Local evidence**: all of the above on Julia 1.13.3 / Linux.
- **Unmet platform checks (recorded)**: the Julia **1.10** leg and the
  **Windows/macOS** legs are defined in the CI matrix
  (`.github/workflows/ci.yml`) but were **not re-run locally** for this
  task; they require a push, which is deferred to T019 (explicit request).
  No cross-platform regressions are asserted beyond what CI covers.

### Compat bounds / extension coverage / namespace / license

- `[extras]`/`[targets] test` declares all five test dependencies
  (Test, SHA, PNGFiles, XML, JpegTurbo, ColorTypes); no undeclared runtime
  deps (core is dependency-free).
- **Namespace check**: `using Vetra` imports exactly the **279** public
  exports (matches the `export` block); six of them shadow `Base` names —
  `ceil`, `copy`, `diff`, `fill`, `length`, `transpose` — which are
  intentional upstream pixie names and always reachable as `Base.<name>`.
- **License coverage**: `NOTICE` updated to cover the new T015 opt-in deps
  (ColorTypes MIT © 2015 Holy & Danisch; its transitive FixedPointNumbers
  MIT © 2014 Bezanson) and the cookbook's Noto Sans font (SIL OFL 1.1).
  Core is MIT; upstream pixie MIT is in `third_party/upstream.LICENSE`.

### Docs from clean setup

- `rm -rf docs/build` then `make_tutorial.jl` + `make_cookbook.jl` reproduces
  all gallery images and both executed docs with 0 broken links (T017).
  Prerequisite is `scripts/fetch_upstream.jl` (network) for fonts/fixtures —
  documented in `docs/INDEX.md` and the handoff, not implicit local state.
  Install examples in README/RELEASE_NOTES stay on checkout syntax; they
  switch to registry syntax only after T019 registration.

### Release notes + registration instructions

- `docs/RELEASE_NOTES.md` (draft, v0.1.0): distinguishes **pinned
  compatibility** (upstream revision `30bb5108…`, ~811k-assertion suite,
  COMPATIBILITY.md) from **new opt-in features** (T014–T017), and **links**
  measurements (README benchmarks, T012/T015 records) instead of promising
  universal performance.
- Registration instructions (RegistryTools flow, tag `v0.1.0`, re-verify
  name availability at execution time, post-registration README switch) are
  recorded in the same file for T019. **No registration or publication was
  performed.**

### Verification commands (exact)

```sh
# fresh core-only
export JULIA_DEPOT_PATH=/tmp/.../t018-depot-core
julia --startup-file=no --project=<fresh> -e 'using Pkg; Pkg.develop(path="/tmp/.../t018-rc")'
julia --startup-file=no --project=<fresh> <core-check.jl>     # hints + showable=false
# fresh optional
export JULIA_DEPOT_PATH=/tmp/.../t018-depot-opt
julia --startup-file=no --project=<fresh> -e 'using Pkg; Pkg.develop(path=rc); Pkg.add(["PNGFiles","XML","JpegTurbo","ColorTypes"])'
julia --startup-file=no --project=<fresh> <opt-check.jl>      # round-trips + showable=true
# full gate, clean env
JULIA_DEPOT_PATH=/tmp/.../t018-depot-test julia --startup-file=no --project=/tmp/.../t018-rc scripts/check.jl
```

### Limitations / next step

- Julia 1.10 + Windows/macOS CI legs unmet locally (need a push → T019).
- Version is set to 0.1.0 locally but **not tagged/registered**; T019 owns
  publication and must re-verify name availability. Next ready: T020
  (application benchmarks) and design tasks T023/T027/T030.
