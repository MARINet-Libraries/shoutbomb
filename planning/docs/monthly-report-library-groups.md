# T-004: Group branches under library systems

- Created: 2026-11-10
- Status: in-progress
- Goal: Support library-system views that group multiple branches, while retaining overall and individual-branch views.

## Context and scope

Deferred from [T-002](monthly-report-visualizations.md) with user approval. Some libraries have multiple branches; the user cited Marin County Free Library as an example. At deferral, v1 supported an all-branches overview and optional individual-branch views without system grouping; this task adds the system views.

The user supplied the following branch-to-library mapping and confirmed that Fairfax and Inverness are separate branches (correcting the supplied “Fairfaxx Inverness”). Do not infer membership for unlisted branches.

| Library system | Branches |
| --- | --- |
| Marin County Free Library (MCFL) | Bolinas, Civic Center, Corte Madera, Fairfax, Inverness, Marin City, Novato, Point Reyes, South Novato, Stinson Beach, Bookmobile |
| San Rafael | San Rafael Downtown, Pickleweed, Northgate Library |

The user corrected the initially supplied Mall member to Northgate Library on 2026-11-18, supplied the exact source `San Rafael Northgate Library`, and confirmed there is no Mall. The mapping has no Mall member or alias. Northgate does not occur in the supplied August–October reports. Inspected branch headers and registration labels in those reports to establish exact source aliases such as `Novato Library` and `San Rafael Pickleweed Library`. Aliases are explicit in the mapping, not inferred at runtime; routine tests use synthetic reports only.

## Implemented decisions

The user approved implementation with these defaults:

- Maintain explicit system membership, branch display labels, and exact source aliases in version-controlled `lib/monthly-library-groups.json`, embedded when generating the offline dashboard. Reject overlapping aliases, duplicate system IDs, and multiple source labels for one mapped branch rather than risk double-counting. Existing source branch IDs remain unchanged.
- Use the single selector layout below. Keep mapped branches absent from the inputs selectable with a No data notice and unknown counts; unassigned source branches follow the grouped entries individually.
- Updated with user approval on 2026-11-18: system figures sum reported member values for each metric/month, with explicit coverage labels and partial-subtotal wording. Missing members/metrics are not zero; no reported values and unsafe sums remain unknown. Comparisons and connected chart lines require identical contributing members. Sum each branch's own notice total or complete notice components once; exclude repeated summaries, source-wide totals, and unattributed signups. Preserve separate notice/item counts.
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

## Reopened follow-up · 2026-11-18

The user reported unusable rollups and requested checking branch names against the supplied August–October CSVs. Read-only diagnosis confirmed that all observed member names match explicit aliases: Civic Center Library, Corte Madera Library, Fairfax Library, Inverness Library, Marin City Library, Novato Library, South Novato Library, San Rafael Downtown Library, and San Rafael Pickleweed Library. Bolinas, Point Reyes, Stinson Beach, Bookmobile, and Northgate never appear, so their source spellings cannot be verified from these examples. Northgate's exact source spelling was subsequently supplied by the user; do not invent aliases for the others.

The previous strict completeness rule makes every headline system total unknown in these examples. The user approved showing reported-member subtotals with coverage instead. October reported subtotals are MCFL 30 registered / 5 signups / 107 notices and San Rafael 17 / 2 / 44; coverage varies by metric. All 34 baseline isolated tests pass but enforce the superseded strict rule.

Implemented metric-specific subtotal/coverage reporting, retained unknowns for no data/overflow, suppressed comparisons and chart connections when contributing members change, and added synthetic regression coverage. Coverage is shown alongside headline counts, in monthly-value/detail tables, and in chart accessibility text; absent-member notices name branches, and notice breakdowns explain that different rows can cover different members. Northgate Library now maps to exact source `San Rafael Northgate Library`, with no Mall alias. Updated help, README, AGENTS, and CHANGELOG.

Follow-up validation:

- `node --test tests/monthly-visualizations.test.cjs`: all 38 isolated tests pass, including sparse source-shaped fixtures, metric-specific coverage, matching/mismatching reporting-member sets, no-data/zero/overflow behavior, independent notice components, and exact Northgate mapping/selection.
- `node --check` on the executable, parser, dashboard script, and tests; `./visualize-monthly-reports --help`; and `git diff --check`: passed.
- Generated a temporary offline dashboard from all three user-provided example CSVs and asserted each system's registered/signup/notice subtotals for every month. October MCFL: 30 (7/11 members), 5 (4/11), 107 (7/11); San Rafael: 17 (2/3), 2 (1/3), 44 (2/3). Confirmed no Mall in the generated HTML. Temporary output was removed; working dashboards and input CSVs were not changed.
- `./check`: Bash syntax checks passed, then exited 127 because ShellCheck and Bats are unavailable. Their suites were not run. No live services, real `.env`, or real-browser visual validation used.

**Awaiting user acceptance.** Keep T-004 in-progress until the user explicitly approves closing the follow-up. Suggested next step: regenerate the working dashboard with the intended local inputs and visually review system coverage and Northgate selection; re-run `./check` once ShellCheck/Bats are available. Do not stage unrelated changes/source CSVs or commit without permission.
