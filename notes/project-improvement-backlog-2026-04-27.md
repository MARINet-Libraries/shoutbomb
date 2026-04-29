# Project improvement backlog

## Summary

This note captures a small set of follow-up improvements identified during a static repository review on 2026-04-27.

No live PostgreSQL/Sierra execution or upload validation was performed for this review.
The items below are intended as future-session cleanup and hardening work, with an emphasis on keeping the project simple and predictable.
Some observations refer specifically to the FTPS-based uploader that existed at the time of review.

## Suggested priorities

### 1. Create one source of truth for supported reports

Current report-related knowledge is duplicated across:

- `upload`
- `upload --help`
- `README.md`
- `AGENTS.md`
- `notes/`

This has already drifted in a few places:

- `sql/text-patrons.sql` exists and `upload` uploads `text-patrons`, but that report is not treated consistently in all docs
- the hold-count issue is described in some places as if it is still current, even though `sql/overdue.sql` and `sql/renew.sql` now use `COUNT(DISTINCT ...)`

### Recommendation

Keep the supported-report mapping in one place and derive the rest from it when practical.
At minimum, make sure the scripts and docs are updated together.

Possible simple approaches:

- a small shell config file sourced by `upload`
- a single clearly marked array block in `upload` treated as canonical
- a short checklist for doc updates whenever a report is added, renamed, or removed

## 2. Ignore generated CSV files

`data/` is documented as generated output, but `.gitignore` currently only ignores `.env`.

### Recommendation

Add generated CSVs to `.gitignore`, for example:

```gitignore
.env
data/*.csv
```

If the directory itself needs to stay present in the repository, keep it with a placeholder such as `.gitkeep`.

## 3. Standardize CLI flags across scripts

At the time of review, the scripts used `-h` differently:

- `generate-reports`: `-h` means help
- `upload`: `-h HOST` meant the FTPS host

This is easy to forget and unnecessarily surprising.

### Recommendation

Reserve `-h` / `--help` for help in both scripts.
Use something more explicit for host overrides, such as:

- `-H HOST`
- `--host HOST`

Keep `-P` / `--port` for port if desired.

## 4. Make bib selection explicit in `overdue` and `renew`

`sql/holds.sql` uses:

```sql
AND bil.bibs_display_order = 0
```

when joining `sierra_view.bib_record_item_record_link`.

`sql/overdue.sql` and `sql/renew.sql` currently do not apply that restriction.
If an item is attached to more than one bib, one checkout row may fan out into multiple report rows.

### Recommendation

Confirm the intended bib-selection rule and make it explicit.
If the primary bib is the intended one, use the same `bibs_display_order = 0` rule already present in `sql/holds.sql`.

Important:

- this is a report-semantics change
- document it clearly if applied
- validate against real data if possible

## 5. Simplify and clean up `sql/holds.sql`

This query appears to have a few maintainability issues:

- several `RIGHT JOIN`s make the query shape harder to read than necessary
- the title expression suggests a fallback that cannot actually happen with the current inner join to `sierra_view.subfield`
- there is an apparently unused join:

```sql
LEFT JOIN sierra_view.varfield AS ic ON (
    ic.record_id = i.id
    AND ic.varfield_type_code = 'c'
    AND ic.occ_num = 0
)
```

### Recommendation

When next editing `sql/holds.sql`:

- rewrite the `RIGHT JOIN`s as ordinary `JOIN` / `LEFT JOIN`
- either make title fallback real or remove the misleading fallback expression
- remove unused joins unless they are intentionally kept for pending work

This is mostly readability and maintenance cleanup, but it may also prevent future mistakes.

## 6. Harden `sql/text-patrons.sql`

`sql/text-patrons.sql` is simple, but downstream expectations are not fully documented.
Potential concerns:

- no `ORDER BY`, so output order is not guaranteed
- one patron may produce multiple rows if multiple matching phone rows exist
- phone normalization removes spaces, hyphens, and periods, but not every possible formatting character
- blank or invalid normalized numbers are not explicitly filtered out

### Recommendation

Before changing the query, confirm the real output requirements:

- should there be exactly one row per patron?
- should invalid or blank phone numbers be excluded in SQL?
- what exact phone-number format does Shoutbomb expect?

After that, make the smallest query change that enforces the intended output.

## 7. Historical note: make insecure FTPS opt-in rather than default

At the time of this review, `upload` called `curl` with:

```bash
--insecure
```

by default.

That disables certificate verification and is weaker than it should be if the server certificate can be validated normally.

### Recommendation

Prefer secure verification by default.
If insecure mode is still needed for some environments, make it explicit via a flag or environment variable, such as:

- `--insecure`
- `FTPS_INSECURE=1`

Any such change should be tested in the real target environment before being treated as complete.
This recommendation became obsolete once the uploader moved from FTPS to SFTP/SSH.

## 8. Add one small validation entrypoint

The repository intentionally does not need a full test framework, but a small repeatable check command would still help.

### Recommendation

Add a very small validation entrypoint, such as:

- `check.sh`, or
- `make check`

Suggested minimum checks:

```bash
bash -n generate-reports
./generate-reports --help
bash -n upload
./upload --help
```

Optional additions:

- a report/doc consistency check
- a check that required directories exist
- `shellcheck` if available in the environment

## Suggested order of work

If addressing these incrementally, a reasonable order is:

1. ignore generated CSVs
2. standardize CLI flags
3. update report/documentation source-of-truth handling
4. add a small validation entrypoint
5. make bib selection explicit in `overdue` and `renew`
6. simplify `sql/holds.sql`
7. harden `sql/text-patrons.sql`
8. historical FTPS hardening note (obsolete after SFTP/SSH migration)

## Bottom line

The immediate low-risk cleanup is in repository hygiene and script usability:

- ignore generated files
- remove doc drift
- make CLI behavior consistent
- add one simple validation command

The next likely correctness work is in SQL behavior:

- explicit bib selection in `overdue` and `renew`
- cleanup and clarification in `holds`
- output-hardening review for `text-patrons`
