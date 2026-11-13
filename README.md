# shoutbomb

Exports Sierra/PostgreSQL report data to CSV, uploads selected CSVs to Shoutbomb over SFTP, and downloads Shoutbomb monthly statistics CSVs.

## Index

- [Find the right file fast](#find-the-right-file-fast)
- [Quick start](#quick-start)
- [What each script does](#what-each-script-does)
- [Where things live](#where-things-live)
- [Setup](#setup)
- [Common tasks](#common-tasks)
  - [Generate reports](#generate-reports)
  - [Upload reports](#upload-reports)
  - [Download monthly statistics](#download-monthly-statistics)
  - [Visualize monthly statistics](#visualize-monthly-statistics)
  - [Run the monitored generate-and-upload workflow](#run-the-monitored-generate-and-upload-workflow)
  - [Archive old files](#archive-old-files)
  - [Show help](#show-help)
- [Local validation and tests](#local-validation-and-tests)
- [Report inventory](#report-inventory)
- [Cron structure](#cron-structure)
- [Troubleshooting](#troubleshooting)
  - [Grep syslog by shoutbomb tag](#grep-syslog-by-shoutbomb-tag)
  - [Follow logs live](#follow-logs-live)
  - [Use journalctl on journald systems](#use-journalctl-on-journald-systems)
  - [Common failure points](#common-failure-points)
- [Changelog and releases](#changelog-and-releases)
- [Notes and caveats](#notes-and-caveats)

## Find the right file fast

If you are trying to find where something lives:

| If you need to... | Start here |
| --- | --- |
| change report SQL | `sql/*.sql` |
| generate CSVs from SQL | `./generate-reports` |
| change upload behavior or destinations | `./upload` |
| download Shoutbomb monthly statistics | `./download-monthly-reports` |
| visualize monthly statistics for branch staff | `./visualize-monthly-reports` |
| run or change monitored cron workflows | `services/` |
| archive or prune old CSVs manually | `./archive-reports` |
| run monitored archive maintenance | `services/archive-reports` |
| change shared low-level shell helpers | `lib/common.sh` |
| review implemented or release-ready changes | `CHANGELOG.md` |
| run local static and mocked checks | `./check` and `tests/` |
| inspect generated output | `data/` |
| read project-specific caveats or history | `notes/` |
| copy a starter config | `.env.example` |

## Quick start

```bash
cp .env.example .env
# edit .env with your database and SSH settings
./generate-reports
# review files in ./data
./upload
```

## What each script does

| Script | Purpose |
| --- | --- |
| `./generate-reports` | Runs every `sql/*.sql` file by default and writes CSVs to `data/` |
| `./upload` | Uploads the latest supported CSVs from `data/` to Shoutbomb |
| `./download-monthly-reports` | Downloads missing monthly statistics CSVs into `data/monthly-reports/` |
| `./visualize-monthly-reports` | Parses monthly statistics into an offline HTML dashboard with bookmarkable branch views |
| `./services/download-monthly-reports` | Runs daily download polling with logging and Healthchecks.io monitoring |
| `./services/generate-and-upload` | Runs a generate/upload cron workflow with logging and Healthchecks.io monitoring |
| `./archive-reports` | Moves older CSVs from `data/` into `data/_archive/` and deletes sufficiently old archived CSVs |
| `./services/archive-reports` | Runs archive maintenance with logging and Healthchecks.io monitoring |
| `./check` | Runs Bash/JavaScript syntax checks, ShellCheck, fully mocked Bats behavior tests, and isolated dashboard tests |

Typical workflow:

1. add or update a report in `sql/`
2. run `./generate-reports`
3. review the output in `data/`
4. run `./upload` if you want to send the latest files to Shoutbomb
5. run `./archive-reports` separately when you want to archive or prune older generated files

## Where things live

```text
.
├── .env.example
├── CHANGELOG.md
├── generate-reports
├── upload
├── archive-reports
├── download-monthly-reports
├── visualize-monthly-reports
├── check
├── lib/
│   ├── common.sh
│   ├── monthly-report.cjs
│   ├── monthly-dashboard.html
│   └── monthly-dashboard.js
├── tests/
├── services/
│   ├── generate-and-upload
│   ├── archive-reports
│   ├── download-monthly-reports
│   └── lib/
│       └── monitored-job.sh
├── sql/
├── data/
├── notes/
└── README.md
```

## Setup

### Requirements

You will need:

- Bash
- `psql` on your `PATH`
- `sftp` on your `PATH`
- network access to the PostgreSQL/Sierra database
- SSH/SFTP access to the Shoutbomb server
- `curl` for Healthchecks.io monitoring of the cron workflow
- `/usr/bin/logger` for cron workflow logging, unless `SHOUTBOMB_LOGGER_PATH` selects another executable
- an SSH private key for uploads and monthly downloads
- a trusted SSH host key in `known_hosts` or an alternate `known_hosts` file

The offline visualization script additionally requires **Node.js 18 or newer** and a browser with JavaScript enabled. It has no npm dependencies and needs none of the database, SSH, monitoring, or `.env` configuration above. `./check` also requires Node.js for dashboard tests.

### Configure `.env`

Copy the example file:

```bash
cp .env.example .env
```

Then edit `.env` with real values.

#### Required for report generation

- `PGHOST`
- `PGPORT`
- `PGDATABASE`
- `PGUSER`
- `PGPASSWORD`

#### Required for upload and monthly downloads

- `SSH_USERNAME`
- `SSH_IDENTITY_FILE` (absolute path)

#### Required for monitored service jobs

Define one full, private Healthchecks.io ping URL for each independently scheduled workflow. The service invocation selects the appropriate variable with `--healthcheck-url-env`. Variable names must match `HEALTHCHECKS_*_URL`.

For example:

- `HEALTHCHECKS_PRIMARY_REPORTS_URL`
- `HEALTHCHECKS_RENEWALS_URL`
- `HEALTHCHECKS_ARCHIVE_URL`
- `HEALTHCHECKS_MONTHLY_DOWNLOAD_URL` (daily polling only)
- `HEALTHCHECKS_MONTHLY_ARRIVAL_URL` (separate monthly check, selected by the optional `--arrival-healthcheck-url-env` service option)

#### Optional for monitored service jobs

- `SHOUTBOMB_LOGGER_PATH` (defaults to `/usr/bin/logger`; primarily useful for isolated tests)
- `TZ` (optional system timezone override for monthly-arrival classification; match the monthly check's timezone)

#### Optional for upload and monthly downloads

- `SSH_HOST` (defaults to `ftp.shoutbomb.com`)
- `SSH_PORT` (defaults to `22`)
- `SSH_KNOWN_HOSTS_FILE` (absolute path)

Example:

```dotenv
PGHOST=hostname
PGPORT=5432
PGDATABASE=database_name
PGUSER=username
PGPASSWORD=secret

HEALTHCHECKS_PRIMARY_REPORTS_URL=https://hc-ping.com/your-primary-reports-check-uuid
HEALTHCHECKS_RENEWALS_URL=https://hc-ping.com/your-renewals-check-uuid
HEALTHCHECKS_ARCHIVE_URL=https://hc-ping.com/your-archive-check-uuid
HEALTHCHECKS_MONTHLY_DOWNLOAD_URL=https://hc-ping.com/your-monthly-download-check-uuid
HEALTHCHECKS_MONTHLY_ARRIVAL_URL=https://hc-ping.com/your-monthly-arrival-check-uuid
# Optional; otherwise the system timezone determines the current calendar month:
# TZ=Etc/UTC

# Optional; monitored services default to /usr/bin/logger:
# SHOUTBOMB_LOGGER_PATH=/usr/bin/logger

SSH_HOST=ftp.shoutbomb.com
SSH_PORT=22
SSH_USERNAME=your_username
SSH_IDENTITY_FILE=/full/path/to/private_key
# Optional:
# SSH_KNOWN_HOSTS_FILE=/full/path/to/known_hosts
```

## Common tasks

### Generate reports

Run all reports:

```bash
./generate-reports
```

Run only selected reports:

```bash
./generate-reports --reports holds renew
```

Run without headers:

```bash
./generate-reports --no-headers
```

Useful to know:

- every `sql/*.sql` file is generated by default
- output files are written to `data/`
- filenames look like `data/<report-name>-<epoch>.csv`
- headers are included unless you pass `--no-headers`

### Upload reports

Upload the latest supported report files:

```bash
./upload
```

Upload only selected supported reports:

```bash
./upload --reports holds overdue
```

Supported upload report names:

| Report name | Remote directory |
| --- | --- |
| `holds` | `/Holds` |
| `renew` | `/Renew` |
| `overdue` | `/Overdue` |
| `text-patrons` | `/text_patrons` |

Useful to know:

- use report basenames like `holds`, not filenames like `holds.sql`
- `./upload` looks for the latest matching CSV in `data/`
- strict SSH host key checking is always enabled
- remote destination directories must already exist
- not every generated report is uploadable; use the supported names above

### Download monthly statistics

Run manually, or use the daily monitored wrapper:

```bash
./download-monthly-reports
./services/download-monthly-reports \
  --healthcheck-url-env HEALTHCHECKS_MONTHLY_DOWNLOAD_URL \
  --arrival-healthcheck-url-env HEALTHCHECKS_MONTHLY_ARRIVAL_URL
```

The downloader lists SFTP `/monthly_report` using the existing SSH credentials and strict host-key checking. It accepts basenames of the form `sb_generate_monthly_report_<identifier>_YYYY-MM-DD_HH_MM_SS.csv`; the identifier may contain ASCII letters, digits, underscores, and hyphens. Other entries are ignored. The filename timestamp is not interpreted as the reporting period.

Files are saved under their original names in `data/monthly-reports/`. All missing matching files are downloaded, including historical files on the first run. Existing regular files are skipped by filename, even if their remote contents change; published filenames are assumed immutable until Shoutbomb confirms its correction policy. Remote files are never modified. No CSV schema or reporting-period validation is performed.

Each transfer is staged under `data/monthly-reports/.download.lock/` and atomically renamed after SFTP reports success. Failed transfers are removed and retried next run; other files continue downloading. Completed files are created with owner-only permissions. Existing upload and archive scripts do not scan this subdirectory; downloads are retained without automatic deletion and must remain here for filename-based deduplication. Future processing is separate from downloading.

A successful listing with no new files returns zero. Configuration, listing, transfer, publication, or lock failures return 1; usage errors return 2; missing `sftp` returns 127. The summary reports downloaded/skipped/ignored/failed entry counts. `--host`, `--port`, and `--verbose` (or `-H`, `-P`, `-v`) work on both entrypoints; the root script validates downloader arguments. The service preserves the logger pipeline's status, as existing services do.

Overlapping runs fail rather than silently skipping. Normal exits and HUP/INT/TERM clean up staging and the lock. After a machine crash or forced kill, verify no downloader is active before manually removing `data/monthly-reports/.download.lock/`; the next run retries incomplete files.

The service logs under `shoutbomb-download-monthly-reports` and uses the shared best-effort start/success/failure lifecycle. Configure `HEALTHCHECKS_MONTHLY_DOWNLOAD_URL` for **daily polling**: success means the poll completed, not that a new monthly file arrived.

#### Separate monthly-arrival monitoring

Enable `--arrival-healthcheck-url-env HEALTHCHECKS_MONTHLY_ARRIVAL_URL` to notify a second check when a **newly downloaded** file's filename date is in the current calendar month. This is an arrival proxy, not a claim about the CSV's reporting period. The calendar month uses the system timezone (or `TZ` in `.env`). Historical/future-month backfills and existing local files do not count. Several eligible downloads in one run produce one arrival success ping; additional new eligible files can produce another. The two resolved check URLs must differ.

Only arrival **success** pings go to this second check, never daily `/start` or `/fail` pings. Daily no-op successes do not refresh it. Completed eligible downloads still count if another transfer or the logging pipeline fails; the daily check continues to reflect that failure independently. Omit the arrival option to retain daily-only operation.

Configure the second check with a **calendar-month schedule and grace period**, not a fixed 30-day interval. For example, expecting a ping from the 1st with a nine-day grace period gives a deadline around the 10th; choose the exact deadline and timezone in Healthchecks.io and verify its displayed next deadline. Reports typically arrive during the first week. The scripts impose no overdue deadline and never send an overdue failure themselves; monitoring flags a missing arrival. Check that early-in-window arrivals satisfy the intended monthly cycle.

For durable retry state the service passes `--receipt-dir` to the downloader, using `data/monthly-reports/.arrival-state/pending/`. Each receipt is named after its CSV and contains the download month as `YYYY-MM`. The receipt is persisted before atomic CSV publication; a receipt alone is not proof of a completed transfer. Consumers require the corresponding completed regular, non-symlink CSV as well. Publication/receipt errors fail the downloader; no human log parsing is used. Ordinary manual downloads without `--receipt-dir` do not generate arrival evidence later merely by enabling monitoring.

Failed arrival pings (including missing `curl`) leave receipts for the next daily invocation, even if no files are downloaded then. Successful acknowledgment removes only that notification batch's receipts. Historical/mismatched receipts and retries from earlier months are discarded without a ping so they cannot mask a missing report next month. A crash after a successful ping but before receipt removal may repeat the ping; notification delivery is best-effort, not exactly-once. Monitoring failures never replace the download/logging exit status. Keep notification state separate from future processing state; do not delete it merely because a CSV has been processed.

Concurrent notification attempts use `data/monthly-reports/.arrival.lock/`; contention defers notification without failing the daily job. After an unclean termination, verify no service is active before removing a stale arrival lock. As with the download lock, do not remove active locks.

Before operational rollout, independently verify SFTP access to `/monthly_report`, the actual filename family, filename-reuse policy, a complete download, and both Healthchecks.io checks in the deployment environment. Verify monthly scheduling/grace/timezone, an eligible arrival, a no-op day, and recovery from a failed arrival ping using designated test checks, not production checks during routine validation. Local mocked checks do not prove these live integrations.

### Visualize monthly statistics

Create a self-contained HTML dashboard from one or more local monthly reports:

```bash
./visualize-monthly-reports data/monthly-reports/*.csv
# Open data/monthly-visualizations/index.html in a browser.
```

The output defaults to project-root `data/monthly-visualizations/index.html`, regardless of the working directory. Input arguments and `--output` paths are relative to the current directory. Choose another destination with `--output /path/to/report.html`. The destination is replaced atomically with owner-only permissions; inputs are never overwritten. Generated dashboards are ignored by Git. No `.env` is read, and no network requests, downloader receipt updates, or retention changes occur.

Branch selection is reflected in the URL, for example `index.html#branch=novato-library`. Opening that link restores the view; selector changes, branch comparison links, and browser Back/Forward navigation synchronize with the URL. A `report` fragment parameter preserves the selected report as well. Missing selection defaults to all branches/the latest included report; unknown IDs fall back with a visible notice. This works with local `file:` URLs and static hosting. A local link is usable by another staff member only if they can access the same HTML file; sharing the fragment alone does not share the file.

The report opens on **all branches** for the latest included month, with the month and branch together in a compact header. Its single-column layout uses a warm off-white background, navy text, restrained teal charts, and larger headline counts, with **registered patrons**, **new signups**, and **text notices** one after another. Each metric has its heading, selected-month count, prior-month change, and chart together; headline changes use conversational labels (such as “10 more than September 2026 (+14.1%)”) and neutral styling rather than good/bad colors. Tables align numeric columns to the right, and printing uses a plain white background. There are no summary cards, side-by-side metric columns, or forced full-screen sections.

Changes use the immediately preceding calendar month when both values are reported. A zero prior count has no defined percentage change; absent months/metrics are not substituted with zero or the nearest earlier report.

Line charts have labeled count axes starting at zero and visible point values for short series; lines never bridge a missing value or calendar month. All confirmed months remain visible, with the selected report's point outlined. On narrow screens, charts use compact geometry and larger labels, separate month/year lines, and fewer labels for longer timelines without dropping data points or exact table values. Branch selection focuses the first three metrics. Snapshot changes are not signup totals, confirmed month-end balances, or adoption rates.

**Additional information follows below the three primary metrics**, grouped into Activity details, Branch comparisons, and Sources & interpretation, with keyboard-accessible jump controls that preserve the selected branch/report URL. It includes system-wide keyword counts/chart, exact monthly value/change tables, alphabetical branch detail with clickable names, notice breakdowns, overdue-item counts (including successful/failed renewals where reported), system registration totals, source percentages with unverified denominators, filenames, and warnings. Branch comparisons stack the three metrics under each branch in a wrapping three-column table instead of a wide, horizontally scrolling table; tables retain compact signed changes. Nothing is removed from the underlying data. Keyword counts remain explicitly system-wide, include test/administrative commands, and are not unique active users or necessarily engagement. Overall/branch views are printable; no progress-bar-style charts are used. Notice volume is not a performance ranking. The HTML embeds **all included months and branches**: selection is not access control. Review inputs for sensitive information and distribute dashboards only to the intended audience. No external chart libraries, fonts, analytics, or server are used.

#### Reporting months and trends

By default the filename date is shown as a generation date with **activity month unconfirmed**; the script does not assume that a November file reports October activity. For a confirmed reporting month on one file:

```bash
./visualize-monthly-reports --period 2026-10 --output /tmp/october-dashboard.html /path/to/report.csv
```

For user-confirmed named exports such as `sb_report_August_2026_<identifier>_2026-11-10_16_02_39.csv`, explicitly use the **Month_YYYY label**, not the November generation timestamp:

```bash
./visualize-monthly-reports --named-periods sb_report_*.csv
```

`--named-periods` requires that named filename family, accepts full English month names, and assigns/sorts each file by its labeled activity month. It does not change default inference or the SFTP downloader's supported filename family. Supply only the authoritative report for each month; the script does not automatically choose between conflicting corrected versions.

Only if you have confirmed the convention that legacy reports describe the previous calendar month, explicitly opt into filename-date assignment:

```bash
./visualize-monthly-reports --previous-month data/monthly-reports/*.csv
```

`--previous-month` requires legacy `sb_generate_monthly_report_...` dated filenames and handles year boundaries; it rejects named reports to avoid replacing their explicit month label with a generation-date assumption. At least two explicitly assigned months are needed to draw a trend; the primary metric counts remain visible when no trend is available. The report selector is hidden when only one report is included. `--period` requires exactly one file. All three period modes are mutually exclusive; no general reporting-month convention is inferred by default.

#### Parsing and validation

The parser understands branch sections, CSV-like rows (including quoted commas/escaped quotes), dot/equals section separators, prose and CSV reminder summaries, both branch-total/signup formats, prose/CSV registration totals, inline/CSV source percentages, and successful/failed renewal counts. It handles UTF-8 BOM and CRLF; quoted multiline fields are unsupported and fail with a diagnostic. Repeated reminder summaries are counted once, absent metrics remain **not reported** rather than zero, and registration-only branches are retained. A signup row without a branch is retained as unattributed and flagged; it is never assigned to an invented branch or added again to the source-reported system signup total. Item counts and message counts are never added together. No inferred renewal rates, language shares, or adoption rates are calculated.

Source inconsistencies and unknown lines are reported as warnings in stderr and the dashboard; unknown text itself is not copied into diagnostics. Review warnings before relying on the output. Malformed recognized numeric/CSV rows, conflicting repeated metrics, and inputs without supported branch data fail before replacing an existing dashboard. Duplicate normalized reports for the same activity month are skipped; conflicting reports for that month fail so you can explicitly choose the correct source. Without a confirmed month, this check groups reports by filename date (or one undated group), not an inferred activity period.

Exit status is 0 on success, 1 on input/output/format errors, and 2 on usage errors. A missing Node.js runtime prevents the executable from starting. This is a local visualization tool, not a monitored service or a new uploadable SQL report.

### Run the monitored generate-and-upload workflow

Run the primary monitored generate-then-upload workflow used by cron:

```bash
./services/generate-and-upload \
  --healthcheck-url-env HEALTHCHECKS_PRIMARY_REPORTS_URL \
  --generate-reports holds overdue loanrules \
  --upload-reports holds overdue
```

Run a separately monitored renewal workflow with the same service:

```bash
./services/generate-and-upload \
  --healthcheck-url-env HEALTHCHECKS_RENEWALS_URL \
  --generate-reports renew \
  --upload-reports renew
```

Each independently scheduled workflow selects its own full Healthchecks.io URL from `.env`. The generation and upload report lists are explicit and are passed unchanged to their corresponding scripts. This keeps `upload` as the canonical source for supported report names and preserves the existing cron behavior: `upload` runs only when `generate-reports` returns zero.

The service also:

- sends best-effort Healthchecks.io `/start`, success, and `/fail` pings in order, with short connection and request timeouts
- logs command output under the existing `shoutbomb-generate-reports` and `shoutbomb-upload` tags
- preserves command and logging pipeline exit statuses
- resolves the project root from its own location, so cron does not need to set a working directory

The logger executable defaults to `/usr/bin/logger`. `SHOUTBOMB_LOGGER_PATH` can select a substitute executable without changing the default; this is primarily a test seam for keeping mocked service tests out of the real system log.

`--healthcheck-url-env` is required and must name a non-empty `HEALTHCHECKS_*_URL` variable in `.env`. The URL itself is not passed on the command line or written to logs. Healthchecks.io connectivity and ping failures do not prevent the report scripts from running or alter their exit statuses, although each synchronous ping can add up to five seconds when the service is unreachable.

### Archive old files

Archive active files older than 2 days and delete archived files older than 30 days:

```bash
./archive-reports --archive 2 --delete-archived 30
```

Preview the same archive/prune run without changing files:

```bash
./archive-reports --dry-run --archive 2 --delete-archived 30
```

Run archive maintenance as a monitored service job:

```bash
./services/archive-reports \
  --healthcheck-url-env HEALTHCHECKS_ARCHIVE_URL \
  --archive 2 \
  --delete-archived 30
```

The monitored service passes archive options unchanged to `./archive-reports`, logs its output under `shoutbomb-archive-reports`, and uses the same best-effort Healthchecks.io lifecycle as the generate/upload service.

Useful to know:

- eligible `data/*.csv` files are moved into `data/_archive/`
- eligible `data/_archive/*.csv` files are deleted
- file age comes from the Unix timestamp embedded in the filename, not filesystem modification time
- when both options are given, archived-file deletion happens before active-file archiving
- `./upload` only scans active `data/`, so schedule archiving after any review or upload workflow that depends on those files still being there

### Show help

```bash
./generate-reports --help
./upload --help
./services/generate-and-upload --help
./archive-reports --help
./services/archive-reports --help
./download-monthly-reports --help
./services/download-monthly-reports --help
./visualize-monthly-reports --help
./check --help
```

## Local validation and tests

Install the local test dependencies (Bats-core 1.5.0 or newer, ShellCheck, and Node.js 18 or newer) with the operating-system package manager.

FreeBSD:

```bash
sudo pkg install bats-core hs-ShellCheck node
```

Ubuntu 24.04:

```bash
sudo apt install bats shellcheck nodejs
```

Then run the canonical local check:

```bash
./check
```

`./check` runs Bash/JavaScript syntax checks, ShellCheck, the Bats suite under `tests/` (including help smoke tests), and `node --test tests/monthly-visualizations.test.cjs`. Behavioral tests create isolated temporary project trees and use generated fixtures plus fake `psql`, `sftp`, `curl`, `date`, workflow commands, and logger executables. Dashboard tests use synthetic reports, temporary input/output paths, and a small DOM/event harness for generated-template/SVG wiring, URL restoration, selection updates, and simulated Back/Forward navigation. They also cover report-format variants, explicit named periods, corrections, unattributed signups, zero-base percentage changes, and gaps in timelines; they do not constitute a real-browser visual check. Tests do not read the project `.env`, inspect working CSV artifacts, contact external services, write to the real system log, or require secrets.

The mocked `psql` tests validate report discovery, arguments, output-file handling, and failure behavior; they do not execute or prove the semantics of the production Sierra SQL. Live PostgreSQL/Sierra query, SFTP upload, and Healthchecks.io validation remain separate operational checks.

Known CLI differences are preserved by characterization tests and should be normalized separately rather than incidentally during test maintenance.

## Report inventory

| Report | Source file | What it contains | Upload supported? | Remote destination |
| --- | --- | --- | --- | --- |
| `holds` | `sql/holds.sql` | hold-related item and patron data | yes | `/Holds` |
| `loanrules` | `sql/loanrules.sql` | loan rule numbers and max renewal values | no | — |
| `overdue` | `sql/overdue.sql` | items due between 30 days ago and yesterday, inclusive | yes | `/Overdue` |
| `renew` | `sql/renew.sql` | items due between today and 2 days from now | yes | `/Renew` |
| `text-patrons` | `sql/text-patrons.sql` | patron numbers and normalized mobile phone numbers | yes | `/text_patrons` |

## Cron structure

Each monitored cron workflow:

1. selects its own `HEALTHCHECKS_*_URL` setting
2. notifies Healthchecks.io that the workflow is starting
3. runs its report, archive, or monthly-download commands with their logger tags
4. notifies Healthchecks.io whether the complete workflow succeeded or failed

For generate/upload jobs, `upload` still runs only when `generate-reports` succeeds. Archive maintenance remains a later, separate job.

```cron
# Generate selected reports, then upload the configured reports only if generation succeeds.
00 06,12,15 * * * /opt/scripts/shoutbomb/services/generate-and-upload --healthcheck-url-env HEALTHCHECKS_PRIMARY_REPORTS_URL --generate-reports holds overdue loanrules --upload-reports holds overdue

# Renewal command: prefix this command with the intended five-field cron schedule.
# /opt/scripts/shoutbomb/services/generate-and-upload --healthcheck-url-env HEALTHCHECKS_RENEWALS_URL --generate-reports renew --upload-reports renew

# Archive/prune later, after any generate/upload workflow that still needs active files in data/.
30 18 * * * /opt/scripts/shoutbomb/services/archive-reports --healthcheck-url-env HEALTHCHECKS_ARCHIVE_URL --archive 2 --delete-archived 30

# Poll daily; separate check URLs monitor daily polling and current-month arrivals.
00 09 * * * /opt/scripts/shoutbomb/services/download-monthly-reports --healthcheck-url-env HEALTHCHECKS_MONTHLY_DOWNLOAD_URL --arrival-healthcheck-url-env HEALTHCHECKS_MONTHLY_ARRIVAL_URL
```

Why it is structured this way:

- **absolute path**: cron often runs with a minimal environment, so use the full path to each service
- **service-managed logging**: services preserve `pipefail` behavior and existing logger tags; monthly polling adds `shoutbomb-download-monthly-reports`
- **separate checks**: each independently scheduled workflow selects its own Healthchecks.io URL without placing that URL on the command line
- **separate report lists**: generation-only reports such as `loanrules` can be omitted explicitly from the upload list without duplicating `upload`'s supported-report mapping
- **success gating**: the generate/upload service preserves the existing behavior of skipping upload when generation returns non-zero
- **best-effort monitoring**: ordered Healthchecks.io requests use short timeouts; failures do not prevent the underlying scripts from running and do not alter their exit statuses
- **separate archive job**: avoids moving files out of `data/` before upload or review jobs are done

More cron notes:

- replace every cron entry that directly runs `generate-reports` as part of a generate/upload workflow; preserve each entry's schedule and its separate generation and upload report lists
- give every independently scheduled service invocation its own `HEALTHCHECKS_*_URL` variable and Healthchecks.io check
- do not retain outer `/bin/bash`, `logger` pipelines, or `&&` chains around monitored services because the services handle them
- the services and underlying scripts resolve project paths relative to their own locations, so cron does not need to set a working directory
- keep archive/prune jobs later than any workflow that still expects the newest CSVs to remain in active `data/`

## Troubleshooting

### Grep syslog by shoutbomb tag

The cron examples use these `logger` tags:

- `shoutbomb-generate-reports`
- `shoutbomb-upload`
- `shoutbomb-archive-reports`
- `shoutbomb-download-monthly-reports`

To search all shoutbomb-related syslog lines on systems that log to `/var/log/syslog`:

```bash
sudo grep -E 'shoutbomb-(generate-reports|upload|archive-reports|download-monthly-reports)' /var/log/syslog
```

To search only upload logs:

```bash
sudo grep -E 'shoutbomb-upload' /var/log/syslog
```

To search generation and upload together:

```bash
sudo grep -E 'shoutbomb-(generate-reports|upload)' /var/log/syslog
```

If your system uses a different file such as `/var/log/messages`, substitute that path.

### Follow logs live

```bash
sudo tail -F /var/log/syslog | grep --line-buffered -E 'shoutbomb-(generate-reports|upload|archive-reports|download-monthly-reports)'
```

### Use journalctl on journald systems

Some systems do not write these messages to `/var/log/syslog`. If your cron output is going through journald, try:

```bash
sudo journalctl \
  -t shoutbomb-generate-reports \
  -t shoutbomb-upload \
  -t shoutbomb-archive-reports \
  -t shoutbomb-download-monthly-reports \
  --since today
```

### Common failure points

If something is not working, check these first:

- `.env` exists and is readable
- the variable named by `--healthcheck-url-env` exists, is non-empty, and matches `HEALTHCHECKS_*_URL`
- each scheduled workflow selects its own Healthchecks.io variable
- required PostgreSQL variables are set for `./generate-reports`
- required SSH variables are set for `./upload` and `./download-monthly-reports`
- `SSH_IDENTITY_FILE` points to an absolute, readable path
- `SSH_KNOWN_HOSTS_FILE`, if set, is also an absolute, readable path
- `psql` is installed and on `PATH`
- `sftp` is installed and on `PATH`
- `curl` is installed and on `PATH` for Healthchecks.io monitoring
- `/usr/bin/logger` exists for monitored service logging
- the latest expected CSV actually exists in `data/`
- remote upload directories already exist
- SFTP `/monthly_report` exists and is readable for monthly downloads
- no stale `data/monthly-reports/.download.lock/` or `.arrival.lock/` remains after an unclean exit (verify no run/service is active before removing it)
- monthly arrivals select a separate URL, use the intended system/`TZ` month, and have a matching calendar-month schedule/grace in monitoring
- the host key is trusted, since strict host key checking is always enabled

Quick local help commands:

```bash
./generate-reports --help
./upload --help
./services/generate-and-upload --help
./archive-reports --help
./services/archive-reports --help
./download-monthly-reports --help
./services/download-monthly-reports --help
```

## Changelog and releases

Implemented changes are recorded newest-first under dated headings in
`CHANGELOG.md`, using concise entries. Every release includes the updated
changelog. Files under `notes/` remain point-in-time design and caveat context
rather than release-history records.

## Notes and caveats

- If you change `sql/overdue.sql` or `sql/renew.sql`, read `notes/hold-count-aggregation-issue.md` first.
- Files in `data/` are generated artifacts, not source-of-truth logic.
- Real query validation requires access to the PostgreSQL/Sierra environment.
- Real upload/download validation requires working SSH/SFTP credentials and host key setup.
