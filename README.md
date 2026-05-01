# shoutbomb

## Quick start

```bash
cp .env.example .env
# edit .env with your database and SSH settings
./generate-reports
# review files in ./data
./upload
```

## Overview

`shoutbomb` is a small command-line project for exporting Sierra/PostgreSQL report data to CSV and, when needed, uploading those CSVs to Shoutbomb over SFTP.

It has two main scripts:

- `./generate-reports` — runs every SQL file in `sql/` and writes CSVs to `data/`
- `./upload` — uploads the latest supported CSVs from `data/` to Shoutbomb

Typical workflow:

1. add or update a report in `sql/`
2. run `./generate-reports`
3. review the output in `data/`
4. run `./upload` if you want to send the latest files to Shoutbomb

## Repository layout

```text
.
├── .env.example
├── generate-reports
├── upload
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
- an SSH private key for uploads
- a trusted SSH host key in `known_hosts` or an alternate `known_hosts` file

### Configure `.env`

Copy the example file:

```bash
cp .env.example .env
```

Then edit `.env` with real values.

Required for report generation:

- `PGHOST`
- `PGPORT`
- `PGDATABASE`
- `PGUSER`
- `PGPASSWORD`

Required for upload:

- `SSH_USERNAME`
- `SSH_IDENTITY_FILE` (absolute path)

Optional upload settings:

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

SSH_HOST=ftp.shoutbomb.com
SSH_PORT=22
SSH_USERNAME=your_username
SSH_IDENTITY_FILE=/full/path/to/private_key
# Optional:
# SSH_KNOWN_HOSTS_FILE=/full/path/to/known_hosts
```

## How to use

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

What it does:

- reads every `sql/*.sql` file by default
- writes CSV files to `data/`
- names files like `data/<report-name>-<epoch>.csv`
- includes headers unless you pass `--no-headers`

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

- `holds` → `/Holds`
- `renew` → `/Renew`
- `overdue` → `/Overdue`
- `text-patrons` → `/text_patrons`

Useful to know:

- use report basenames like `holds`, not filenames like `holds.sql`
- `./upload` looks for the latest matching CSV in `data/`
- destination directories on the remote server must already exist
- strict SSH host key checking is always enabled

### Help

```bash
./generate-reports --help
./upload --help
```

## Running from cron

For scheduled runs, a good pattern is to call the scripts by absolute path and pipe their combined stdout/stderr through `logger` so log retention and rotation are handled by the system logger instead of by project-managed log files.

The scripts resolve `.env`, `sql/`, and `data/` relative to their own location, so a `cd` wrapper is not required.

Example cron entries:

```cron
50 7,11,15 * * * /bin/bash -o pipefail -c '/opt/scripts/shoutbomb/generate-reports --reports text-patrons 2>&1 | /usr/bin/logger -t shoutbomb-generate-reports && /opt/scripts/shoutbomb/upload --reports text-patrons 2>&1 | /usr/bin/logger -t shoutbomb-upload'
00 08 * * * /bin/bash -o pipefail -c '/opt/scripts/shoutbomb/generate-reports --reports overdue renew 2>&1 | /usr/bin/logger -t shoutbomb-generate-reports && /opt/scripts/shoutbomb/upload --reports overdue renew 2>&1 | /usr/bin/logger -t shoutbomb-upload'
00 08,12,16 * * * /bin/bash -o pipefail -c '/opt/scripts/shoutbomb/generate-reports --reports holds overdue renew 2>&1 | /usr/bin/logger -t shoutbomb-generate-reports && /opt/scripts/shoutbomb/upload --reports holds overdue renew 2>&1 | /usr/bin/logger -t shoutbomb-upload'
```

Using `/bin/bash -o pipefail -c '...'` preserves the failure status of `generate-reports` and `upload` even though their output is piped to `logger`.

On systems that write syslog output to `/var/log/syslog`, you can review these messages with commands such as:

```bash
sudo cat /var/log/syslog | egrep "shoutbomb-generate-reports|shoutbomb-upload"
```

## Current reports

- `sql/holds.sql` — hold-related item and patron data
- `sql/overdue.sql` — items due between 30 days ago and yesterday, inclusive
- `sql/renew.sql` — items due between today and 2 days from now
- `sql/text-patrons.sql` — patron numbers and normalized mobile phone numbers

## Notes and caveats

- If you change `sql/overdue.sql` or `sql/renew.sql`, read `notes/hold-count-aggregation-issue.md` first.
- Files in `data/` are generated artifacts, not source-of-truth logic.
- Real query validation requires access to the PostgreSQL/Sierra environment.
- Real upload validation requires working SSH/SFTP credentials and host key setup.
