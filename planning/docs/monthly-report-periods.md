# T-003: Reporting-month interpretation and multi-month trends

- Created: 2026-11-10
- Status: planned
- Goal: Establish how reporting periods should be assigned to monthly Shoutbomb reports and review reliable multi-month presentation.

## Context and scope

Deferred from [T-002](monthly-report-visualizations.md) with user approval. The user confirmed that the supplied file `sb_generate_monthly_report_feb88521e8_2026-11-05_00_10_18.csv` contains October 2026 statistics. This establishes the period for that file only, not a rule for future or historical files.

The existing implementation supports explicit `--period YYYY-MM`, opt-in `--previous-month`, and trends when multiple assigned months exist. These features are context, not confirmation of the source's general date convention.

Subsequent user feedback on 2026-11-10 made growth-focused visualizations central to T-002, which resumed on 2026-11-12 after the user supplied and approved August–October named reports. Comparisons using individually confirmed activity months belong to T-002; this planned follow-up retains general period interpretation and broader cross-month reliability questions. No status change or implementation is authorized for T-003.

## Open decisions

- What authoritative evidence establishes each report's activity month?
- Is a consistent relationship between filename generation dates and reporting months guaranteed, including delayed reports and backfills?
- What defaults, overrides, and uncertainty labels should the CLI and dashboard use?
- How should multi-month comparisons handle missing metrics, duplicate reports, and corrections?

## Guardrails

Preserve explicit assignments and unknown values; do not silently infer activity months from filenames. Keep notice and item counts separate. Use synthetic fixtures for routine tests and do not access live services or the real `.env`.

## Progress and next step

Planning only; no implementation authorized or performed for this task. When resumed, confirm the period convention with the user or authoritative source documentation, then review the parser, CLI, dashboard, and existing tests before proposing changes. T-002 now supports opt-in `--named-periods` for the user-confirmed Month_YYYY labels without deriving activity months from generation timestamps. Its historical-data blocker is resolved; keep its implementation distinct from this still-planned general-convention review.
