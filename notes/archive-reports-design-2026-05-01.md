# Archive-reports design note

## Summary

This note captures the revised design for the `archive-reports` Bash script.
The script manages generated CSV files in `data/` by archiving older files into `data/_archive/` and deleting sufficiently old archived files.

The script is intended to be usable both manually and from a daily cron job.
Cleanup eligibility should be based on the Unix timestamp already embedded in generated filenames, not on filesystem modification time.

The script is now implemented in the repository.
No live environment validation was performed as part of the implementation.

## Goals

- provide a simple housekeeping command for generated CSV files
- support unattended daily cron execution
- keep the default workflow centered on repo-local `./data`
- match the existing `generate-reports` filename convention and `upload`'s notion of "latest"
- support relative age thresholds in whole days based on filename epoch
- make destructive actions visible with clear per-file output
- support a safe preview mode with `--dry-run`
- keep the initial implementation simple and portable for Bash on Linux and FreeBSD
- avoid changing `generate-reports` or `upload` behavior automatically

## Proposed script name

- `archive-reports`

## Proposed interface

```bash
./archive-reports [--archive DAYS] [--delete-archived DAYS] [--dry-run] [--help]
```

### Options

- `--archive DAYS`
  - move matching CSV files from `./data` into `./data/_archive`
  - only files whose embedded filename epoch is at least `DAYS * 24 hours` old are eligible

- `--delete-archived DAYS`
  - delete matching CSV files from `./data/_archive`
  - only files whose embedded filename epoch is at least `DAYS * 24 hours` old are eligible

- `--dry-run`
  - print what would happen without moving or deleting files

- `--help`
  - print usage text

Initial expectation:

- at least one of `--archive` or `--delete-archived` should be required

## Why a dedicated script is still the right fit

A daily cron job should call a version-controlled project script rather than embed cleanup logic directly in crontab.

A generic filesystem-retention tool is also not a great fit here because cleanup should use the Unix timestamp embedded in filenames such as `holds-1714521600.csv`, not filesystem metadata such as file modification time.

Given the narrow scope of this repository, a small dedicated Bash script remains the simplest operational approach.

## Path model

The initial version should operate only on the repository's standard directories:

- active data directory: `./data`
- archive directory: `./data/_archive`

The initial version should **not** add:

- `--data-dir`
- `--archive-dir`

This keeps the script simple and avoids unnecessary path-validation complexity.

For cron safety, the implementation should resolve these repo-local paths relative to the script's own location rather than relying on the caller's current working directory.

## Filename age semantics

Cleanup decisions should use the trailing Unix timestamp in the filename.

Examples of valid generated filenames:

- `holds-1714521600.csv`
- `overdue-1714521600.csv`
- `text-patrons-1714521600.csv`

Rules:

- the script should parse the final `-<digits>.csv` suffix as the timestamp
- report-name portions may contain hyphens
- filesystem modification time should **not** be used for cleanup eligibility
- `DAYS` should be a non-negative integer
- `0` means all currently matching files are eligible
- `1` means files whose embedded epoch is at least 24 hours old are eligible
- `2` means files whose embedded epoch is at least 48 hours old are eligible
- in general, a file matches when its embedded epoch is less than or equal to `now - (DAYS * 24 hours)`

This should be documented explicitly in `--help` output.

## Directory handling

Recommended behavior:

- `./data` must exist and be a directory
- `./data/_archive` should be created as needed before archive operations
- if `--delete-archived` is requested and `./data/_archive` does not yet exist, that should be treated as "nothing to delete", not as an error
- if either expected path exists but is not a directory, the script should fail clearly

## Scope of file operations

The script should operate only on top-level regular CSV files.

That means:

- archive candidates come from `data/*.csv`
- delete candidates come from `data/_archive/*.csv`
- no recursive traversal
- ignore placeholder files such as `.keep`
- ignore non-CSV files
- warn and skip any candidate that is not a regular file
- warn and skip any CSV file whose name does not match the expected `*-<epoch>.csv` pattern

This keeps the behavior predictable and avoids accidentally reprocessing nested content.

## Combined operation order

If both `--delete-archived` and `--archive` are supplied in the same run, the script should:

1. delete archived files first
2. archive current data files second

This prevents newly archived files from being immediately deleted during the same invocation.

## Output and exit behavior

The script should print useful operational information.

Recommended behavior:

- print one line per file action
- print warnings when a file cannot be processed cleanly or has an unexpected filename
- print a summary at the end
- make `--dry-run` output obvious

Examples of action output:

- `Archived: data/holds-1714521600.csv -> data/_archive/holds-1714521600.csv`
- `Deleted archived file: data/_archive/holds-1714435200.csv`
- `Would archive: ...`
- `Would delete archived file: ...`
- `Skipping unexpected filename: data/manual-export.csv`

Recommended exit behavior:

- invalid arguments should cause a non-zero exit
- failed move/delete operations should cause a non-zero exit
- warnings about unexpected filenames may remain non-fatal as long as they are clearly reported

This makes unattended cron runs easier to monitor.

## Overwrite behavior

When archiving a file, if the destination file already exists in the archive directory, the script should:

- overwrite the existing archived file
- print a warning before doing so

This was chosen explicitly over skip-and-warn behavior.

## Portability and implementation approach

The implementation should stay generally portable across normal Bash environments on Linux and FreeBSD.

Recommended implementation style:

- use Bash plus basic utilities already expected on a typical Linux or FreeBSD system
- prefer Bash globbing and shell parsing for candidate selection and filename inspection
- avoid depending on filesystem metadata for age checks
- avoid introducing GNU/BSD-specific timestamp-parsing behavior where it is not necessary

This should keep the implementation straightforward and reduce cross-platform surprises.

## Recommended examples for help text

```bash
./archive-reports --archive 2
./archive-reports --delete-archived 30
./archive-reports --archive 2 --delete-archived 30
./archive-reports --dry-run --archive 2 --delete-archived 30
./archive-reports --archive 0
```

## Impact on existing workflow

This script is intended to be a standalone housekeeping tool that may be run manually or from a separate daily cron entry.
It should not be wired automatically into `generate-reports` or `upload`.

Important operational notes:

- `upload` looks for the latest supported files in `data/`
- archiving files out of `data/` changes what `upload` can see
- automated cleanup should be scheduled after any review or upload workflow that depends on files remaining in active `data/`
- using `--archive 0` in an unattended schedule can immediately remove all matching CSVs from active `data/`, so it should be used with care

## Stretch goals for later

The following are intentionally out of scope for the initial version, but are reasonable follow-up ideas:

- overlap protection / locking for cron runs
- more advanced logging or reporting if operational need emerges
- configurable data/archive paths if a real use case appears later

## Implementation notes

The initial implementation also adds:

- a tracked placeholder file at `data/_archive/.keep`
- `README.md` updates documenting the new script and its cron-friendly workflow
- an example cron invocation in documentation

Minimum local checks after implementation should include:

```bash
bash -n generate-reports
./generate-reports --help
bash -n upload
./upload --help
bash -n archive-reports
./archive-reports --help
```

## Bottom line

The recommended design is a standalone script:

```bash
./archive-reports [--archive DAYS] [--delete-archived DAYS] [--dry-run]
```

with these core semantics:

- relative-age thresholds in whole days
- eligibility based on the Unix timestamp embedded in the filename
- fixed repo-local paths: `data/` and `data/_archive/`
- top-level `*.csv` files only
- delete archived files first, then archive active files
- overwrite archive collisions and warn
- explicit per-file actions and a final summary
- suitable for a separate daily cron entry
- locking deferred as a later enhancement
