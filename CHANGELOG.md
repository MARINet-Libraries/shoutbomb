# Changelog

## 2026-11-05

- Added `download-monthly-reports` to fetch missing statistics CSVs from SFTP `/monthly_report` into `data/monthly-reports/`, including historical files. Downloads preserve filenames, skip existing regular files, publish atomically, and use an exclusive lock; remote files and existing upload/retention behavior are unchanged.
- Added `services/download-monthly-reports` with best-effort daily Healthchecks.io lifecycle monitoring and the `shoutbomb-download-monthly-reports` logger tag. No-new-file runs succeed; optional `--arrival-healthcheck-url-env` selects a distinct check for newly downloaded files dated in the current calendar month (system/`.env` `TZ` timezone), leaving overdue deadlines to monitoring.
- Added durable basename/download-month receipts via `--receipt-dir` and separate monthly notification state/locking. Failed arrival pings retry within the same month without redownloading or changing daily workflow status; expired retries and historical/future backfills never reset the monthly check.
- Extended `./check`, isolated mocks, and behavioral tests for downloads and daily/monthly monitoring; documented configuration, calendar-month scheduling, daily cron, and recovery behavior.

## 2026-09-08

- Consolidated shared environment loading, array membership, and missing-variable collection in `lib/common.sh`. Report generation, upload, retention, and monitoring behavior remain unchanged.
- Added mocked coverage for shared environment-loading failures and archive dry-run collision handling. `./check` now includes the shared library.
