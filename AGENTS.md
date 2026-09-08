# AGENTS.md

## Project map and upkeep

- `sql/*.sql`: standalone Sierra/PostgreSQL report queries.
- `generate-reports`, `upload`, `archive-reports`: canonical CSV export, SFTP upload, and retention entrypoints.
- `services/`: monitored cron entrypoints; both use `services/lib/monitored-job.sh`.
- `check` and `tests/`: canonical local static checks and fully mocked Bats behavior tests.
- `notes/`: caveats, history, and deferred designs. Check note status/date against current code.
- `data/` and `data/_archive/`: generated artifacts, never source-of-truth logic.
- `.env.example`: configuration template; the real ignored `.env` may contain secrets.
- Keep this file current when layout, interfaces, configuration, validation, or workflows change. Document implemented behavior, not proposals.

## Guardrails

- Assume no live PostgreSQL/Sierra, SSH/SFTP, remote server, or Healthchecks.io access. Never claim query, upload, or monitoring validation unless performed.
- Scripts needing configuration resolve the project-root `.env` from their own location. Do not inspect, modify, or commit it unless explicitly requested.
- Never add real secrets or private values to `.env.example`, code, docs, or logs. Preserve intentional public defaults; otherwise use placeholders and `.env` settings.
- Tests must use temporary project fixtures and fake configuration; never let routine tests read the real `.env`, inspect working CSVs, write to real syslog, or contact live services.
- Preserve report, output, upload, retention, and monitoring behavior unless the task requests a change.
- Do not inspect generated CSVs unless the task concerns output. Do not run non-dry-run retention merely for validation.

## Read minimally

- Single-report work: read its `sql/<name>.sql` and specifically referenced caveat notes only.
- Export work: read `generate-reports`; upload work: read `upload` (its supported-report/destination mapping is canonical).
- Retention work: read `archive-reports`; consult `notes/archive-reports-design-2026-05-01.md` for semantic changes or rationale.
- Monitoring work: read the affected `services/` entrypoint and shared helper; for non-trivial changes also read `notes/monitored-services-design-2026-08-21.md`.
- Configuration, dependency, CLI, or cron changes: read `.env.example` and relevant `README.md` sections.
- Treat proposal, plan, and historical notes as context, not current requirements.

## SQL changes

- Keep one runnable, preferably direct `SELECT` query per file. Avoid `psql` meta-commands, transaction control, and unsupported session setup.
- Follow nearby style: uppercase keywords, clear joins/aliases, and one selected expression per line when practical.
- Preserve column names/order, filtering, aggregation, and sorting unless requested; use explicit `ORDER BY` when determinism matters.
- For `overdue.sql` or `renew.sql`, first read `notes/hold-count-aggregation-issue.md`. For due-window changes, also read the applicable `notes/*-window-change-2026-04-29.md`. For broader refactors, check `notes/sql-query-review-2026-04-24.md` against current SQL.
- Call out semantic changes and document non-trivial downstream impact in `notes/`.

## Shell changes

- Keep Bash readable and safe. Preserve defaults, argument pass-through, exit statuses, and script-relative path resolution unless requested.
- Root entrypoints must remain independently usable; monitored services orchestrate rather than duplicate their logic.
- `generate-reports` discovers `sql/*.sql`; `upload` owns upload support/destinations; `archive-reports` owns retention validation.
- Configuration changes require matching help, `.env.example`, and `README.md` updates. `.env` must remain valid Bash input.
- After shell changes, run:

  ```bash
  for f in generate-reports upload archive-reports services/generate-and-upload services/archive-reports services/lib/monitored-job.sh; do bash -n "$f"; done
  for f in generate-reports upload archive-reports services/generate-and-upload services/archive-reports; do "./$f" --help >/dev/null; done
  ```

- With Bats-core and ShellCheck installed, also run `./check` after shell or test changes.

## Operational contracts

### Reports

- A SQL basename is its CLI report name and generated filename prefix. Generation auto-discovers reports; upload support is explicit.
- When adding/removing/renaming reports, update `upload` if applicable, help text, the `README.md` inventory, relevant notes, and documented service/cron lists. Keep generation-only reports out of upload lists.

### Retention

- Use fixed top-level paths `data/*.csv` and `data/_archive/*.csv`; age comes from the trailing `-<epoch>.csv`, not mtime.
- With both operations, delete archived files before archiving active ones; collisions overwrite with a warning. Preserve non-destructive `--dry-run` and schedule retention after upload/review.
- Test file operations in an isolated fixture, not against working artifacts.

### Monitoring

- `services/generate-and-upload` uploads only after successful generation; generation/upload lists are independent pass-through arguments. `services/archive-reports` passes retention arguments through.
- Each invocation requires `--healthcheck-url-env HEALTHCHECKS_*_URL`; keep the private URL out of arguments and logs.
- Preserve logger tags `shoutbomb-generate-reports`, `shoutbomb-upload`, and `shoutbomb-archive-reports`; do not add duplicate logger wrappers to cron examples. `SHOUTBOMB_LOGGER_PATH` defaults to `/usr/bin/logger` and exists so isolated tests can substitute a fake logger.
- Healthchecks.io lifecycle pings are best-effort and never replace workflow status. Shared-helper changes require validating both services.

## Changes to call out

Explicitly identify changes to output schema/rows/order, report names/files/timestamps/headers, upload selection/support/destinations, retention semantics, CLI/config/exit behavior, logger tags, monitoring lifecycle, or generation-to-upload gating. Update `README.md`, `.env.example`, and/or `notes/` wherever their contract changes.

## Validation limits

- Local validation may cover syntax, help, arguments, isolated filesystems, and mocked commands. `./check` is the canonical local entrypoint.
- Live query, upload, and monitoring checks require their respective environments and credentials. Never ping production checks during routine tests.
- State exactly what ran; distinguish static/mocked checks from live integration validation.
