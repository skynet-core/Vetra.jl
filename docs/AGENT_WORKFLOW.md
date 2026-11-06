# Agent workflow

The project supports successive Codex sessions and, when requested, several
agents. No orchestrator, API key configuration, agent SDK, or background process
is included. AGENTS.md is persistent repository guidance; the other documents
are project conventions referenced by that file.

## Roles

| Role | Responsibility | Output |
| --- | --- | --- |
| Coordinator | Choose a bounded task, resolve dependencies, maintain handoff | Updated task and ownership record |
| Reference analyst | Inspect pinned Nim behavior and independently generate expected data | Source mapping, contract, fixture provenance |
| Implementer | Build the chosen Julia feature and focused tests | Reviewable code and test results |
| Reviewer | Check correctness, edge cases, and evidence without editing | Findings with exact locations |
| Performance analyst | Measure already-correct code against a fixed workload | Reproducible timings and allocation results |

One Codex session can take these roles sequentially. Role names do not imply
that multiple agents ran or that review is independent. Record who actually did
each pass. Use a new review session when an independent review is useful.

## Delegation (2026-10-28 user directive)

All coding work is delegated to the local `qwen3.8:27b` model through the
OpenCode subagent tool. The coordinator (this session) writes the specs and
the shared docs, scopes one wave at a time, and integrates the returned work;
the implementer owns `src/` and `test/` for the delegated task and reports
commands, coverage, and deviations. The implementer must not edit `TASKS.md`,
`docs/HANDOFF.md`, `docs/DECISIONS.md`, `docs/COMPATIBILITY.md`, or
`docs/API.md`; those are integrated by the coordinator from the report.

## Work loop

1. Read the entry files, inspect Git status, and select a ready task.
2. Record ownership and mark the task in progress.
3. Read the relevant pinned sources. Write down unclear behavior before coding.
4. Implement and run focused checks; inspect the final diff.
5. Resolve findings within the task's scope.
6. Update the task, compatibility inventory, decisions, and handoff with evidence.

Use the user's existing authorization for routine implementation choices. Ask a
question only when a missing decision materially changes scope or cannot safely
be inferred. A codec policy question need not block work on core arithmetic.

## Concurrent work

Default to one implementation writer. When the user requests parallel agents,
split genuinely independent tasks, use one branch/worktree per writer, and record
file ownership in TASKS.md. Assign one integrator to shared files such as
Project.toml, src/Vetra.jl, TASKS.md, and docs/HANDOFF.md. Other agents return
suggested changes to those files rather than editing them concurrently.

Do not parallelize the early core and rasterizer tasks before their interfaces
are stable. A read-only source audit or review can proceed alongside an
implementation when its scope is clear.

## Handoff content

Keep docs/HANDOFF.md short and current: task, changed files, actual commands and
outcomes, unresolved questions, next action, and any worktree ownership. Leave
long investigation notes in the task specification. Do not rely on chat history
as the only record of a decision.
