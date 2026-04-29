# Renew report due window change

## Summary

On 2026-04-29, `sql/renew.sql` was changed from selecting items due exactly two days from today to selecting items due between today and two days from today, inclusive.

The filter changed from:

```sql
(c.due_gmt::date - current_date) = 2
```

to:

```sql
c.due_gmt::date BETWEEN current_date AND current_date + 2
```

## Impact

This changes row filtering for the `renew` report.

The report now includes items due on:

- today
- tomorrow
- two days from now

Unchanged:

- column names
- column order
- hold-count aggregation logic
- sort order

## Validation note

This was a static SQL change only.
It was not validated against a live Sierra/PostgreSQL environment in this repository.
