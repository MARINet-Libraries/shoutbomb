# Overdue report due window change

## Summary

On 2026-04-29, `sql/overdue.sql` was changed from selecting items overdue by more than 9 days and less than 31 days to selecting items due between 30 days ago and yesterday, inclusive.

The filter changed from:

```sql
(current_date - c.due_gmt::date) > 9
AND (current_date - c.due_gmt::date) < 31
```

to:

```sql
c.due_gmt::date BETWEEN current_date - 30 AND current_date - 1
```

## Impact

This changes row filtering for the `overdue` report.

The report now includes items with due dates from 1 to 30 days ago.

It no longer limits results to items that are at least 10 days past due, but it still excludes items due today.

Unchanged:

- column names
- column order
- hold-count aggregation logic
- sort order

## Validation note

This was a static SQL change only.
It was not validated against a live Sierra/PostgreSQL environment in this repository.
