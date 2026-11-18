# T-004: Group branches under library systems

- Created: 2026-11-10
- Status: done
- Goal: Support library-system views that group multiple branches, while retaining overall and individual-branch views.

## Context and scope

Deferred from [T-002](monthly-report-visualizations.md) with user approval. Some libraries have multiple branches; the user cited Marin County Free Library as an example. At deferral, v1 supported an all-branches overview and optional individual-branch views without system grouping; this task adds the system views.

The user supplied the following branch-to-library mapping and confirmed that Fairfax and Inverness are separate branches (correcting the supplied “Fairfaxx Inverness”). Do not infer membership for unlisted branches.

| Library system | Branches |
| --- | --- |
| Marin County Free Library (MCFL) | Bolinas, Civic Center, Corte Madera, Fairfax, Inverness, Marin City, Novato, Point Reyes, South Novato, Stinson Beach, Bookmobile |
| San Rafael | San Rafael Downtown, Pickleweed, Mall |

Mall may not occur in the report data. Inspected branch headers and registration labels in the three supplied August–October reports to establish exact source aliases such as `Novato Library` and `San Rafael Pickleweed Library`. These aliases are explicit in the mapping, not inferred at runtime; tests use synthetic reports only.

## Implemented decisions

The user approved implementation with these defaults:

- Maintain explicit system membership, branch display labels, and exact source aliases in version-controlled `lib/monthly-library-groups.json`, embedded when generating the offline dashboard. Reject overlapping aliases, duplicate system IDs, and multiple source labels for one mapped branch rather than risk double-counting. Existing source branch IDs remain unchanged.
- Use the single selector layout below. Keep mapped branches absent from the inputs selectable with a No data notice and unknown counts; unassigned source branches follow the grouped entries individually.
- System figures sum member branches only, with every mapped member required for each metric/month. Missing members or metrics and unsafe integer sums leave totals unknown, never partial or zero. Sum each branch's own notice total or complete notice components once; exclude repeated summaries, source-wide totals, and unattributed signups. Preserve separate notice/item counts.
- Keep all-branches totals unchanged. In system views, restrict branch comparisons to members while retaining explicitly labeled all-branches keyword activity, source registration totals, and source percentages.
- Use `#system=mcfl` / `#system=san-rafael` with the existing report parameter. Explicit system selection takes precedence if a hand-written URL also contains a branch; selecting/linking a branch clears the system parameter and vice versa. Preserve unrelated fragment parameters and Back/Forward synchronization.
- Apply the embedded mapping to every included month. Historical membership changes are not modeled and would require explicit future rules.

## Agreed selection layout

Use one pick list: All branches first, then MCFL as a selectable system with its individual branches indented beneath it, followed by San Rafael as a selectable system with its individual branches indented beneath it. Do not introduce separate view-type selectors. The user approved an example with unassigned branches listed individually after the grouped entries. Selecting a system shows its combined report; selecting a branch shows only that branch. Mapped branches absent from the data stay selectable, showing a No data notice and unknown counts as approved.

## Guardrails

Avoid double-counting repeated summaries or system totals when aggregating branches. Keep notice and item counts separate and missing metrics unknown. Selection remains a presentation feature, not access control over embedded data. Use synthetic fixtures and do not access live services or the real `.env`.

## Progress and validation

Implemented the mapping builder, grouped pick list, system aggregation/detail/chart views, and bookmarkable system selection. Updated CLI help, README, AGENTS guidance, and CHANGELOG. The user approved the mapping, Fairfax/Inverness correction, selector example, implementation defaults, and explicitly requested marking the task done before staging files; closure is authorized, with no archive requested.

Validation:

- `node --test tests/monthly-visualizations.test.cjs`: all 34 isolated tests pass, including seven new mapping/aggregation/navigation/offline-generation tests.
- `node --check` on the executable, parser, dashboard script, and test file: passed.
- `./visualize-monthly-reports --help` and `git diff --check`: passed.
- `./check`: Bash syntax checks passed, then exited 127 because ShellCheck and Bats are unavailable; ShellCheck and Bats behavior suites were not run.
- No live services, real `.env`, working-dashboard regeneration, or real-browser visual checks were used for validation.

No remaining implementation decisions. Re-run `./check` when Bats-core and ShellCheck are available; real-browser visual review remains outside the isolated DOM tests. Stage task changes only, leaving unrelated work and source CSVs untouched, and recommend a commit message without committing.
