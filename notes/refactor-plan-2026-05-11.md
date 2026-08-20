# Project refactor plan

## Status
Proposed on 2026-05-11 from static review only; no live PostgreSQL/Sierra queries were executed and no live SFTP upload validation was performed.

## Goals
- Improve operational safety.
- Reduce duplication across scripts and docs.
- Make behavior easier to validate locally.
- Make SQL intent clearer without changing report behavior accidentally.
- Preserve current filename conventions, supported report names, and upload destinations unless intentionally changed.

## Non-goals
- Do not rewrite the project out of Bash for now.
- Do not change the generated CSV filename format.
- Do not change report columns, row filters, sort order, upload destinations, or supported report names unless explicitly planned and documented.
- Do not add persistent upload-state tracking at this time.

## Recommended implementation order
1. Add locking and atomic writes in `generate-reports`, `upload`, and `archive-reports`.
2. Add `check.sh` plus lightweight behavior tests with fake `psql` and `sftp` binaries.
3. Centralize upload report metadata in one shared config and derive validation/help from it.
4. Extract shared shell helpers such as `.env` loading, `array_contains()`, and small error/log helpers.
5. Refactor `sql/overdue.sql` and `sql/renew.sql` around explicit base rows, explicit bib selection, and pre-aggregated hold counts.
6. Simplify `sql/holds.sql` by replacing `RIGHT JOIN`s, removing unused joins, and clarifying title fallback behavior.
7. Clarify and harden `sql/text-patrons.sql` after documenting expected patron cardinality and phone normalization rules.
8. Clean up `README.md` and add `notes/INDEX.md` so active caveats and historical notes are easier to find.

## Detailed plan
- `generate-reports`, `upload`, `archive-reports`, and a new `lib/lock.sh`: add one project-wide lock so concurrent runs cannot race on `data/`.
- `generate-reports`: write each CSV to a temp file and rename it into place only after `psql` succeeds.
- `README.md` and an optional `run-cycle`: document or add a simple lock-aware cron orchestration path after locking lands.
- `check.sh`: run `bash -n` and `--help` checks for all three scripts, and run `shellcheck` when available.
- `tests/`: add lightweight shell tests that mock `psql` and `sftp` and exercise report selection, latest-file detection, and archive behavior.
- `upload`, a new `lib/upload-reports.sh` or `config/upload-reports.tsv`, and `README.md`: move supported upload report mapping into one canonical source.
- `generate-reports`, `upload`, and a new `lib/env.sh`: share `.env` existence/readability/loading logic while keeping per-script required-variable validation local.
- `generate-reports`, `upload`, `archive-reports`, and a new `lib/common.sh`: extract only low-complexity shared helpers and keep entrypoint scripts readable.
- `generate-reports`, `upload`, and `archive-reports`: standardize error prefixes, option handling, and exit-code conventions.
- `generate-reports`, `upload`, and `archive-reports`: explicitly validate any new dependency such as `flock` and document fallback behavior if it remains optional.
- `sql/overdue.sql`: refactor to make one checkout row map to one final report row before hold counts are joined in.
- `sql/renew.sql`: mirror the `overdue` refactor pattern and restate the overdue-exclusion rule more clearly.
- `sql/holds.sql`: replace `RIGHT JOIN`s with clearer `JOIN` and `LEFT JOIN`s, remove the unused `ic` join, and either make title fallback real or remove the misleading fallback.
- `sql/text-patrons.sql`: document whether one row per patron is required and then tighten phone normalization and filtering to match that contract.
- `notes/INDEX.md`: separate active operational caveats, historical changes, deferred design ideas, and backlog items.
- `README.md`: keep setup and operator workflow concise, and document locking and `check.sh` once implemented.

## Acceptance criteria
- Concurrent runs cannot modify or inspect unstable `data/` contents at the same time.
- Failed report generation never leaves a partial final CSV behind.
- `./check.sh` passes locally without requiring live PostgreSQL/Sierra or SFTP access.
- Upload report support is defined in one place and reflected consistently in script behavior and docs.
- SQL refactors preserve current output unless a behavior change is explicitly documented in `notes/`.
- Docs clearly distinguish current caveats from historical design notes.

## File-by-file summary
- `generate-reports`: add locking, atomic writes, shared env/helper sourcing, and tests around `--reports`, failures, and output cleanup.
- `upload`: add locking, source canonical report mapping, keep unconditional latest-file upload behavior, and test latest-file and missing-file paths.
- `archive-reports`: add locking, preserve epoch-based retention behavior, and test archive/delete order plus `--dry-run`.
- `sql/holds.sql`: refactor for readability without changing row selection unless intentionally documented.
- `sql/overdue.sql`: refactor for explicit row cardinality, deterministic bib selection, and clearer hold aggregation.
- `sql/renew.sql`: refactor alongside `sql/overdue.sql` and preserve current row-filter semantics unless intentionally changed.
- `sql/text-patrons.sql`: only refactor after the downstream output contract is explicitly documented.
- `README.md`: update only as implementation lands so operator docs stay aligned with actual behavior.
- `notes/`: add or update notes whenever SQL semantics, filenames, supported report names, or upload destinations change.

## Risks to avoid
- Do not change CSV column names, column order, row filters, aggregation meaning, sort order, filename conventions, supported report names, or upload destinations accidentally.
- Do not make `generate-reports` depend on upload-only report metadata.
- Do not add so much shared-library indirection that the Bash entrypoints become harder to read than the current scripts.
- Do not treat static tests as proof of live PostgreSQL/Sierra or SFTP correctness.

## Practical next step
1. Add `check.sh`.
2. Add project-wide locking.
3. Make `generate-reports` write atomically.
