# Codex prompts

Start Codex from this repository root. These prompts are ordinary text for the
extension; they do not install or start extra services.

## Begin

```text
Read AGENTS.md, TASKS.md, and docs/HANDOFF.md.
Execute T001 from tasks/T001-reference-baseline.md.
Keep the graphics implementation empty. Validate what you can, record exact
commands and any blockers, then update TASKS.md and docs/HANDOFF.md.
```

## Implement the next task

```text
Read AGENTS.md, TASKS.md, and docs/HANDOFF.md.
Choose the first ready task with completed dependencies and implement only that
task. If it needs a detailed specification, create one from tasks/TEMPLATE.md.
Inspect pinned upstream behavior, implement the smallest coherent change, run
the relevant checks, and update compatibility, decisions, and handoff records.
Do not claim checks passed unless you ran them.
```

## Review independently

```text
Act as a reviewer. Read AGENTS.md and the selected task's acceptance criteria,
then inspect the current diff and tests against the pinned upstream behavior.
Do not edit files. Report concrete defects with file/line references and missing
evidence, prioritizing alpha handling, rounding, indexing, transforms, bounds,
and fixture independence. State exactly which checks you ran.
```

## Resume a paused task

```text
Read AGENTS.md, TASKS.md, docs/HANDOFF.md, and the active task specification.
Inspect the working tree and preserve unfinished changes. Continue from the
recorded state, resolve the next actionable item, validate, and refresh the
handoff. If a recorded blocker is still present, explain it precisely.
```

## Investigate parity

```text
Investigate the failing fixture named in my message. Reproduce it at the pinned
upstream revision with the recorded toolchain and flags. Compare raw pixel
buffers, identify the first divergence and its cause, and propose a minimal fix.
Do not regenerate golden files or widen tolerances to hide a mismatch.
```
