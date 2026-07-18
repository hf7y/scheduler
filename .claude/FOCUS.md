# FOCUS — scheduler (what its own nightly job should work on)

The scheduler's Tier 2 job (`/nightly-batch`) is scoped by this file, same
as every other project. Difference: this project is the **meta-tool** that
controls all the other jobs, and it's a **local-only git repo with no
remote**, so its nightly run is a **review gate** — work lands on a
`nightly/<date>` branch for a human to merge, never auto-applied.

## The backlog lives in TODO.md

Unlike the web-app projects, there is **no tracker and no `type=feature`
queue** here — the scheduler has no end users filing reports. `TODO.md` at
the repo root **is** the backlog. Introduce a new idea by adding a line to
it; that's the whole intake mechanism (this was itself TODO item #2's
stated goal — "as simple as editing a text file to introduce a new idea").

## Current focus

Work `TODO.md` top-down by value-over-risk. As of this writing the open
items are:

1. Sweep cadence — sweeps (esp. chezz) may run too often; tune
   `schedule/*.conf` cadence, validate with a `sync-crontab.sh` preview.
2. Auditability — largely addressed by `bin/build-services-view.sh` /
   `services/`; keep it current and extend if gaps show up.
3. Optimal-usage scheduling — token/%-usage reporting per project and
   scheduling jobs into unused capacity windows. Larger; break into
   verifiable pieces, don't attempt wholesale in one unattended run.

## Out of scope for an unattended run

- Anything that can only be tested by waiting for a live cron fire.
- Editing installed wrappers under `~/.local/bin`, the live crontab, or any
  other project's files.
- Adding a git remote / pushing this repo anywhere — that's a human call.
