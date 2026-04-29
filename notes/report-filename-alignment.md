# Report filename alignment

## Summary

On 2026-04-24, the report filenames were aligned with the remote destination naming pattern.

Renamed SQL reports:

- `sql/renewals.sql` → `sql/renew.sql`
- `sql/overdues.sql` → `sql/overdue.sql`

Because `generate-reports` uses the SQL filename basename for CSV export names, the generated files also changed:

- `data/renewals-<epoch>.csv` → `data/renew-<epoch>.csv`
- `data/overdues-<epoch>.csv` → `data/overdue-<epoch>.csv`

`upload` now expects and uploads these names:

- `holds-<epoch>.csv` → `/Holds`
- `renew-<epoch>.csv` → `/Renew`
- `overdue-<epoch>.csv` → `/Overdue`

## Impact

This is a filename-convention change only.

It does **not** change the SQL result columns, row filters, or aggregation behavior of the reports.

Any downstream process that looked for `renewals-*.csv` or `overdues-*.csv` must be updated to use the new filenames.
