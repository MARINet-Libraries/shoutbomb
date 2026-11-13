# T-004: Group branches under library systems

- Created: 2026-11-10
- Status: planned
- Goal: Support library-system views that group multiple branches, while retaining overall and individual-branch views.

## Context and scope

Deferred from [T-002](monthly-report-visualizations.md) with user approval. Some libraries have multiple branches; the user cited Marin County Free Library as an example. The current v1 focus is an all-branches overview and optional individual-branch views, without system grouping.

No authoritative branch-to-library mapping has been supplied or approved. Do not infer membership from branch names.

## Open decisions

- Obtain and validate the branch-to-library-system mapping and decide where it should be maintained.
- Define selection, labels, and aggregation for overall, library-system, and branch views.
- Decide how unassigned branches, changing membership, and missing metrics should appear.
- Define bookmarkable system selection without breaking existing branch/report URL fragments or Back/Forward behavior.

## Guardrails

Avoid double-counting repeated summaries or system totals when aggregating branches. Keep notice and item counts separate and missing metrics unknown. Selection remains a presentation feature, not access control over embedded data. Use synthetic fixtures and do not access live services or the real `.env`.

## Progress and next step

Planning only; no implementation authorized or performed for this task. When resumed, obtain an approved grouping map and agree on the selection/aggregation behavior before implementation. This work does not block T-002's v1 report.
