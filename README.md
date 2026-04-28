# shoutbomb

Small PostgreSQL report-export project for Sierra data destined for Shoutbomb.

This repository contains a Bash report runner, a Bash SFTP uploader, and a set of standalone SQL report queries used to generate and deliver report information to Shoutbomb. The intended workflow is:

1. put report queries in `sql/`
2. run `./generate-reports.sh`
3. review generated CSV files in `data/`
4. run `./upload.sh` to upload the latest supported report files

The project is intentionally simple:

- no application runtime
- no package manager
- no test framework
- no migration system

The core responsibility is exporting predictable CSV reports from `psql` and uploading the expected files to Shoutbomb.

## Repository layout

```text
.
├── .env.example          # example PostgreSQL and SSH/SFTP settings
├── generate-reports.sh   # runs every sql/*.sql file with psql
├── upload.sh             # uploads latest supported CSVs from data/ via SFTP
├── sql/                  # source report queries
├── data/                 # generated CSV output
├── notes/                # caveats and analysis notes
├── AGENTS.md             # contributor guidance
└── README.md
```

## Requirements

- Bash
- `psql` installed and available on `PATH`
- `sftp` installed and available on `PATH`
- network access to the target PostgreSQL server
- network access to the Shoutbomb SSH/SFTP server
- an SSH private key authorized for the upload account
- the SSH host key present in the default `known_hosts` file or a configured alternate known_hosts file
- a project-root `.env` file containing:
  - PostgreSQL settings for report generation:
    - `PGHOST`
    - `PGPORT`
    - `PGDATABASE`
    - `PGUSER`
    - `PGPASSWORD`
  - SSH/SFTP settings for upload:
    - `SSH_USERNAME`
    - `SSH_IDENTITY_FILE` (absolute path)
  - optional SSH/SFTP overrides:
    - `SSH_HOST`
    - `SSH_PORT`
    - `SSH_KNOWN_HOSTS_FILE` (absolute path)

## Purpose

This project is meant to support Shoutbomb-related reporting workflows.

In practice, that means:

- querying Sierra/PostgreSQL data
- exporting the results as CSV files
- uploading the latest required report files to Shoutbomb

## Configuration

Create a `.env` file in the project root before running reports or uploads.

A quick start is:

```bash
cp .env.example .env
```

Then edit `.env` with the real PostgreSQL/Sierra and SSH/SFTP values.

Example:

```dotenv
PGHOST=hostname
PGPORT=5432
PGDATABASE=database_name
PGUSER=username
PGPASSWORD=secret

SSH_HOST=ftp.shoutbomb.com
SSH_PORT=22
SSH_USERNAME=your_username
SSH_IDENTITY_FILE=/full/path/to/private_key
# Optional:
# SSH_KNOWN_HOSTS_FILE=/full/path/to/known_hosts
```

`generate-reports.sh` loads this file automatically and exits with an error if the file is missing or required PostgreSQL values are blank.

`upload.sh` also loads this file automatically and exits with an error if the file is missing or required SSH/SFTP values are blank. `SSH_IDENTITY_FILE` and `SSH_KNOWN_HOSTS_FILE`, if set, must use absolute paths.

## Usage

Generate all reports with headers:

```bash
./generate-reports.sh
```

Generate all reports without headers:

```bash
./generate-reports.sh --no-headers
```

Upload the latest supported report files:

```bash
./upload.sh
```

Show help:

```bash
./generate-reports.sh --help
./upload.sh --help
```

## Report runner behavior

`generate-reports.sh` is the canonical export entrypoint.

It:

- loads PostgreSQL connection settings from `.env`
- discovers every `*.sql` file in `sql/`
- runs each query with `psql`
- writes CSV output into `data/`
- uses a single shared epoch timestamp for the whole run
- names output files as `<report-name>-<epoch>.csv`
- includes headers by default
- supports `--no-headers` to omit headers
- continues processing remaining reports if one report fails
- exits non-zero if any report fails
- deletes partial output files for failed reports

Example output filenames:

```text
data/holds-1713965123.csv
data/overdue-1713965123.csv
data/renew-1713965123.csv
```

## Upload behavior

`upload.sh` uploads only the latest generated file for each supported report type:

- `holds` → `/Holds`
- `renew` → `/Renew`
- `overdue` → `/Overdue`
- `text-patrons` → `/text_patrons`

It:

- loads SSH/SFTP settings from `.env`
- looks in `data/` for files matching `<report-name>-<epoch>.csv`
- selects the latest file for each supported report by filename epoch
- uploads each selected file with its own SFTP invocation
- uploads each selected file to its existing destination directory on the remote server
- assumes the destination directories already exist
- continues attempting remaining uploads if one report file is missing or one upload fails
- exits non-zero if any required report file is missing or any upload fails
- always uses strict SSH host key checking

For the filename-convention change that aligned report names with the destination directories, see `notes/report-filename-alignment.md`.

Optional upload flags:

```text
-h, --help         Show help
-H, --host HOST    SSH host override
-P, --port PORT    SSH port override
-v, --verbose      Verbose sftp output
```

## Current reports

### `sql/holds.sql`

Exports hold-related item and patron data, including:

- title
- last item update date
- item number
- patron number
- pickup location
- item barcode
- hold ID
- patron barcode

The query filters to selected hold statuses, only includes items with status `!`, and requires a non-null pickup location.

### `sql/overdue.sql`

Exports checkout records that are overdue by more than 9 days and less than 31 days, including:

- patron number
- item barcode
- title
- due date
- item number
- money owed
- loan rule
- item hold count
- bib hold count
- renewal count
- bib number

### `sql/renew.sql`

Exports checkout records due in 2 days, with the same output columns as `overdue.sql`.

### `sql/text-patrons.sql`

Exports patron numbers and normalized mobile phone numbers for text-message related downstream use.

## Known caveat

A documented aggregation issue affects:

- `sql/overdue.sql`
- `sql/renew.sql`

Both queries join bib-level and item-level holds before aggregation, which can multiply rows and inflate:

- `COUNT(ih.id)`
- `COUNT(bh.id)`

See:

- `notes/hold-count-aggregation-issue.md`

If you change these reports, review that note first.

## Adding or changing reports

Each SQL file in `sql/` should be a standalone query intended for direct execution by `psql`.

Recommended conventions:

- one report per file
- lowercase filenames
- stable, intentional column names
- stable column order
- explicit `ORDER BY` when deterministic output matters
- avoid `psql` meta-commands in report SQL files

The output CSV basename comes from the SQL filename:

- `sql/holds.sql` → `data/holds-<epoch>.csv`
- `sql/overdue.sql` → `data/overdue-<epoch>.csv`
- `sql/renew.sql` → `data/renew-<epoch>.csv`
- `sql/text-patrons.sql` → `data/text-patrons-<epoch>.csv`

Treat changes to any of the following as potentially breaking:

- column names
- column order
- row filtering
- aggregation logic
- sort order
- filename conventions
- header defaults

If report semantics change, document the reason in `notes/`.

## Validation

For script-only changes, the minimum local checks are:

```bash
bash -n generate-reports.sh
./generate-reports.sh --help
bash -n upload.sh
./upload.sh --help
```

Actual query validation requires access to the target PostgreSQL/Sierra environment.

Actual upload validation requires access to the target SSH/SFTP environment, valid SSH credentials, and host key configuration.

## Notes on generated data

Files in `data/` are runtime artifacts, not source-of-truth logic. They can be regenerated by rerunning the export script.
