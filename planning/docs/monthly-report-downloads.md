# T-001: Download Shoutbomb monthly reports

- Created: 2026-11-05
- Status: in-progress
- Awaiting user review/confirmation. Local implementation and mocked validation are ready for review; the user has not confirmed completion. Deployment/live validation remains an operator step.

## Goal and decisions

Poll Shoutbomb daily for monthly statistics CSVs over the existing SFTP connection, save complete files locally, and leave processing to a later, separate service. Shoutbomb typically publishes within the first week of each month.

Remote directory: `/monthly_report`.
Example filename: `sb_generate_monthly_report_feb88521e8_2026-11-05_00_10_18.csv`.
The identifier is opaque; it is not hard-coded. The filename timestamp is not interpreted as the CSV's reporting period.

The user confirmed that a newly downloaded file dated in the current calendar month counts as a new arrival. Historical and future-month backfills do not count. Calendar-month classification uses the system timezone or `TZ` loaded from project-root `.env`.

Two independent Healthchecks.io checks distinguish polling failure from a missing monthly report:

- Daily polling: start/success/failure lifecycle; a successful poll with no new files is success.
- Monthly arrival: success only for completed eligible downloads. Configure the monthly schedule, timezone, and overdue grace in Healthchecks.io, not in the downloader. The 10th is an example deadline, not a hard-coded rule.

## Implemented interfaces

- Root entrypoint: `./download-monthly-reports`.
- Monitored wrapper: `./services/download-monthly-reports`, reusing the unchanged `services/lib/monitored-job.sh`.
- Local destination: `data/monthly-reports/`, ignored by Git and outside existing top-level upload/retention scans.
- Both entrypoints accept `--host`, `--port`, and `--verbose` (`-H`, `-P`, `-v`). The root script owns downloader validation and transfer behavior.
- The service requires `--healthcheck-url-env HEALTHCHECKS_*_URL`; example setting: `HEALTHCHECKS_MONTHLY_DOWNLOAD_URL`.
- Optional `--arrival-healthcheck-url-env HEALTHCHECKS_*_URL` selects a distinct monthly check; example setting: `HEALTHCHECKS_MONTHLY_ARRIVAL_URL`. Identical resolved daily/arrival URLs are rejected before pings or downloads.
- Logger tag: `shoutbomb-download-monthly-reports`; configurable logger seam and best-effort daily lifecycle remain shared with existing services.
- Root statuses: 0 success/no-op; 1 configuration, locking, listing, receipt, transfer, or publication failure; 2 usage error; 127 missing SFTP. The service preserves download/logger pipeline status; arrival notification failures do not replace it.

## Download and filesystem behavior

Reuse existing SSH credentials, strict host-key checking, and script-relative project-root `.env` loading. Accept only the expected filename prefix, safe opaque identifier (ASCII letters/digits/underscores/hyphens), and timestamp suffix; ignore other entries. Quote SFTP batch paths and reject line breaks in project paths.

Download every missing matching file, including historical files on first run, preserving remote basenames. Skip existing regular files by filename; reject symlink/directory destination collisions. Published filenames are assumed immutable, and remote files are never changed. No CSV schema validation or automatic local deletion is performed.

Stage transfers in destination `.download.lock/` and atomically rename completed files. Owner-only creation permissions keep downloads private. Individual failures clean partial transfers and do not prevent attempting other files; subsequent runs retry missing files. Exclusive directory locking prevents overlapping downloads. Normal exits and HUP/INT/TERM clean staging/lock; crashes/forced kills may require operator removal of a stale lock after verifying no downloader remains active.

## Durable results and arrival notifications

With arrival monitoring enabled, the wrapper supplies the root script's `--receipt-dir` option, using `data/monthly-reports/.arrival-state/pending/`.

The result contract is one receipt per new basename, containing its download month as `YYYY-MM`. Persist the receipt before CSV publication so a crash immediately after publication cannot lose the result. A receipt is not sufficient evidence by itself: consumers also require the corresponding completed regular, non-symlink CSV. Receipt errors prevent publication and fail that download. Existing CSVs do not generate new receipts; ordinary manual downloads without receipts do not retroactively count upon enabling monitoring.

The wrapper batches eligible receipts into one arrival success ping. A successful eligible download counts even if another transfer or the logging pipeline failed; daily status still reflects that independent failure. Additional newly downloaded eligible files can notify again in the same month.

Missing curl or failed pings leave receipts for retry during the same calendar month, even on a no-new-file or failed-listing run. A successful ping removes only the acknowledged batch. Historical/future filename-month mismatches and expired previous-month retries are discarded without pinging. Old receipts cannot mask a missing arrival next month. Crash recovery may repeat a ping after remote success but before local receipt cleanup; best-effort delivery is not exactly-once.

Notification uses a separate `.arrival.lock/`; contention defers notification without changing daily status. Normal exits/signals clean the lock; stale-lock recovery requires verifying no service is active. Notification state is separate from future processing state and must not be removed merely because a file is processed.

## Implementation and acceptance checklist

- [x] Implement standalone discovery, safe matching/quoting, deduplication, download, atomic publication, cleanup, overlap protection, help, configuration, and statuses.
- [x] Expose durable machine-readable completed-file evidence without parsing human logs or conflating new files with exit success.
- [x] Implement daily wrapper and optional distinct monthly check, including backfill filtering, partial-success handling, same-month retries, expiry, and notification locking.
- [x] Keep existing generation/upload/retention scripts and the shared monitoring helper unchanged; preserve existing service behavior.
- [x] Extend `check`, mocks, fixtures, help smoke tests, and isolated Bats behavior tests for daily and monthly paths.
- [x] Document CLI/configuration, retention boundaries, calendar-month monitoring setup, daily cron, recovery, and live validation limits in `README.md`, `.env.example`, and `AGENTS.md`.
- [x] Record implemented changes under 2026-11-05 in `CHANGELOG.md`.
- [ ] User reviews the implementation and explicitly confirms completion before this task is marked `done`.

## Validation and progress

2026-11-05 first slice: implemented downloader/daily service and 20 new behavior tests. Required syntax/help commands, ShellCheck, and all 55 Bats tests passed. Existing user edits to planning instructions were preserved.

2026-11-05 second slice: user accepted the current-month filename arrival proxy. Added durable receipts, separate monthly URL selection, retry/expiry behavior and locking, and 14 further behavior tests. Validation uses Bats-core 1.12.0 and ShellCheck 0.10.0 installed in `/tmp`, as the base environment lacks those tools. Final syntax/help checks, `./check` (69 tests), and `git diff --check` passed.

2026-11-06 review handoff: reran syntax/help checks and `./check`; ShellCheck and all 69 mocked tests passed. Prepared branch `feature/monthly-report-downloads` with the related changes staged, not committed, at the user's request. The unrelated `.agent-container` file remains unstaged. T-001 remains in-progress awaiting user review/confirmation.

All behavioral checks use temporary project trees, generated files, and fake SFTP/curl/date/logger commands. The real `.env`, working CSVs, production SFTP, and Healthchecks.io were not accessed. No claim of live integration validation is made.

## Operational handoff / remaining external checks

Next step: user review and explicit confirmation, addressing any requested changes before marking this task `done`. Passing local checks does not constitute user acceptance.

Before deployment, the operator must:

1. Verify the SFTP-visible `/monthly_report` path, filename family, and access using deployment credentials; confirm whether filenames can be reused. The implemented policy preserves existing local copies if remote contents change under the same name.
2. Configure distinct daily and monthly Healthchecks.io URLs in the real `.env` and enable the arrival option in daily cron. Use the intended system/`TZ` timezone for both classification and monitoring.
3. Choose the calendar-month schedule/grace (for example, the 1st with nine days' grace for a deadline around the 10th), verify the monitoring UI's next deadline and early-arrival handling, and avoid a fixed 30-day interval.
4. Validate complete transfers, separate daily lifecycle/current-month arrival, historical backfill/no-op behavior, and failed-ping retry using designated test checks before production rollout.

CSV processing/transformation, a downstream processing service, automatic retention, and remote deletion remain out of scope and need separate work if requested.

## References

[Repository instructions](../../AGENTS.md), [upload conventions](../../upload), [service example](../../services/archive-reports), [monitoring helper](../../services/lib/monitored-job.sh), [historical monitoring design](../../notes/monitored-services-design-2026-08-21.md), and [current operator documentation](../../README.md#download-monthly-statistics).
