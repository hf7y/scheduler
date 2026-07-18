# FOCUS — scheduler (what its own nightly job should work on)

The scheduler's Tier 2 job (`/nightly-batch`) is scoped by this file, same
as every other project. Difference: this project is the **meta-tool** that
controls all the other jobs, so its nightly run is a **review gate** — work
lands on a `nightly/<date>` branch for a human to merge, never auto-applied.

The repo now has a GitHub remote (`git@github.com:hf7y/scheduler.git`),
pushed by a human. The nightly still does NOT push or merge on its own.

## This project dogfoods its own system

The scheduler uses the exact pieces every registered project uses, no
bespoke ones:

- **Its files live in `.claude/scheduler/`** (this folder): `FOCUS.md`,
  `QUESTIONS.md`, `schedule.conf`. Registration symlinks them into
  scheduler's aggregation folders (`focus/`, `questions/`, `schedule/`) —
  `schedule/scheduler.conf` is already a symlink back to
  `.claude/scheduler/schedule.conf`.
- **Reports** go to `~/reports/scheduler/` like everyone else.
- **The backlog lives HERE, in this file** (the section below) — not in a
  separate `TODO.md` anymore (retired 2026-07-18). The scheduler has no
  tracker and no end users filing reports, so FOCUS.md is both scope *and*
  backlog. Introduce an idea by adding a line to the Backlog section; that's
  the whole intake mechanism.
- **Questions** (`.claude/scheduler/QUESTIONS.md`) for anything needing a
  human decision — appended, never acted on unilaterally.

## Current focus

1. **Migrate every project's `schedule/*.conf` onto the new
   `bin/scheduler-run` entrypoint, per `MIGRATION.md`.** The generic
   entrypoint + backwards-compat mechanism landed 2026-07-18; the confs are
   still on legacy `*_SCRIPT` wrappers. For each of `chezz`, `vkv-inventory`,
   `home-assistant`, `wtul`: READ its `~/.local/bin/<...>-loop.sh` wrapper
   (reading outside the repo is fine; **editing** it is not), copy each
   config variable into that project's `schedule/<project>.conf` runtime
   fields (`REPO_URL`, `<TIER>_PROMPT`, `<TIER>_MAX_TURNS`, `<TIER>_MODEL`,
   `<TIER>_PRECHECK_CMD`, …), and **leave the `*_SCRIPT` line in place**
   (commented) so nothing flips until a human drops it and runs `--apply`.
   Verify with `bin/sync-crontab.sh` (preview, NO `--apply`): output must
   stay byte-identical while `*_SCRIPT` is still set. One commit per project.

2. **Propagate the self-contained-folder model to the other projects** (what
   scheduler just adopted): each project's scheduler files
   (`FOCUS.md`/`QUESTIONS.md`) grouped under `.claude/scheduler/`, with a
   `SCHEDULER_SUBDIR=".claude/scheduler"` line in its conf so
   `bin/sync-crontab.sh` points its `focus/`+`questions/` symlinks there.
   This touches other projects' `.claude/` layout and their `/nightly-batch`
   command's FOCUS path — write it up as a per-project proposal in the
   report (and a QUESTIONS entry) rather than editing other repos from here.

## Backlog (the intake — add a line to propose an idea)

- **Sweep cadence** — sweeps (esp. chezz) may run too often; tune
  `schedule/*.conf` cadence, validate with a `sync-crontab.sh` preview.
- **Auditability** — largely addressed by `bin/build-services-view.sh` /
  `services/` and the `focus/`+`questions/` aggregation; keep current,
  extend if gaps show up.
- **Optimal-usage scheduling** — token/%-usage reporting per project and
  scheduling jobs into unused capacity windows; ideally never hit the daily
  usage-limit window while maximizing weekly usage. Larger; break into
  verifiable pieces (e.g. a `USAGE_GATE_CMD` sibling to `PRECHECK_CMD`, plus
  per-run token logging into the state dir that `morning-report.sh` sums).
  Don't attempt wholesale in one unattended run.

## Out of scope for an unattended run

- Anything that can only be tested by waiting for a live cron fire.
- Editing installed wrappers under `~/.local/bin`, the live crontab, or any
  other project's files.
- Pushing/merging this repo — a human call (the remote exists now, but the
  nightly still never pushes).
