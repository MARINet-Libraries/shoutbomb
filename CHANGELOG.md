# Changelog

## 2026-11-13

- Simplified the monthly report to a plain, single-column layout with registered patrons, signups, and notices stacked vertically, each with its count, prior-month change, and chart. Moved keyword usage, exact-value tables, branch/detail tables, and source notes below the primary metrics; removed cards and metric columns without changing report data, CLI behavior, or URL selection.
- Keep primary counts visible when there are too few assigned months to chart a trend. Added layout-order coverage and updated isolated summary/single-report tests; printable overall/branch views remain available.

## 2026-11-12

- Extended monthly-report parsing for equals-sign headings, CSV/prose reminder and registration/signup variants, successful renewal counts, and inline source percentages. Unattributed signups are preserved separately with warnings; missing values remain unknown and repeated summaries are not extra activity.
- Added opt-in `--named-periods` for `sb_report_Month_YYYY_...` inputs, assigning their explicit month labels independently of generation timestamps; period modes are mutually exclusive and conflicting same-period reports still fail. Default period inference and downloader/upload/retention/monitoring behavior are unchanged.
- Replaced progress-bar-style views with monthly count line charts, exact-value tables, and current/prior-month changes for enrollment snapshots, signups, notices, and separately labeled system-wide keyword activity. Comparisons require the preceding calendar month and both values, zero-base percentage changes remain undefined, and lines do not bridge gaps; branch/report URLs, print views, and offline operation are preserved.
- Expanded isolated tests for historical-format variants, named periods, unattributed signups, three-month template rendering, missing/zero values, and calendar-gap comparisons.

## 2026-11-10

- Refined the offline monthly dashboard into a staff briefing with an all-branches default, five summary cards, alphabetical branch notice comparisons, separate registration/signup charts, distinct overdue-item counts, and printable overall/branch views. Added readable month headings and visible source warnings; single-report selectors and trends without two assigned months are hidden. Parser, CLI period assignment, source counts, and download/upload/monitoring behavior are unchanged.
- Expanded isolated dashboard tests to cover overview figures, alphabetical charts, missing versus zero values, persistent system-wide context, and generated-template wiring for an explicitly assigned October report.

## 2026-11-09

- Added `visualize-monthly-reports` (Node.js 18+, no npm dependencies) to generate an offline HTML dashboard with URL-synchronized branch/report selection, printable summaries, notice/item charts, registrations, branch comparisons, and explicitly dated monthly trends. Output defaults to `data/monthly-visualizations/index.html` and is published atomically with owner-only permissions; no existing download, upload, retention, or monitoring behavior changes.
- Added section-aware monthly-report parsing with reminder-summary deduplication, registration-only branches, missing-value preservation, and source-quality warnings. Reporting months require explicit `--period` or `--previous-month`; duplicate reports are skipped and conflicting corrections fail without replacing existing output.
- Added isolated Node parser/CLI/navigation tests and JavaScript checks to `./check`, which now also requires Node.js; documented the CLI, privacy/interpretation limits, and generated output location.

## 2026-11-05

- Added `download-monthly-reports` to fetch missing statistics CSVs from SFTP `/monthly_report` into `data/monthly-reports/`, including historical files. Downloads preserve filenames, skip existing regular files, publish atomically, and use an exclusive lock; remote files and existing upload/retention behavior are unchanged.
- Added `services/download-monthly-reports` with best-effort daily Healthchecks.io lifecycle monitoring and the `shoutbomb-download-monthly-reports` logger tag. No-new-file runs succeed; optional `--arrival-healthcheck-url-env` selects a distinct check for newly downloaded files dated in the current calendar month (system/`.env` `TZ` timezone), leaving overdue deadlines to monitoring.
- Added durable basename/download-month receipts via `--receipt-dir` and separate monthly notification state/locking. Failed arrival pings retry within the same month without redownloading or changing daily workflow status; expired retries and historical/future backfills never reset the monthly check.
- Extended `./check`, isolated mocks, and behavioral tests for downloads and daily/monthly monitoring; documented configuration, calendar-month scheduling, daily cron, and recovery behavior.

## 2026-09-08

- Consolidated shared environment loading, array membership, and missing-variable collection in `lib/common.sh`. Report generation, upload, retention, and monitoring behavior remain unchanged.
- Added mocked coverage for shared environment-loading failures and archive dry-run collision handling. `./check` now includes the shared library.
