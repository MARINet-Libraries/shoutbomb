# AGENTS.md

## Project overview

This repository contains a small set of PostgreSQL report queries, a Bash runner that exports each query result to CSV, and a Bash uploader that sends the latest supported CSVs to Shoutbomb over FTPS.

The intended workflow is:

1. place report queries in `sql/*.sql`
2. run `./generate-reports.sh`
3. collect generated CSV files from `data/`
4. run `./upload.sh`

The repository is intentionally simple. There is no application runtime, package manager, test framework, or migration system. The main responsibilities are:

- maintaining correct SQL report definitions
- preserving predictable CSV export behavior
- documenting any query caveats or data-quality concerns

## Repository layout

- `generate-reports.sh`
  - Bash entrypoint that discovers and runs all `sql/*.sql` files with `psql`
- `upload.sh`
  - Bash entrypoint that uploads the latest supported CSV files from `data/` to Shoutbomb over FTPS
- `sql/`
  - source SQL reports; every `*.sql` file in this directory is executed by the script
- `data/`
  - generated CSV output directory
  - output files are runtime artifacts and may be regenerated
- `notes/`
  - project notes, caveats, and analysis documents
- `AGENTS.md`
  - contributor and automation guidance for this repository

## Current reports

At the time of writing, the repository contains:

- `sql/holds.sql`
- `sql/overdue.sql`
- `sql/renew.sql`

These are Sierra/PostgreSQL reporting queries against `sierra_view` tables.

## Runtime assumptions

The report runner assumes:

- `psql` is installed and available on `PATH`
- connection details are provided by standard PostgreSQL environment variables, such as:
  - `PGHOST`
  - `PGPORT`
  - `PGDATABASE`
  - `PGUSER`
  - `PGPASSWORD`
- the executing environment has network access to the target PostgreSQL server

The uploader assumes:

- `curl` is installed and available on `PATH`
- FTPS connection details are available in the project `.env` file
- the executing environment has network access to the target FTPS server

Important:

- agents working in this repository should **not assume** they can reach the live database
- agents should **not assume** they have working FTPS credentials or server access
- syntax and file-level validation can be performed locally
- actual query execution and FTPS upload may only be possible for the repository owner or in the target environment

## Report runner behavior

`generate-reports.sh` is the canonical way to export reports.

### Expected behavior

- discovers every `*.sql` file in `sql/`
- runs each query with `psql`
- writes CSV files to `data/`
- uses a single shared epoch timestamp per run
- names files as:
  - `<report-name>-<epoch>.csv`
  - example: `holds-1713965123.csv`
- includes headers by default
- supports `--no-headers` to omit headers
- continues processing remaining reports if one fails
- exits non-zero if any report fails
- deletes partial output for failed reports

### Expected usage

```bash
./generate-reports.sh
./generate-reports.sh --no-headers
./generate-reports.sh --help
```

## Conventions for SQL files

### Location and naming

- all runnable SQL reports belong in `sql/`
- use one report per file
- use lowercase file names with hyphens or simple descriptive singular/plural names when practical
- the file basename becomes the CSV basename
  - `sql/holds.sql` -> `data/holds-<epoch>.csv`
  - `sql/overdue.sql` -> `data/overdue-<epoch>.csv`
  - `sql/renew.sql` -> `data/renew-<epoch>.csv`

### Query shape

- each file should contain a single report query intended for direct execution by `psql`
- prefer plain `SELECT` statements
- avoid interactive `psql` meta-commands inside report SQL files
- avoid transaction control statements unless there is a strong reason
- do not depend on session-local setup that the runner does not provide

### Output stability

Because the SQL result becomes a CSV delivered to downstream users, maintain stable output whenever possible:

- keep column order intentional
- keep column names readable and consistent
- avoid renaming columns casually
- document any breaking output changes in `notes/`
- if a report requires sorted output, include an explicit `ORDER BY`

### SQL style

The existing SQL uses a vertically formatted style. Follow that style for consistency:

- uppercase SQL keywords
- one selected expression per line when practical
- clearly formatted `JOIN` blocks
- explicit aliases
- explicit `ORDER BY`
- preserve existing indentation style in nearby files

## Known query caveats

A documented issue currently exists in:

- `sql/overdue.sql`
- `sql/renew.sql`

See:

- `notes/hold-count-aggregation-issue.md`

### Summary of the issue

Those two queries currently join both bib-level and item-level holds before aggregation, which can multiply joined rows and inflate:

- `COUNT(ih.id)`
- `COUNT(bh.id)`

### Contributor guidance

- do not “quietly” change report semantics without approval
- if fixing this issue, prefer a clearly justified change such as:
  - `COUNT(DISTINCT ...)`, or
  - pre-aggregated hold-count subqueries / CTEs
- if behavior changes, document the reason in `notes/`

## Conventions for Bash changes

If modifying `generate-reports.sh` or `upload.sh`:

- keep it POSIX-aware Bash, but Bash-specific features are acceptable since the shebang is Bash
- preserve safe shell practices already in use
- do not hardcode credentials, database hosts, or FTPS hosts unless explicitly requested
- prefer readable control flow over clever shell tricks
- keep help text current with actual behavior
- preserve the current default behavior unless explicitly asked to change it

### Minimum checks after editing a script

Run at least:

```bash
bash -n generate-reports.sh
./generate-reports.sh --help
bash -n upload.sh
./upload.sh --help
```

If database access is available, a real query execution against the intended environment is ideal, but do not claim query validation unless it was actually performed.

If FTPS access is available, a real upload is ideal, but do not claim upload validation unless it was actually performed.

## Data directory guidance

- `data/` contains generated artifacts, not source-of-truth logic
- do not treat generated CSVs as hand-edited files
- if sample output is ever committed intentionally, document why
- otherwise, prefer leaving generated data uncommitted unless the user explicitly wants it tracked

## Notes directory guidance

Use `notes/` for:

- query review findings
- data caveats
- unresolved issues
- rationale for non-obvious implementation decisions
- change-impact notes when report semantics change

Notes should be written as clear Markdown with enough context that a future contributor can understand the concern without reconstructing the entire history.

## Safety and change management

When making changes in this repository:

- favor small, targeted edits
- preserve existing behavior unless the requested task is specifically to change behavior
- call out any semantic SQL changes explicitly
- do not invent database access you do not have
- do not embed secrets in scripts, SQL, or docs
- do not remove or overwrite user-provided SQL files without a clear reason

## Recommended workflow for future contributors

1. inspect the relevant SQL file(s), `generate-reports.sh`, and/or `upload.sh`
2. check `notes/` for known issues or prior rationale
3. make the smallest change that satisfies the request
4. validate shell syntax if a script changes
5. if SQL semantics or output conventions change, document the change in `notes/`
6. summarize clearly what was changed and what could not be verified locally

## If adding a new report

When adding a new report:

1. create a new `sql/<name>.sql`
2. ensure it runs as a standalone query in `psql`
3. ensure output columns are intentionally named
4. add ordering if deterministic output matters
5. remember that `generate-reports.sh` will automatically include it
6. document any special caveats in `notes/` if needed

## If changing report output format

Changing any of the following should be treated as a potentially breaking change:

- column order
- column names
- row filtering logic
- aggregation logic
- sort order
- filename conventions
- header defaults

If such a change is intentional, mention it explicitly in the change summary and add a note if the impact is non-trivial.

## Quick reference

### Run all reports

```bash
./generate-reports.sh
```

### Run without headers

```bash
./generate-reports.sh --no-headers
```

### Upload latest supported reports

```bash
./upload.sh
```

### Validate script syntax

```bash
bash -n generate-reports.sh
bash -n upload.sh
```

### Known issue note

```text
notes/hold-count-aggregation-issue.md
```
