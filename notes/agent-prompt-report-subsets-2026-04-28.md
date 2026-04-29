# Agent prompt: report subset support

Work in `/usr/home/cory/projects/shoutbomb`.

Read first:
- `AGENTS.md`
- `generate-reports`
- `upload`
- relevant usage sections in `README.md`

Task:
Add `--reports REPORT [REPORT ...]` support to both scripts.

Requirements:
- Keep current defaults:
  - `./generate-reports` generates all `sql/*.sql`
  - `./upload` uploads all supported reports
- `--reports` limits the run to one or more named reports
- Accept base names only, not filenames:
  - valid: `holds`
  - invalid: `holds.sql`
- Fail the full run if any requested report name is invalid, with a clear error and a list of valid names

`generate-reports`:
- Default behavior stays the same
- When `--reports` is given, run only those reports
- Validate against discovered `sql/*.sql` basenames
- Preserve:
  - shared timestamp per run
  - `<report>-<epoch>.csv` filenames
  - header behavior
  - partial-file cleanup on failure
  - non-zero exit if any selected report fails

`upload`:
- Default behavior stays the same
- When `--reports` is given, upload only those supported reports
- Validate against the supported upload mapping
- Preserve upload destinations exactly:
  - `holds` -> `/Holds`
  - `renew` -> `/Renew`
  - `overdue` -> `/Overdue`
  - `text-patrons` -> `/text_patrons`
- For selected reports only, upload the latest matching `<report>-<epoch>.csv`
- Preserve strict host key checking and non-zero exit if any selected upload fails or selected file is missing

CLI/doc updates:
- Update both `--help` outputs
- Update `README.md` usage/behavior docs
- Do not add scheduling logic; scheduling will be external (cron)
- Do not change SQL semantics, output naming, supported report names, or upload destinations

Validation:
- `bash -n generate-reports`
- `./generate-reports --help`
- `bash -n upload`
- `./upload --help`

Deliverable:
- Make the changes
- Summarize what changed
- Mention any edge-case decisions
- State that validation was static/help-path only unless more was actually run
