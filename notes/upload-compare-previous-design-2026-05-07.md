# Upload compare-previous design note

## Status

Deferred. Do not implement for now.

## Summary

This note originally proposed adding an optional `--compare-previous` mode to `./upload`.

The original goal was simple: do not upload unchanged report contents.
The proposed behavior was to compare the latest local CSV for each selected report against the previous local CSV for that same report and upload only when the files differed.

After review, that design is **not** recommended for implementation in the current system.
The reason is a correctness issue around failed uploads:
comparing the latest local CSV to the previous local CSV does **not** tell us whether the latest content was ever uploaded successfully.

Solving that safely would require extra state or extra remote inspection, which adds more complexity than desired for this repository.
For now, `./upload` should remain unchanged and continue uploading the latest selected file unconditionally.

No live environment validation was performed as part of this design review.

## Original goal

The original intent behind this idea was still reasonable:

- avoid uploading unchanged report contents
- preserve current `./upload` behavior by default
- keep separation of concerns clean between report generation and upload
- rely on existing timestamped CSV artifacts in `data/`
- avoid requiring remote-state inspection or remote file comparison
- keep the feature simple enough for manual use and cron use

## Proposed interface that was considered

The idea under consideration was:

```bash
./upload [--reports REPORT [REPORT ...]] [--compare-previous] [--help] [-H HOST] [-P PORT] [-v]
```

with a new option:

- `--compare-previous`
  - for each selected report, compare the latest local CSV in `./data` with the previous local CSV for that same report
  - upload the latest file only if the contents differ
  - if no previous local CSV exists, upload the latest file

This would have been an additive, non-default behavior.
Running `./upload` without the new flag would have continued to behave exactly as it does now.

## Why the design is being deferred

The blocking issue is a failed-upload retry gap.

A previous-local-file comparison can incorrectly skip a report even though the newest content was never uploaded successfully.

Example:

1. `holds-1715000000.csv` is generated and uploaded successfully
2. `holds-1715086400.csv` is generated with changed contents
3. upload of `holds-1715086400.csv` fails
4. later, another run generates `holds-1715172800.csv` with the **same contents** as `holds-1715086400.csv`
5. a `--compare-previous` implementation that compares only the latest two local files would compare:
   - `holds-1715172800.csv`
   - `holds-1715086400.csv`
6. those two files match, so the script would skip upload
7. but the remote system would still only have the older successfully uploaded contents from `holds-1715000000.csv`

That means the script could suppress a needed retry after a failed upload.

This is a real correctness problem, not just a minor edge case.
It undermines the main expectation of the upload script: if changed content has not yet been transferred successfully, a later run should still try to send it.

## Why simple local history is not enough

The problem is that the comparison baseline in the original design is:

- the latest generated local file
- the previous generated local file

But the baseline that actually matters for safe skipping is:

- the latest generated local file
- the last content that was uploaded successfully

Those are not always the same thing.

As soon as an upload can fail, local generation history and successful upload history can diverge.
Once that happens, comparing only local generated files is not sufficient.

## Safer alternative considered, but not recommended right now

A safer design would be to store local upload state, such as a per-report hash of the last successfully uploaded file, for example under a state directory like:

- `.state/upload/holds.sha256`
- `.state/upload/renew.sha256`

Under that approach, `./upload` would:

1. find the latest local CSV for a report
2. compute a content hash
3. compare that hash to the stored hash of the last successfully uploaded content
4. skip only when they match
5. update the stored hash only after a successful upload

That approach would solve the failed-upload retry gap.

However, it introduces additional complexity that this repository does not currently have and that is not desired at this time:

- persistent local state to create and maintain
- new failure modes around missing or corrupt state
- more operator-facing behavior to explain
- possible drift between local state and remote reality after out-of-band changes
- a more complex mental model for what is currently a very simple upload script

Because the system is intentionally simple, that additional complexity outweighs the benefit for now.

## Decision

Do **not** implement `--compare-previous` at this time.

Keep the current `./upload` behavior:

- find the latest supported CSV for each selected report in `./data`
- upload that latest file unconditionally

This preserves the current strengths of the script:

- simple behavior
- no extra state to manage
- no risk of skipped retries caused by local-only comparison
- easier operator expectations for manual and cron usage

## Guidance for any future revisit

If this idea is revisited later, do **not** revive the original previous-local-file comparison design as written.

Any future implementation should be based on one of these instead:

- locally tracked state representing the last successful upload per report
- remote-state inspection that can safely determine whether the newest content has already been transferred

The original idea of comparing only the latest and second-latest local CSV files is not sufficient if upload failures must be handled correctly.

## Bottom line

The original `--compare-previous` proposal was appealing because it seemed simple and could rely only on existing files in `data/`.

After review, it is being deferred because that simplicity is misleading:
a local latest-vs-previous comparison can incorrectly skip retries after failed uploads.
Fixing that requires added state or added remote-awareness, which is more complexity than desired for this project right now.

For now, the correct decision is to leave `./upload` as-is.