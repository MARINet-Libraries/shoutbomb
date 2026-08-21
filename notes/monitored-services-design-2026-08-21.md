# Monitored services design

## Summary

Monitoring and logging orchestration is shared by service entrypoints under `services/` without changing the behavior of the root `generate-reports`, `upload`, or `archive-reports` scripts.

The service entrypoints are:

- `services/generate-and-upload`
- `services/archive-reports`

Both source `services/lib/monitored-job.sh` for `.env` loading, Healthchecks.io lifecycle pings, signal/exit handling, and the existing logger pipeline.

## Per-workflow Healthchecks.io URLs

A Healthchecks.io check represents one independently scheduled cron workflow, not one executable. Every service invocation therefore requires:

```text
--healthcheck-url-env HEALTHCHECKS_<JOB>_URL
```

The option names a variable in the project `.env`; the full private URL is not placed on the command line or written to logs. There is no generic `HEALTHCHECKS_URL` fallback.

This allows separate checks for workflows that reuse the same service, including primary report generation/upload and renewal generation/upload.

## Preserved behavior

The service refactor does not change root-script behavior.

- Generate and upload arguments are passed as before.
- Upload still runs only after successful generation.
- Archive arguments are passed unchanged to `archive-reports`.
- Logger tags remain `shoutbomb-generate-reports`, `shoutbomb-upload`, and `shoutbomb-archive-reports`.
- Healthchecks.io requests remain best-effort and do not alter the underlying workflow status.
- Archive remains a separately scheduled job.

## Operational configuration

Example settings:

```dotenv
HEALTHCHECKS_PRIMARY_REPORTS_URL=https://hc-ping.com/<primary-id>
HEALTHCHECKS_RENEWALS_URL=https://hc-ping.com/<renewals-id>
HEALTHCHECKS_ARCHIVE_URL=https://hc-ping.com/<archive-id>
```

Variable names must match `HEALTHCHECKS_*_URL` and contain a non-empty value. Each scheduled invocation selects the appropriate variable explicitly.

## Validation limits

Local syntax, help, argument-validation, and mocked Healthchecks.io lifecycle checks can be performed without database or SFTP access. No live PostgreSQL/Sierra query execution or live SFTP upload validation is implied by those checks.
