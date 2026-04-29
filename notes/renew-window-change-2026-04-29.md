# Renew report due window change

## Summary

On 2026-04-29, `sql/renew.sql` was changed from selecting items due exactly two days from today to selecting items due between today and two days from today, inclusive.

The filter changed from:

```sql
(c.due_gmt::date - current_date) = 2
```

to:

```sql
c.due_gmt >= current_date
AND c.due_gmt < current_date + INTERVAL '3 days'
```

## Impact

This changes row filtering for the `renew` report.

The report now includes items due on:

- today
- tomorrow
- two days from now

The query now expresses that window as a timestamp range on `c.due_gmt` instead of casting `c.due_gmt` to `date`, which may allow a plain index on `c.due_gmt` to be used more effectively.

Unchanged:

- column names
- column order
- hold-count aggregation logic
- sort order

## Validation note

This was a static SQL change only.
It was not validated against a live Sierra/PostgreSQL environment in this repository.
