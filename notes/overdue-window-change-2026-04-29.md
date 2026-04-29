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
c.due_gmt >= current_date - INTERVAL '30 days'
AND c.due_gmt < current_date
```

## Impact

This changes row filtering for the `overdue` report.

The report now includes items with due dates from 1 to 30 days ago.

It no longer limits results to items that are at least 10 days past due, but it still excludes items due today.

The query now expresses that window as a timestamp range on `c.due_gmt` instead of casting `c.due_gmt` to `date`, which may allow a plain index on `c.due_gmt` to be used more effectively.

Unchanged:

- column names
- column order
- hold-count aggregation logic
- sort order

## Validation note

This was a static SQL change only.
It was not validated against a live Sierra/PostgreSQL environment in this repository.
