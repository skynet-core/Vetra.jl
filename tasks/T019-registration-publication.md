# T019 — Register and publish the adoption release

Status: see [TASKS.md](../TASKS.md). Dependencies: T018 and explicit publication
authorization. Goal: make `Pkg.add("Vetra")` and public documentation available.

## Inputs and scope

Use T018's verified release candidate. Check the current General registration
process, version/name/UUID, repository ownership, and documentation deployment
target. The roadmap request authorizes planning, not remote mutations.

## Acceptance criteria

- Record the user's explicit publication request and release target before
  creating tags, registration requests, deployment changes, or remote releases.
- Submit the correct candidate through the supported registry workflow; record
  submission versus acceptance separately. A pending registry review is blocked,
  not "registered".
- After acceptance, verify `Pkg.add("Vetra")` in a clean environment, execute the
  quick start with its optional packages, and verify public documentation links.
- Publish release notes and update installation instructions to the released
  version, with an identifiable commit/tag and archived verification evidence.

## Validation

Repeat T018's affected release checks against the actual accepted artifact,
not a path-developed checkout. Validate the deployed docs and gallery URLs.

## Results and handoff

Blocked: T018 incomplete and publication has not been requested. Record registry
and release URLs, accepted version, and clean-install results when authorized.
