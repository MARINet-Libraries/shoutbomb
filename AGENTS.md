# AGENTS.md

## Scope

This repository contains standalone SQL report queries in `sql/`, a Bash export runner in `generate-reports`, a Bash SFTP uploader in `upload`, project notes in `notes/`, and generated CSV artifacts in `data/`.

## Critical rules

- Do **not** assume live PostgreSQL/Sierra access.
- Do **not** assume working SSH/SFTP credentials or server access.
- Do **not** claim query execution or upload validation unless it was actually performed.
- Scripts load configuration from `./.env`; do not hardcode secrets, hosts, credentials, or private paths unless explicitly requested.
- Preserve existing report and output behavior unless the task specifically asks for a change.
- `data/` contains generated artifacts, not source-of-truth logic.

## Read minimally

- For a single-report task, read only the relevant `sql/<name>.sql` file.
- Read `generate-reports` only when the task concerns export behavior.
- Read `upload` only when the task concerns upload behavior; treat its supported-report mapping as canonical.
- Read `notes/` only when the touched file is referenced there or the task changes semantics, output, or caveats.
- Do not inspect generated CSV files unless the task is specifically about generated output.

## Task playbooks

### SQL changes

- Keep one runnable report query per `sql/*.sql` file.
- Prefer direct `SELECT`-style queries.
- Avoid `psql` meta-commands, transaction control, or session-local setup that the runner does not provide.
- Preserve intentional column names, column order, and filtering unless explicitly asked to change them.
- Use explicit `ORDER BY` when deterministic output matters.
- Follow existing SQL style in nearby files:
  - uppercase SQL keywords
  - one selected expression per line when practical
  - clear `JOIN` blocks
  - explicit aliases
- If touching `sql/overdue.sql` or `sql/renew.sql`, read `notes/hold-count-aggregation-issue.md` first.
- If SQL semantics change, call that out explicitly and document non-trivial impact in `notes/`.

### Script changes

- Keep Bash readable and safe; Bash-specific features are acceptable.
- Preserve current default behavior unless explicitly asked to change it.
- Do not hardcode credentials, database hosts, or SSH hosts unless explicitly requested.
- `generate-reports` is the canonical export entrypoint.
- `upload` is the canonical source for supported upload report names and destination mapping.
- Minimum local checks after editing a script:
  - `bash -n generate-reports`
  - `./generate-reports --help`
  - `bash -n upload`
  - `./upload --help`

### Adding, removing, or renaming a report

- Put runnable report SQL in `sql/`.
- Remember that `generate-reports` automatically discovers every `sql/*.sql` file.
- If a report should be uploaded, update `upload` and any affected docs/notes together.
- Treat filename convention changes, supported-report-name changes, and upload destination changes as breaking.

## Breaking changes to call out

Explicitly mention changes to:

- column names
- column order
- row filtering
- aggregation logic
- sort order
- filename conventions
- header defaults
- upload destinations
- supported report names

If any of the above change, update `notes/` when the downstream impact is non-trivial.

## Validation limits

- Static and file-level validation can be done locally.
- Real query validation requires access to the target PostgreSQL/Sierra environment.
- Real upload validation requires access to the target SSH/SFTP environment, valid credentials, and trusted host keys.

## References

- Project overview and operator usage: `README.md`
- Query caveats and rationale: `notes/`
- Export behavior: `generate-reports`
- Upload behavior and supported-report mapping: `upload`
