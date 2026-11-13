# AGENTS.md

## Project map and upkeep

- `CHANGELOG.md`: concise, date-ordered record of implemented changes; keep it current as changes land and include it in every release.
- `sql/*.sql`: standalone Sierra/PostgreSQL report queries.
- `generate-reports`, `upload`, `archive-reports`: canonical CSV export, SFTP upload, and retention entrypoints.
- `download-monthly-reports`: canonical SFTP monthly-statistics downloader; writes only under `data/monthly-reports/`.
- `visualize-monthly-reports`: Node.js 18+ offline dashboard entrypoint; parses explicit local inputs with `lib/monthly-report.cjs` and embeds `lib/monthly-dashboard.html`/`.js`, defaulting output to `data/monthly-visualizations/index.html`. Opens on a plain single-column report: registered patrons, new signups, and notices each have their count/change/chart together; keyword activity and all supporting tables/source notes follow below. Compact month/branch header, off-white/navy/teal styling, larger headline counts, neutral conversational headline changes, mobile chart geometry/labels, and right-aligned numeric tables; no cards, side-by-side metric columns, or forced full-screen sections. Supporting information is grouped into activity details, stacked three-column branch comparisons, and sources/interpretation, with jump controls that preserve branch/report fragments. All-branches and optional branch views remain printable on plain white. No `.env`, network, or downloader/notification state access.
- `lib/common.sh`: narrow namespaced helpers for `.env` loading, array membership, and missing-variable collection; keep domain validation in its owning scripts.
- `services/`: three monitored cron entrypoints; all use `services/lib/monitored-job.sh`.
- `check` and `tests/`: canonical local Bash/JavaScript static checks, fully mocked Bats behavior tests, and isolated Node dashboard tests (`tests/monthly-visualizations.test.cjs`); requires Bats-core, ShellCheck, and Node.js 18+.
- `notes/`: point-in-time caveats, history, and deferred designs. Check their status/date against current code and `CHANGELOG.md`.
- `data/`, `data/_archive/`, `data/monthly-reports/`, and `data/monthly-visualizations/`: generated/downloaded artifacts, never source-of-truth logic.
- `.env.example`: configuration template; the real ignored `.env` may contain secrets.
- Keep this file current when layout, interfaces, configuration, validation, or workflows change. Document implemented behavior, not proposals.

## Changelog and releases

- Before completing an implementation task, ensure every notable change is recorded under a `## YYYY-MM-DD` heading in `CHANGELOG.md`; add the current date at the top when needed and do not add proposals.
- Keep each change to a concise bullet of no more than a couple of sentences, with the newest dates first, and include the updated changelog in every release.
- Do not edit dated files under `notes/` solely to record implementation status or release history. Update a note only when its design or caveat content itself changes.

## Guardrails

- Assume no live PostgreSQL/Sierra, SSH/SFTP, remote server, or Healthchecks.io access. Never claim query, upload, or monitoring validation unless performed.
- Scripts needing configuration resolve the project-root `.env` from their own location. Do not inspect, modify, or commit it unless explicitly requested.
- Never add real secrets or private values to `.env.example`, code, docs, or logs. Preserve intentional public defaults; otherwise use placeholders and `.env` settings.
- Tests must use temporary project fixtures and fake configuration; never let routine tests read the real `.env`, inspect working CSVs, write to real syslog, or contact live services.
- Preserve report, output, upload, retention, and monitoring behavior unless the task requests a change.
- Do not inspect generated CSVs unless the task concerns output. Do not run non-dry-run retention merely for validation.

## Read minimally

- Single-report work: read its `sql/<name>.sql` and specifically referenced caveat notes only.
- Export work: read `generate-reports`; upload work: read `upload` (its supported-report/destination mapping is canonical).
- Monthly-download work: read `download-monthly-reports` and the linked plan in `planning/TASKS.md`; published filenames currently deduplicate downloads, not report contents.
- Monthly-visualization work: read `visualize-monthly-reports`, `lib/monthly-report.cjs`, `lib/monthly-dashboard.html`/`.js`, and the linked plan in `planning/TASKS.md`; use synthetic fixtures for routine tests. Reporting months require explicit `--period`, legacy `--previous-month`, or opt-in `--named-periods` for `sb_report_Month_YYYY_...` labels (not generation dates). The parser supports dot/equals headings and prose/CSV variants; preserve unattributed signups separately without inventing a branch or adding them again to source totals. Missing metrics stay unknown, repeated summaries are not extra activity, and notice/item counts remain separate. Compare only the immediately prior calendar month when both values exist; percentages from a zero base are undefined, and chart lines must not bridge absent values/months. Registration snapshots and system-wide keyword uses are not adoption rates or unique active-user counts. Preserve branch/report URL fragments and Back/Forward synchronization; selection is not access control over the embedded dataset.
- Retention work: read `archive-reports`; consult `notes/archive-reports-design-2026-05-01.md` for semantic changes or rationale.
- Monitoring work: read the affected `services/` entrypoint and shared helper; for non-trivial changes also read `notes/monitored-services-design-2026-08-21.md`.
- Configuration, dependency, CLI, or cron changes: read `.env.example` and relevant `README.md` sections.
- Treat proposal, plan, and historical notes as context, not current requirements.

## SQL changes

- Keep one runnable, preferably direct `SELECT` query per file. Avoid `psql` meta-commands, transaction control, and unsupported session setup.
- Follow nearby style: uppercase keywords, clear joins/aliases, and one selected expression per line when practical.
- Preserve column names/order, filtering, aggregation, and sorting unless requested; use explicit `ORDER BY` when determinism matters.
- For `overdue.sql` or `renew.sql`, first read `notes/hold-count-aggregation-issue.md`. For due-window changes, also read the applicable `notes/*-window-change-2026-04-29.md`. For broader refactors, check `notes/sql-query-review-2026-04-24.md` against current SQL.
- Record SQL semantic and downstream-impact changes in `CHANGELOG.md`; update a note only when its active caveat or design guidance changes.

## Shell changes

- Keep Bash readable and safe. Preserve defaults, argument pass-through, exit statuses, and script-relative path resolution unless requested.
- Root entrypoints must remain independently usable; monitored services orchestrate rather than duplicate their logic.
- `generate-reports` discovers `sql/*.sql`; `upload` owns upload support/destinations; `archive-reports` owns retention validation.
- Configuration changes require matching help, `.env.example`, and `README.md` updates. `.env` must remain valid Bash input.
- After shell changes, run:

  ```bash
  for f in generate-reports upload archive-reports download-monthly-reports lib/common.sh services/generate-and-upload services/archive-reports services/download-monthly-reports services/lib/monitored-job.sh; do bash -n "$f"; done
  for f in generate-reports upload archive-reports download-monthly-reports services/generate-and-upload services/archive-reports services/download-monthly-reports; do "./$f" --help >/dev/null; done
  ```

- With Bats-core and ShellCheck installed, also run `./check` after shell or test changes.

## Operational contracts

### Reports

- A SQL basename is its CLI report name and generated filename prefix. Generation auto-discovers reports; upload support is explicit.
- When adding/removing/renaming reports, update `upload` if applicable, help text, the `README.md` inventory, `CHANGELOG.md`, and documented service/cron lists. Keep generation-only reports out of upload lists.

### Retention

- Use fixed top-level paths `data/*.csv` and `data/_archive/*.csv`; age comes from the trailing `-<epoch>.csv`, not mtime.
- With both operations, delete archived files before archiving active ones; collisions overwrite with a warning. Preserve non-destructive `--dry-run` and schedule retention after upload/review.
- Test file operations in an isolated fixture, not against working artifacts.

### Monthly downloads

- Poll SFTP `/monthly_report` and save all missing matching CSVs under their original basenames in `data/monthly-reports/`, including historical files. Skip existing regular files; do not modify remote files or automatically prune local downloads.
- Publish downloads atomically from the destination's `.download.lock/` staging directory. Lock contention fails; normal exits/signals clean up, while crash recovery requires verifying no run is active before removing a stale lock.
- Daily polling success includes no-new-file runs; do not present daily success as proof of a monthly report's arrival.
- With `--arrival-healthcheck-url-env HEALTHCHECKS_*_URL`, the service sends a separate arrival success only for completed new downloads whose filename month matches their download month and the current system/`.env` `TZ` month. Historical/future backfills and existing files do not count; overdue deadlines belong in monitoring.
- The service owns `.arrival-state/pending/` notification receipts and `.arrival.lock/` under `data/monthly-reports/`. The root downloader's `--receipt-dir` records basenames/download months before CSV publication, so consumers must also require a completed CSV. Retry failed pings within the same month; expire old receipts without pinging. Keep notification and future processing state separate.

### Monitoring

- `services/generate-and-upload` uploads only after successful generation; generation/upload lists are independent pass-through arguments. `services/archive-reports` passes retention arguments through.
- Each invocation requires `--healthcheck-url-env HEALTHCHECKS_*_URL`; keep the private URL out of arguments and logs.
- Preserve logger tags `shoutbomb-generate-reports`, `shoutbomb-upload`, `shoutbomb-archive-reports`, and `shoutbomb-download-monthly-reports`; do not add duplicate logger wrappers to cron examples. `SHOUTBOMB_LOGGER_PATH` defaults to `/usr/bin/logger` and exists so isolated tests can substitute a fake logger.
- Healthchecks.io lifecycle pings are best-effort and never replace workflow status. Shared-helper changes require validating all three services.

## Changes to call out

Explicitly identify changes to output schema/rows/order, report names/files/timestamps/headers, upload selection/support/destinations, retention semantics, CLI/config/exit behavior, logger tags, monitoring lifecycle, or generation-to-upload gating. Record implemented changes in `CHANGELOG.md`; update `README.md` and `.env.example` wherever their documented contracts change.

## Validation limits

- Local validation may cover syntax, help, arguments, isolated filesystems, and mocked commands. `./check` is the canonical local entrypoint.
- Live query, upload, and monitoring checks require their respective environments and credentials. Never ping production checks during routine tests.
- State exactly what ran; distinguish static/mocked checks from live integration validation.

<!-- tasks:planning:start -->
## Task planning

Use `planning/TASKS.md` for work the user wants to return to later, not as a log of every request. If work is likely to span sessions, has unresolved decisions or blockers, or is being left unfinished with next steps, ask the user whether to track it before adding a task. Do not ask for routine, self-contained changes. If the user explicitly asks to track work or resume an existing task, proceed without asking again.

When tracking or resuming a task, read and follow [the planning workflow](planning/WORKFLOW.md). Each task links to one plan in `planning/docs/`.

Only mark a task `done` after the user explicitly approves closing that task. When implementation and verification are finished, leave it `in-progress`, record “Awaiting user acceptance” in the plan, summarize the results, and ask whether to mark it done. Approval to perform work is not approval to close the task. This approval requirement also applies if an older project workflow says to mark completed work done automatically.
<!-- tasks:planning:end -->
