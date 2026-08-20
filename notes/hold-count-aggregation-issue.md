# Hold count aggregation issue

## Summary

A review identified an aggregation problem in these two report queries:

- `sql/overdue.sql`
- `sql/renew.sql`

Both queries calculate:

- `item_holds`
- `bib_holds`

from joined hold tables.

## Original problem

The original versions joined both hold tables before aggregation:

- `LEFT JOIN sierra_view.hold AS bh ON (bh.record_id = b.id)`
- `LEFT JOIN sierra_view.hold AS ih ON (ih.record_id = i.id AND ih.status = '0')`

Because both joins can return multiple rows for the same checkout row, the result set can multiply rows before the `GROUP BY` happens.

Example:

- if one item has 2 matching `ih` rows
- and the related bib has 3 matching `bh` rows

then the joined result can produce 6 rows for that one logical checkout record.
This causes:

- `COUNT(ih.id)` to be overstated
- `COUNT(bh.id)` to be overstated

## Applied fix

On 2026-04-24, both queries were updated from:

```sql
COUNT(ih.id)
COUNT(bh.id)
```

to:

```sql
COUNT(DISTINCT ih.id)
COUNT(DISTINCT bh.id)
```

The reports now use:

- `NULLIF(COUNT(DISTINCT ih.id), 0) AS item_holds`
- `NULLIF(COUNT(DISTINCT bh.id), 0) AS bib_holds`

## Why this fix was chosen

`COUNT(DISTINCT ...)` is the smallest targeted change that corrects the hold overcounting caused by join multiplication while preserving the rest of the query shape.

## Remaining caveat

This fix addresses inflated hold counts from the combined hold joins.

It does **not** by itself address other possible sources of duplicated report rows, such as multiple bib links for the same item in:

- `sierra_view.bib_record_item_record_link`

That should be reviewed separately if checkout rows are still appearing more than once.

## Validation note

This was a static SQL fix based on query structure review.
It was not validated against a live Sierra/PostgreSQL environment in this repository.
