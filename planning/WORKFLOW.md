# Planning workflow

`TASKS.md` is the index of substantial work that may need to be resumed, with completed entries retained for history. Each task has one line with a stable ID, creation date, status, short description, and exactly one link to its plan document. The plan is the task's entry point: read it before resuming work, keep decisions, progress, blockers, and next steps there, and link from it to any other relevant documents. Do not link to supporting documents directly from the task index.

- When the user asks to track work or agrees to tracking, create or update one plan document in `docs/` and add one entry pointing to that plan in `TASKS.md`. Do not index routine, one-off changes or add entries without the user's consent.
- Use `- T-001 | YYYY-MM-DD | planned | Description | [plan](docs/topic.md)` as the format. Links in the index are relative to `TASKS.md`. Assign the next unused sequential ID; never reuse IDs. Use the current date when the entry is created.
- Keep entries in creation order, oldest first. Do not change an entry's ID or creation date when its description, status, or document changes.
- Use only these statuses: `planned`, `in-progress`, `blocked`, `done`. Set `in-progress` when work starts, `blocked` when progress cannot continue (explain why in the linked plan), and `done` only after the user explicitly confirms completion. Implementation and passing checks alone are not acceptance; keep the task `in-progress` with an explicit "awaiting user review/confirmation" note in its plan until then.
- Before finishing work on an indexed task, update its status and plan to reflect what was done and what remains. If more work remains, leave a concrete next step in the plan.
- Keep each index entry on one line. Ensure links remain valid if documents are moved.
