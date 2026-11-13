# T-002: Monthly report visualizations for branch staff

- Created: 2026-11-09
- Status: in-progress
- Review state: Layout refinements staged for review/commit; awaiting user acceptance.
- Goal: Produce a simple, single-column staff report focused on month-over-month service adoption, usage, and growth or decline, defaulting to an all-branches overview with optional branch views. Use the user-approved August, September, and October 2026 named reports, with the new October source replacing the earlier baseline.

## Context and discovery

Inspected the user-provided root file `sb_generate_monthly_report_feb88521e8_2026-11-05_00_10_18.csv`. It is a sectioned text report with CSV-like rows, blank lines, prose summaries, and separator headings, rather than one rectangular CSV table. The source remains unmodified and untracked.

Available data includes:

- Per-branch hold notices, hold reminders, and overdue notices.
- Per-branch overdue item eligibility and unsuccessful renewal counts, where present.
- System-wide totals and percentages, plus a repeated branch notice-total section.
- Registered patrons and new signups by branch.
- System-wide keyword usage, registration totals, and language counts.

The sample lists 13 branches in notice activity and 14 in registered patrons; Sausalito appears only in the latter. It contains aggregate counts rather than individual patron records. Future inputs still need privacy-aware handling.

## Confirmed requirements

- Branch selection must be reflected in the URL, so a branch-specific view can be bookmarked or shared and restored on load.
- URL mechanism: a fragment such as `report.html#branch=novato-library`, compatible with a self-contained report opened locally or hosted. Keep the selector and URL synchronized, including browser Back/Forward navigation; handle missing or unknown branches gracefully. The implementation also preserves report selection in a `report` parameter.
- The user approved starting the offline HTML dashboard implementation after the URL-selection requirement was recorded.
- On 2026-11-10, the user confirmed that the supplied file contains October 2026 statistics. V1 should prioritize this file, a beautiful and useful staff report, an all-branches default overview, and optional specific-branch views.
- General reporting-month interpretation remains deferred to [T-003](monthly-report-periods.md). Multi-month visualizations were initially deferred there, but subsequent user feedback makes growth-focused comparisons central to T-002 using explicitly confirmed months. Library-system grouping (for example, Marin County Free Library and its branches) remains deferred to [T-004](monthly-report-library-groups.md).
- The user initially approved planning changes only, then approved starting implementation from the proposed layout on 2026-11-10: an October heading, five summary cards, notice activity/branch comparisons, separate registrations/signups, overdue items, and system-wide details/data notes.

## Simplification requirements (2026-11-13)

- The user wants a very basic, single-column scrolling report: one metric after another, without cards, side-by-side charts, or forced full-screen sections.
- Put registered patrons, new signups, and text notices first. Each gets its heading, selected-month count/change, and one chart together.
- Keep keyword usage and all remaining information below those three primary metrics, rather than removing it. Preserve branch/report URL selection and all existing data interpretation safeguards.

## Current first-version scope

- A plain, self-contained offline staff report centered on adoption and usage over time, with the user-confirmed August–October 2026 reports. Default to an all-branches overview; offer a specific-branch view and printable summaries. The new named October file is authoritative.
- Stack registered patrons, new signups, and notices as the primary metrics, each with its count/change/chart together. Put keyword usage and all supporting values, branch comparisons, overdue-item counts, and source notes below. Do not mix message counts with item counts.
- Branch comparisons for context, clearly labeled as activity rather than performance rankings; branch size/circulation denominators are not available.
- Month-over-month growth or decline is the primary reporting question. Show comparable current/prior counts and changes where supported, and trends when several months are available; never imply growth from October alone. General filename/month interpretation and grouping branches under library systems remain outside v1.
- System-wide keyword usage displayed separately because the report does not attribute it to branches.

## Decisions and remaining interpretation questions

- The supplied reports are confirmed as August–October 2026 activity; this does not establish a general generation-date convention. The implementation defaults to unconfirmed activity months and supports explicit `--period YYYY-MM` for one input, `--previous-month` for legacy dated inputs, and opt-in `--named-periods` for Month_YYYY labels in the new filename family. General date-convention decisions remain in T-003; growth-focused presentation using explicitly confirmed periods belongs to T-002.
- Omitted metrics remain unavailable, not assumed zero. Repeated reminder prose and aggregate summaries do not add activity; registration-only branches are preserved.
- Source totals are reconciled where practical, with warnings. Message and item counts remain separate. Source percentages are displayed only in clearly labeled system context with unverified denominators; no inferred rates or language shares are charted.
- Duplicate normalized data in the same assigned month is skipped. Conflicting corrections fail so the user can select one source. Without an assigned month, grouping uses the filename date or one undated group.
- Added `visualize-monthly-reports`, requiring Node.js 18+ with no npm dependencies or `.env`. Default output is project-root `data/monthly-visualizations/index.html`; explicit input/output arguments resolve from the working directory. Output is atomically replaced with owner-only permissions; inputs cannot be overwritten.
- Normalized data is embedded in the HTML, not emitted as a second public file. All included branches remain in the dataset; selection is not access control. Source text is escaped, and the dashboard uses no external services/libraries.
- No download, upload, retention, monitoring, or arrival-state behavior changed.

## Implementation and validation outline

1. Use the confirmed October 2026 period for this file; agree on the all-branches overview and visual presentation without blocking on a general reporting-period convention.
2. Review relevant repository conventions and configuration/docs before adding the entrypoint.
3. Implement a section-aware parser and explicit normalized metric model with useful diagnostics for malformed or unfamiliar input.
4. Render agreed visualizations with escaped source text and no unnecessary exposure of sensitive data or external dependencies.
5. Add isolated tests using synthetic fixtures, including repeated summaries, absent metrics, registration-only branches, malformed input, and multiple months. Validate branch URL restoration, selection updates, Back/Forward navigation, and missing/unknown branch handling.
6. Document implemented CLI/dependencies/output behavior, update `AGENTS.md` where contracts change, and record implementation in `CHANGELOG.md`.
7. Run applicable local checks; distinguish those from live validation. Do not contact live services or read the real `.env`.

## Progress and verification (2026-11-09)

- Implemented section-aware parsing in `lib/monthly-report.cjs`, the executable `visualize-monthly-reports`, and self-contained rendering from `lib/monthly-dashboard.html`/`.js`.
- Implemented branch/report URL restoration, selector/link synchronization, graceful unknown selection fallback, hash-history navigation, print action, notice/item charts, registration/signup cards, branch context, and explicitly dated trends.
- Added `tests/monthly-visualizations.test.cjs` and integrated JavaScript syntax checks/Node tests into `./check`. Updated `README.md`, `AGENTS.md`, `.gitignore`, and `CHANGELOG.md`.
- Ran the script on the user-supplied report and generated `data/monthly-visualizations/index.html`: one report, 14 branches. The source remained unmodified. One warning identifies language counts that do not reconcile with system registered users.
- Passed 10 isolated Node tests covering parsing, malformed inputs, duplicate/corrected reports, output preservation/permissions, safe embedding, reporting-period assignment, URL restoration, and simulated navigation in a DOM/event harness.
- Passed Bash syntax checks and help smoke tests for all existing entrypoints plus the new script/`check`; passed JavaScript syntax checks and `git diff --check`.
- Attempted `./check`; it stopped with exit 127 because ShellCheck and Bats are not installed. The complete canonical suite still needs rerunning with those tools available. No live database/SFTP/monitoring checks were performed, and no real-browser visual/navigation or print inspection was available.

## Scope discussion (2026-11-10)

- The user narrowed v1 to the supplied October 2026 file and a polished, useful staff report that opens on overall information for all branches, with an optional specific-branch view.
- Created planned follow-ups T-003 for general period interpretation/trends and T-004 for library-system grouping. No grouping membership or default period rule has been inferred.
- The initial scope update changed planning only. After discussion of the staff-facing layout, the user explicitly approved beginning implementation; results are recorded below.

## V1 presentation implementation and verification (2026-11-10)

- Reworked `lib/monthly-dashboard.html`/`.js` as a warm-white, navy/teal staff briefing with responsive layouts and print styles. The default remains all branches; individual branch views retain URL selection and Back/Forward synchronization.
- Added five summary cards (hold notices, reminders, overdue notices, registered patrons, new signups), a notice total/breakdown and alphabetical branch comparisons, separate registration/signup charts with independent scales, and a distinct overdue-item section. Registrations are labeled snapshots; missing metrics remain unknown. Branch comparisons use a reported notice total or a sum only when all three components are present.
- Made system-wide keyword/registration context and source notes visible, including reconciliation warnings. Source renewal percentages remain in an expandable, denominator-unverified detail. Hide the report selector for a single report and hide trends without two assigned months; existing multi-input support remains intact.
- Generated `data/monthly-visualizations/index.html` from the supplied file with `--period 2026-10`. Verified 14 branches, 300 total notices (184 holds, 24 reminders, 92 overdue), 82 registered users, 12 signups, owner-only output permissions, and an unchanged source checksum. The one language-count warning remains visible. No general reporting-month rule was inferred.
- Expanded to 14 passing isolated Node tests, including actual generated-template ID wiring, default overview figures, alphabetical charts, branch-specific unknown/zero behavior, retained system context, and single-report/trend visibility. Passed JavaScript syntax checks for the entrypoint/parser/dashboard/tests, CLI help, and `git diff --check`.
- Attempted `./check`: Bash syntax checks passed, then it stopped with exit 127 because ShellCheck and Bats are still unavailable. No real-browser visual/navigation/print inspection or live-service checks were performed. No `.env`, download, upload, retention, or monitoring behavior changed.
- Updated `README.md`, `AGENTS.md`, and `CHANGELOG.md` for the implemented presentation and verification contracts. At that point T-003/T-004 remained planned and out of v1 scope; subsequent feedback on growth-focused reporting is recorded below.

## User feedback and pause (2026-11-10)

- The user found the progress-bar-style visualizations confusing and clarified that the primary purpose is to convey service usage month over month, including adoption, growth, or decline. The current visual design is not accepted.
- Discussed a replacement direction: registered-patron snapshots over time, monthly signups, source-reported keyword activity (system-wide, not unique active patrons), and notice volumes as supporting activity rather than proof of patron engagement. Consider line charts for several months and previous/current count comparisons with absolute/percentage changes for comparable data. Specific chart designs remain to be agreed and validated.
- Only October 2026 is currently available. The user will obtain historical reports in the same format. September plus October would enable an initial month-over-month comparison; several earlier months would provide more useful trends. Do not fabricate historical values, growth rates, or unique active-patron counts.
- The user explicitly approved shelving the work and marking T-002 blocked pending historical reports. Keep the existing parser, generated October baseline, and implementation intact; no further visualization changes were made after this feedback.

## Historical reports received and inspected (2026-11-12)

- The user supplied root-level `sb_report_August_2026_2bbb0dbd32_2026-11-10_16_02_39.csv`, `sb_report_September_2026_253c0de442_2026-11-10_16_02_39.csv`, and `sb_report_October_2026_2b3c0de4a2_2026-11-10_16_02_39.csv`, identifying them as August, September, and October reports. Their explicit month/year labels are separate from the November generation timestamp.
- Inspected all three without modifying them or regenerating the dashboard. Source-reported notice totals (holds + reminders + overdue) are 177, 272, and 241 respectively; registered users are 37, 71, and 81; new signups are 14, 35, and 12. These are source values, not fully validated comparable measures yet.
- August/September use equals-sign section separators, an additional CSV reminder-summary form, different branch-total/signup rows, successful-renewal counts, and (September) CSV registration summaries. The existing parser fails on both at the first system hold total because it does not recognize their section separators. October parses as 14 branches with the existing language-count warning. No code changes were made during this inspection.
- September includes an unattributed signup row of one patron. Preserve this as unattributed rather than inventing a branch or dropping it from reconciliation. Missing branch metrics still do not establish zero activity.
- The new October report differs from the earlier baseline: 241 versus 300 notices and 81 versus 82 registered users (both report 12 signups). Confirm which October source should be authoritative; do not silently mix or overwrite the earlier baseline.

## Resumption (2026-11-12)

The user explicitly approved resuming T-002 using the three `sb_report_` files, with the new October file replacing the earlier baseline. Status is now in-progress. Adapt parsing and provide growth-focused charts/comparisons; keep general date-convention work (T-003) and library grouping (T-004) deferred.

## Three-month implementation and verification (2026-11-12)

- Extended `lib/monthly-report.cjs` for equals/dot section headings, CSV/prose reminder aliases, both branch-total/signup forms, CSV registration totals, inline percentages, and successful renewal counts. Reminder aliases reconcile to one metric. Unattributed signups are preserved separately, included in reconciliation diagnostics, and never added again to source-reported system totals or assigned to a fabricated branch.
- Added opt-in `--named-periods` to read Month_YYYY activity labels in `sb_report_...` filenames. Generation dates are recorded separately; default assignment is still unconfirmed. This mode is mutually exclusive with `--period`/`--previous-month`, and `--previous-month` rejects named reports. Duplicate/conflicting-period checks remain in place. This narrow explicit-label support does not settle T-003's general date convention.
- Replaced progress-bar-style charts with SVG count line charts for enrollment snapshots, monthly signups, notices, and separately labeled system-wide keyword totals. Each chart has a zero-based count axis, exact-value/change table, and selected-report point outline; lines do not bridge missing values or calendar months. Registered counts are not labeled unique active users or adoption rates; keyword counts include test/administrative commands.
- Added three selected-month cards and alphabetical branch tables showing current values and absolute/percentage changes from the immediately prior calendar month only. Missing comparisons remain unavailable; percentage changes from zero are undefined (including 0 to 0). Branch/report URLs, Back/Forward, default overview, print action/styles, safe text rendering, and offline behavior remain intact.
- Generated `data/monthly-visualizations/index.html` with `./visualize-monthly-reports --named-periods sb_report_*.csv`, containing three ordered activity months and 14 distinct branches. Verified August/September/October system registered users 37/71/81, signups 14/35/12, notices 177/272/241, and system-wide keyword uses 39/46/17. The selected latest report is the newly approved October source (241 notices, not the previous 300-notice baseline).
- October-versus-September comparisons are +10 registered users (+14.1%), -23 signups (-65.7%), and -31 notices (-11.4%). These compare reported values, not a guaranteed fixed cohort or month-end population.
- The September signup without a branch remains one unattributed signup. Three source warnings are visible across the included reports: that row and September/October language totals that do not sum to registered users. No rows remain unrecognized in these three inputs.
- Verified unchanged input SHA-256 checksums, owner-only generated HTML permissions, and the embedded report periods/counts. No `.env`, download, upload, retention, monitoring, or notification state was accessed or changed.
- Passed 19 isolated Node tests (synthetic fixtures only), including all previous parser/CLI/navigation coverage, observed format variants, named months independent of common generation timestamps, duplicate/corrected reports, unattributed rows, zero-base changes, calendar gaps, SVG/table rendering, and three-month generated-template wiring. Passed JavaScript syntax checks, Bash syntax checks, all entrypoint help smoke tests, and `git diff --check`.
- Attempted `./check`; Bash syntax passed, then exit 127 reported missing ShellCheck and Bats. No real-browser visual/Back/Forward/print review or live integration checks were available. Updated `README.md`, `AGENTS.md`, and `CHANGELOG.md`; T-003/T-004 remain planned.

## Single-column simplification and verification (2026-11-13)

- The user clarified that metrics should flow one after another, not fill a screen, and approved retaining all other information below the three primary metrics.
- Reworked `lib/monthly-dashboard.html` into a plain white, single-column report with modest typography and simple separators. Removed cards, colored panels, and side-by-side metric layouts; there are no viewport-height or scroll-snap sections.
- Each primary metric now groups its heading, selected-month count/prior-month change, short definition, and chart. Registered patrons, signups, and notices appear in that order. Keyword uses and all exact-value tables, branch detail, notice/item breakdowns, registration totals, source percentages, warnings, and provenance follow under Additional information.
- Primary counts remain visible when periods are unconfirmed or there is only one assigned month; a short message replaces an unavailable trend. Keyword counts and charts remain explicitly system-wide in branch views.
- Regenerated `data/monthly-visualizations/index.html` from the three approved named reports. Compared the complete embedded dataset before/after and confirmed it is identical; input SHA-256 checksums and owner-only output permissions are unchanged. No parser, CLI, reporting-period, selection/history, or operational behavior changed.
- Passed 20 isolated Node tests, including new primary-before-secondary layout ordering, count/chart co-location, absence of cards/metric grids/full-screen sizing, relocated exact-value tables, and single/unconfirmed-month counts. Existing numeric, missing-value, SVG, generated-template, selection/history, and print-action tests still pass.
- Passed JavaScript syntax checks, visualization CLI help, and `git diff --check`. Attempted `./check`; Bash syntax passed, then missing ShellCheck/Bats caused exit 127. No real-browser appearance/navigation/print or live integration review was performed. Updated `README.md`, `AGENTS.md`, and `CHANGELOG.md`.

## Commit preparation (2026-11-13)

- The user requested staging the work and a recommended commit message. Staged 14 related files covering the dashboard entrypoint/parser/template, isolated tests, check integration, documentation/changelog, and linked task plans for one feature commit. `git diff --cached --check` passed; no commit was requested or created.
- Leave raw report CSVs, generated dashboards, `.agent-container`, and unrelated pre-existing task-workflow edits in `AGENTS.md` unstaged. Include only dashboard-related `AGENTS.md` changes.
- Implementation is ready for review/commit preparation. T-002 remains in-progress with **Awaiting user acceptance**; requesting staging is not explicit approval to close the task. T-003 and T-004 remain planned.

## Visual polish and verification (2026-11-13)

- The user confirmed that adding `--named-periods` resolves the same-generation-date conflict for the approved August–October files and that the single-column layout is much better. They then explicitly approved restrained visual polish, not task closure or a status change.
- The earlier implementation is now committed (`9f50036`); this polish was initially left unstaged. Preserved the unrelated pre-existing task-workflow edits in `AGENTS.md` and left raw CSVs/other untracked files alone.
- Refined the template with warm off-white paper, navy text, teal accents, larger headline counts, closer count/change/chart grouping, lighter chart gridlines, stronger series lines, outlined selected points, and selected-month axis-label emphasis. Controls have consistent sizing, keyboard-focus outlines remain visible, and numeric table headers/cells align right while source provenance remains left-aligned.
- Changes remain neutrally styled rather than green/red judgments. Preserved the single column, primary-before-secondary ordering, all supporting information, offline operation, and plain-white print styling. Removed only the leading separator before the now-stacked change text; parser, CLI, calculations, URL selection/history, and operational behavior are unchanged.
- Regenerated `data/monthly-visualizations/index.html` using the three approved named root reports. Verified the entire embedded dataset is identical to the prior output, all source SHA-256 checksums are unchanged, output permissions remain 0600, and all three activity months are included (14 branches). Existing unattributed-signup/language reconciliation warnings remain unchanged.
- Passed all 21 isolated Node tests (synthetic fixtures), JavaScript syntax checks for the entrypoint/parser/dashboard/tests, visualization CLI help, and `git diff --check`. New coverage checks neutral changes, numeric versus provenance alignment, selected-month highlighting through simulated history navigation, offline styles, and print rules.
- Attempted `./check`: Bash syntax passed, then exit 127 reported missing ShellCheck and Bats. No browser executable was available for visual/navigation/print inspection. No live services, real `.env`, or downloader/notification state were accessed. Updated `README.md`, the dashboard-specific `AGENTS.md` contract, and `CHANGELOG.md`.

## Polish commit preparation (2026-11-13)

- At the user's request, staged the seven polish-related source/test/documentation/plan files, including only the dashboard-specific hunk in `AGENTS.md`. Left unrelated task-workflow edits, raw CSVs, generated HTML, and `.agent-container` unstaged; `git diff --cached --check` passed. Suggested `style: polish monthly report presentation`; no commit or task closure was requested or performed.

## Approved layout refinements and verification (2026-11-13)

- The user approved tightening the header, improving mobile charts and the branch table, grouping supporting information, and using conversational change labels. Moving the chart explanation beside the charts was explicitly deferred; its existing location/text is unchanged. No status change, commit, staging, or task closure was requested.
- The previous polish is now committed (`1af1ec4`). These new refinements were initially left unstaged; unrelated pre-existing task-workflow edits in `AGENTS.md` and raw/untracked files were preserved.
- Combined the selected month/branch into a compact header and removed the redundant subtitle/separate branch heading. Preserved the single-column primary metric order, neutral styling, and count/change/chart grouping.
- Added mobile-specific SVG geometry, larger chart labels, separate month/year lines, and spaced labels for longer timelines. All points and exact table values remain included; resizing and selection/history updates re-render without altering the selected view or missing-value/calendar-gap semantics.
- Replaced the seven-column branch table with alphabetical branch row groups containing three metric rows and three wrapping columns (metric, count, change). Kept every count/change and clickable branch name; removed the forced 850px width and increased print legibility.
- Grouped supporting content under Activity details, Branch comparisons, and Sources & interpretation. Keyboard-accessible jump buttons focus/scroll to headings without changing the branch/report fragment or adding history entries; they are hidden when printing.
- Headline changes now read, for example, “10 more than September 2026 (+14.1%)” or “23 fewer than September 2026 (-65.7%).” Unchanged/missing/zero-base comparisons remain explicit, and tables keep their compact signed values. No parser, calculations, CLI, data, or operational behavior changed.
- Regenerated `data/monthly-visualizations/index.html` from the three approved named root reports. Verified the entire embedded dataset is identical, source SHA-256 checksums are unchanged, and output mode remains 0600; all three months and 14 branches remain included with the same three source warnings.
- Passed 26 isolated Node tests (synthetic fixtures), JavaScript syntax checks for the entrypoint/parser/dashboard/tests, visualization CLI help, and `git diff --check`. New tests cover compact header/grouping, jump focus/selection/history, mobile resizing, longer timelines, stacked branch counts, and conversational labels including unknown/zero-base values.
- Attempted `./check`: Bash syntax passed, then missing ShellCheck and Bats caused exit 127. No browser executable was available, so real-browser appearance/navigation/print inspection remains outstanding. No live services, real `.env`, or downloader/notification state were accessed. Updated `README.md`, `AGENTS.md`, and `CHANGELOG.md`.

## Layout refinement commit preparation (2026-11-13)

- At the user's request, staged the seven layout-related source/test/documentation/plan files, including only the dashboard-specific hunk in `AGENTS.md`. Left unrelated task-workflow edits, raw CSVs, generated HTML, and `.agent-container` unstaged; `git diff --cached --check` passed. No commit or task closure was requested or performed.

## Next step / acceptance

**Awaiting user acceptance.** Open the regenerated `data/monthly-visualizations/index.html` in a browser and review the compact header, mobile charts, stacked branch comparisons, supporting-section jumps, and conversational headline changes, including all-branches/branch views, month selection, Back/Forward navigation, and printing. Review the staged source changes and rerun `./check` with Bats and ShellCheck installed. The chart explanation remains in its existing location; no further period or library-grouping rules are inferred.

Keep T-002 in-progress until the user explicitly approves closing it. No task closure or archive has been approved.
