# Scheduler

Coordinates autonomous `claude -p` jobs across several projects — nightly
feature/maintenance batches and frequent bug sweeps — on top of plain cron.
It is **not a daemon**: cron is the coordinator. This repo is a shared engine
+ a config registry + a report aggregator.

For the *why* behind every decision here (and the dated history), see
[`DESIGN-NOTES.md`](DESIGN-NOTES.md). To move a project off the legacy
per-project wrapper scripts, see [`MIGRATION.md`](MIGRATION.md).

## The two job tiers

- **Tier 1 — Bug Sweeper**: fast, frequent, narrow, fixed daytime window.
  Mechanical fixes only.
- **Tier 2 — Overnight Batch**: slow, thorough, broad. One long run per
  project per night, scoped by that project's `.claude/FOCUS.md`.

A project can register either tier, both, or (like `scheduler` itself) just
Tier 2.

## Registering a project — one file

Registering a project means dropping **one** file here:
`schedule/<project>.conf`, then running `bin/sync-crontab.sh --apply`. That
file is the single source of truth for both *when* a job fires and *how* it
runs. There is no longer a per-project wrapper script to write — the generic
`bin/scheduler-run <project> <sweep|batch>` entrypoint reads everything it
needs from the conf.

```sh
cp examples/schedule-entry.conf.template schedule/myproject.conf
$EDITOR schedule/myproject.conf          # fill in repo, prompt, cron, knobs
bin/sync-crontab.sh                       # preview the crontab this produces
bin/sync-crontab.sh --apply               # back up + install it
```

`--apply` also symlinks the project's `.claude/QUESTIONS.md` and
`.claude/FOCUS.md` into `questions/` and `focus/` here, so every project's
scope-input and flagged-questions are browsable/editable from one place.

Deregistering: delete the conf, re-run `--apply` (the managed crontab block
is fully regenerated from whatever confs currently exist).

## What's in here

| Path | What it is |
|---|---|
| `lib/sweep-loop-common.sh` | The engine: lock / expiry / heartbeat / dedicated clone / `reset --hard` / invoke-claude / push-verify / cross-tier registry mutex. Sourced, not run. |
| `bin/scheduler-run` | Generic entrypoint. `scheduler-run <project> <sweep\|batch>` reads `schedule/<project>.conf` and sources the engine. Replaces per-project `~/.local/bin/*-loop.sh` wrappers. |
| `bin/sync-crontab.sh` | Reads every `schedule/*.conf`, rewrites only the scheduler-managed crontab block, auto-staggers `BATCH_CRON=auto` slots, syncs `questions/`+`focus/` symlinks. Preview by default; `--apply` writes. |
| `bin/tracker-bug-sweep-precheck.sh` | Reusable `PRECHECK_CMD` gate: skips the `claude` call entirely when the tracker's open-report set is unchanged. |
| `bin/morning-report.sh` | **Deprecated 2026-07-20** — superseded by `bin/scheduler` (see below). Aggregates every project's `~/reports/<project>/LATEST.md` + flagged questions, prints a `DEPLOY PENDING` line for a stale deploy. Left working, not the thing to build against now. |
| `~/.local/bin/scheduler` | The current CLI — `scheduler` (glance), `scheduler -b/-f/-q/-r [project]`, `scheduler -i <project> "idea"`. Not yet tracked in this repo's git history (see `.scheduler/FOCUS.md` item 3). |
| `bin/build-services-view.sh` | Regenerates the plain-text per-service audit under `services/`. |
| `schedule/*.conf` | One per registered project (`_batch.conf` is global auto-stagger config). |
| `examples/` | The conf template + the canonical `.claude/` command/FOCUS/QUESTIONS templates a project copies in. |
| `INTAKE.md` | The web-tracker HTTP contract a project's backend implements to plug in. |

## The conf file: `schedule/<project>.conf`

Two kinds of fields (full annotated example in
`examples/schedule-entry.conf.template`):

- **Scheduling** — `SWEEP_CRON` / `BATCH_CRON` (or `auto`), and the
  `*_JOB_NAME` that names each job's state dir and expiry marker.
- **Runtime** — `REPO_URL`, `REPO_SUBDIR`, and per-tier `SWEEP_*` / `BATCH_*`
  knobs (`PROMPT`, `MAX_TURNS`, `MODEL`, `PRECHECK_CMD`, …) that
  `scheduler-run` feeds to the engine.

**Backwards compatibility**: if a tier still sets `SWEEP_SCRIPT` /
`BATCH_SCRIPT` (a path to a legacy `~/.local/bin/*-loop.sh` wrapper), that
wrapper wins and the runtime fields are ignored for that tier. Drop the
`*_SCRIPT` line to switch that tier onto `scheduler-run`. This is how a
project migrates on its own schedule without a flag day — see `MIGRATION.md`.

## Two coordination mechanisms (don't conflate them)

- **Schedule registry** (`schedule/*.conf` + `sync-crontab.sh`): decides
  *when* a job fires, centralized so no `crontab -e` per project.
- **Runtime `PROJECT_KEY` mutex** (`lib/sweep-loop-common.sh`, in
  `~/.local/share/scheduler-registry/`): decides *who wins* if a project's
  Tier 1 and Tier 2 are somehow running at once, so they never race a second
  `reset --hard`/push against the same clone. Keyed per project, not per job.

## Cost of an idle run

Every registered project fires a real `claude -p` invocation on schedule
whether or not there's work. Two levers keep that cheap:

- **`PRECHECK_CMD`** cuts *how often* claude runs — a deterministic check
  (e.g. `bin/tracker-bug-sweep-precheck.sh`) skips the invocation when
  nothing changed.
- **`MODEL`** cuts *what each run costs* — e.g. run a mechanical sweep on a
  cheaper model.

See `DESIGN-NOTES.md` → "Cost of an idle run" for the measured numbers.
