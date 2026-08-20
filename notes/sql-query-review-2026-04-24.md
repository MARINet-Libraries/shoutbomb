# SQL query review

## Scope

This note captures a static review of the current report SQL files:

- `sql/holds.sql`
- `sql/overdue.sql`
- `sql/renew.sql`
- `sql/text-patrons.sql`

No live PostgreSQL/Sierra execution was performed during this review, so the findings below are based on query structure and repository conventions rather than runtime validation.

## Highest-priority fixes

### 1. `sql/overdue.sql` and `sql/renew.sql` can overcount holds *(fixed on 2026-04-24)*

This is the already-documented issue in:

- `notes/hold-count-aggregation-issue.md`

Both queries join bib-level holds and item-level holds before aggregation, which can multiply rows and inflate:

- `COUNT(ih.id)`
- `COUNT(bh.id)`

### Resolution

This was fixed on 2026-04-24 by changing the queries to use:

- `COUNT(DISTINCT ih.id)`
- `COUNT(DISTINCT bh.id)`

See:

- `notes/hold-count-aggregation-issue.md`

A future refactor could still move these counts into pre-aggregated subqueries / CTEs for clarity, but the immediate overcounting problem is addressed.

### 2. `sql/overdue.sql` and `sql/renew.sql` do not constrain an item to one bib row

`sql/holds.sql` joins `sierra_view.bib_record_item_record_link` with:

```sql
AND bil.bibs_display_order = 0
```

That implies this repository already treats the primary bib link as the intended one-record choice for item-based reporting.

By contrast, `sql/overdue.sql` and `sql/renew.sql` use:

```sql
JOIN sierra_view.bib_record_item_record_link AS bil ON (bil.item_record_id = i.id)
```

with no filter to pick a single bib.

If an item is attached to more than one bib, a single checkout can produce multiple grouped rows with different bib/title values. That can also interact badly with the hold-count aggregation issue.

### Recommendation

After fixing the hold-count logic, make the bib selection rule explicit.

Most likely fix:

- use the same `bil.bibs_display_order = 0` rule already used in `sql/holds.sql`

If a different bib-selection rule is desired, it should be documented because it changes report semantics.

### 3. `sql/holds.sql` title fallback is not doing what it appears to do

`sql/holds.sql` selects the title as:

```sql
COALESCE(s.content, bt.field_content)
```

which suggests a fallback from MARC `245$a` to the bib title varfield.

However, `sierra_view.subfield AS s` is joined with an inner `JOIN`:

```sql
JOIN sierra_view.subfield AS s ON (
    s.record_id = b.id
    AND s.marc_tag = '245'
    AND s.tag = 'a'
)
```

That means rows without a matching `245$a` never reach the `SELECT` list, so `bt.field_content` is not actually acting as a fallback for missing `245$a` rows.

### Recommendation

Decide what the intended behavior is:

- if the report should allow a varfield title fallback, change the title joins so the fallback can actually happen
- if records without `245$a` should be excluded, remove the misleading fallback expression and document that requirement

As written, the query looks more forgiving than it really is.

## Secondary fixes and follow-up questions

### 4. `sql/holds.sql` has an unused join

This join is present but not referenced anywhere else in the query:

```sql
LEFT JOIN sierra_view.varfield AS ic ON (
    ic.record_id = i.id
    AND ic.varfield_type_code = 'c'
    AND ic.occ_num = 0
)
```

### Recommendation

Remove it unless it is being kept intentionally for an upcoming change.

### 5. `RIGHT JOIN` usage in `holds`, `overdue`, and `renew` obscures the real query shape

Examples:

- `sql/holds.sql` starts from `sierra_view.hold AS h` and then uses several `RIGHT JOIN`s
- `sql/overdue.sql` and `sql/renew.sql` use `RIGHT JOIN sierra_view.patron_record AS p ON (p.id = c.patron_record_id)`

Given the later `WHERE` clauses and required joins, these behave like inner joins in practice.

### Recommendation

When the queries are next edited, rewrite these as ordinary `JOIN`s for clarity.

This is mostly a readability and maintenance fix, not the first thing to change.

### 6. `sql/overdue.sql` and `sql/renew.sql` may still allow row multiplication from barcode/title joins

These queries join item barcodes with:

```sql
JOIN sierra_view.varfield AS ib ON (
    ib.record_id = i.id
    AND ib.varfield_type_code = 'b'
)
```

There is no `occ_num = 0` restriction here, unlike some of the more targeted joins elsewhere in the repository.

The title join also assumes a single matching `245$a` row.

### Recommendation

Verify whether Sierra data guarantees one matching barcode row and one matching title row for the records used here.

If not, consider:

- restricting the barcode join to one occurrence, or
- using a more direct barcode source such as `item_record_property`, if that better matches the local data model

This is a likely cleanup item, but it should be verified against real data before changing output semantics.

### 7. `sql/overdue.sql` and `sql/renew.sql` should confirm the intended meaning of `bib_holds`

These queries now count item holds with:

```sql
COUNT(DISTINCT ih.id)
```

where `ih` is filtered to:

```sql
ih.status = '0'
```

But bib holds are joined as:

```sql
LEFT JOIN sierra_view.hold AS bh ON (bh.record_id = b.id)
```

with no status filter at all.

That may be correct, but it is worth confirming.

### Recommendation

Check whether `bib_holds` is intended to mean:

- all bib-level hold rows, or
- only active/requestable bib holds

If the report is supposed to describe current hold pressure, it may need an explicit status rule rather than counting every matching bib hold row.

### 8. `sql/text-patrons.sql` likely needs output-hardening before semantic changes

This query is simple, but a few things are worth reviewing:

- no `ORDER BY`, so output order is not guaranteed
- one patron may produce multiple rows if multiple matching phone rows exist
- phone normalization removes spaces, hyphens, and periods, but not every possible formatting character
- there is no explicit filter to remove blank normalized numbers

### Recommendation

Before changing the query, inspect a sample extract and confirm the actual downstream expectations for Shoutbomb:

- should there be exactly one row per patron?
- what phone-number format is required?
- should invalid or blank numbers be excluded at query time?

This feels more like a data-quality decision than a pure syntax fix.

## Suggested order of work

1. Constrain `sql/overdue.sql` and `sql/renew.sql` to one bib per item
2. Fix or clarify the title fallback behavior in `sql/holds.sql`
3. Remove unused joins and simplify `RIGHT JOIN` usage
4. Review `sql/text-patrons.sql` with sample data before changing row-selection rules

## Bottom line

The most important likely correctness issues were in `sql/overdue.sql` and `sql/renew.sql`.

The hold-count logic there has now been corrected.

The next fix I would make is making bib selection explicit so a single checkout does not fan out across multiple bib rows.
