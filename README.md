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
  project per night, scoped by that project's `.scheduler/FOCUS.md` (set
  `SCHEDULER_SUBDIR=".scheduler"` in the project's `schedule/<project>.conf`
  — `.claude/FOCUS.md` is unwritable from inside an unattended run, since
  the harness's sensitive-file gate covers `.claude/`).

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

`--apply` also symlinks the project's `$SCHEDULER_SUBDIR/QUESTIONS.md` and
`$SCHEDULER_SUBDIR/FOCUS.md` (`.scheduler/` for a new registration,
`.claude/` only as a legacy default) into `questions/` and `focus/` here,
so every project's scope-input and flagged-questions are browsable/editable
from one place.

Deregistering: delete the conf, re-run `--apply` (the managed crontab block
is fully regenerated from whatever confs currently exist).

### Committed-config gate

`--apply` refuses (exit 2) when `schedule/` is dirty relative to `HEAD` —
any tracked modification, staged change, or untracked `schedule/*.conf`.
Deploying cron lines generated from an uncommitted working tree is config
that exists in one directory and nowhere in history; this repo has already
been bitten by exactly that (2026-07-26, a usage-ceiling edit that lived
only in the working tree, `a9bffa2`). Same rule if the tree isn't inside a
git repo at all — unverifiable is treated as dirty, not as clean.

- **Preview (no `--apply`) still works on a dirty tree** and only warns on
  stderr. Checking what an in-progress edit would produce, before
  committing it, is the intended workflow.
- `--allow-dirty` overrides the refusal deliberately, and says so in the
  output.
- `bin/sync-crontab.sh --check-clean` runs *only* this gate and exits
  0 (clean) or 2 (dirty/unverifiable). Writes nothing and reads no
  crontab, so it's safe to call from a sweep or another script.

## What's in here

| Path | What it is |
|---|---|
| `lib/sweep-loop-common.sh` | The engine: lock / expiry / heartbeat / dedicated clone / `reset --hard` / invoke-claude / push-verify / cross-tier registry mutex. Sourced, not run. |
| `bin/scheduler-run` | Generic entrypoint. `scheduler-run <project> <sweep\|batch>` reads `schedule/<project>.conf` and sources the engine. Replaces per-project `~/.local/bin/*-loop.sh` wrappers. |
| `bin/sync-crontab.sh` | Reads every `schedule/*.conf`, rewrites only the scheduler-managed crontab block, auto-staggers `BATCH_CRON=auto` slots, syncs `questions/`+`focus/` symlinks. Preview by default; `--apply` writes. `--apply` **refuses** if `schedule/` is dirty relative to HEAD (or isn't verifiable against a git ref) — see "Committed-config gate" below. |
| `bin/tracker-bug-sweep-precheck.sh` | Reusable `PRECHECK_CMD` gate: skips the `claude` call entirely when the tracker's open-report set is unchanged. |
| `bin/morning-report.sh` | **Deprecated 2026-07-20** — superseded by `bin/scheduler` (see below). Aggregates every project's `~/reports/<project>/LATEST.md` + flagged questions, prints a `DEPLOY PENDING` line for a stale deploy. Left working, not the thing to build against now. |
| `bin/scheduler` | The current CLI — `scheduler` (glance — also flags any registered project sitting on stranded, unpushed commits in its dedicated clone, e.g. a silent push-credential gap, or a branch beyond `main` with unmerged commits (a finished `nightly/<date>`/`paced/<date>` cycle nobody merged yet), without needing a separate `sweep` run), `scheduler -b/-f/-q/-r [project]`, `scheduler -i <project> "idea"` (auto-commits and, since 2026-07-22, auto-pushes that single `.md` — fast-forwarding first if the repo is merely behind origin, so the idea can't strand as a local-only commit dispatch never sees; a genuine ahead+behind divergence is still never auto-resolved, just reported with the recovery command), `scheduler status <project>` (`-c`; offline git/feedback/questions/last-run deep-dive, no AI by default — `--claude` for a read-only one-shot summary, `--interactive`/`-I` for a live session preloaded with the same report), `scheduler <project>` (bare registered project name, no verb — shorthand for `scheduler status <project>`), `scheduler sweep`/`-s` (offline, read-only except auto-committing safe `*.md` drift: dirty working checkouts, unpushed dedicated clones, and stale `~/.local/share/scheduler-registry/*.active` markers left by a run that was killed/crashed before its own exit trap could clean up; later passes add `MIGRATED to <host>` re-verification, `BLOCKERS.md` staleness, tripped `expires_at` dead-man switches, installed-vs-git drift via `bin/deploy-drift-check.sh`, and — last — checks that exist but nothing runs, via `bin/check-witness-lint.sh`; also reports a `schedule/` left sitting uncommitted, via `sync-crontab.sh --check-clean` — the passive half of the committed-config gate). `scheduler man` (`-m`) opens the maintained man page (`docs/scheduler-cli.md`) — the glance itself now shows a one-line legend instead of the old in-screen explanation block. `~/.local/bin/scheduler` is a symlink to this file (see `.scheduler/FOCUS.md` item 3). |
| `bin/scheduler-completion.bash` | Bash tab-completion for `bin/scheduler` — completes subcommands and, for the ones that take one, project names (reuses the same `schedule/*.conf` glob `scheduler` itself uses, so it can't drift out of sync). Source it from your shell rc: `source ".../scheduler/bin/scheduler-completion.bash"`. |
| `bin/build-services-view.sh` | Regenerates the plain-text per-service audit under `services/`. |
| `bin/deploy-drift-check.sh` | Read-only "is what's installed still what's in git?" check: compares every `~/.local/bin/<name>` against this repo's `bin/<name>` at a git ref (`origin/main` by default), flagging a copy that has drifted (naming the commit it *does* match, so staleness is a fact) and a copy that matches today but can silently rot — a symlink can't drift, a copy can. Wired into `scheduler sweep` as its eighth pass; prints the `ln -sfn` fix but never touches anything under `~/.local/bin` (installed wrappers stay a human step). |
| `lib/check-witness.sh` | The one source for the runtime-witness convention every check in `bin/` follows: `check_witness <name>` stamps `~/.local/share/scheduler-checks/<name>.lastrun` as the check's first act. Sourced, not run; never fatal — bookkeeping must not be able to break a check. |
| `bin/check-witness-lint.sh` | Read-only "this check exists; nothing has run it since \<date\>" — reads the witnesses back and reports `NEVER RUN` (built, never called) or `STALE` (was wired, silently unwired — e.g. a `sweep` pass deleted in a refactor). Deliberately not static analysis: grep proves a check is *mentioned*, and a call site in a branch that never executes greps identically to a live one. Same dead-man-switch shape as `EXPIRY_DAYS`, applied to checks. Wired into `scheduler sweep` as its **tenth and last** pass — last so the passes that invoke the other checks have already refreshed their witnesses, and a wired check can't be reported stale by the sweep that just ran it. Grace period `CHECK_WITNESS_STALE_DAYS` (default 2). |
| `schedule/*.conf` | One per registered project (`_batch.conf` is global auto-stagger config). |
| `schedule/_usage.conf` | The pacing knobs `bin/usage-gate.sh` reads — `USAGE_CEILING`, `USAGE_MIN_SLACK`, `USAGE_RUSH_BEFORE_RESET_MIN`, `USAGE_PROBE_MODEL`. Resolved per field: explicit env > `_usage.<host>.conf` (per-host, same convention as `_paced.<host>.conf`) > this file > the gate's built-in defaults. Edit it and the next tick picks it up — no `sync-crontab.sh --apply`, unlike the `RUNNER_ENV` route it retires. An out-of-range value is a loud `ERROR` (exit 2 → HOLD) naming the file; the gate's verdict line reports which source each value came from (`knobs=ceiling:_usage.conf,...`). |
| `examples/` | The conf template + the canonical `.claude/` command/FOCUS/QUESTIONS templates a project copies in, plus `CLAUDE.md.template` (the "suggest `/ideate` instead of implementing" guardrail — see `docs/priority-weight.md` for the realisateur/scheduler split this belongs to). |
| `INTAKE.md` | The web-tracker HTTP contract a project's backend implements to plug in. |
| `docs/scheduler-cli.md` | The maintained man page for `bin/scheduler` (`scheduler man` opens it in `$PAGER`): glance column meanings, the `*` convention, where each number comes from, and the files behind them. The terse per-command list stays only in `scheduler --help` so the two can't drift. |
| `docs/offline-first-checks.md` | The reusable pattern behind `bin/scheduler status`: build a check entirely out of deterministic scripts first, layer AI on top only as an opt-in (one-shot summary or interactive session) — a template for any project that wants the same kind of status check. |
| `docs/priority-weight.md` | The optional `weight` field in `schedule/_paced.conf`: scheduler enforces it mechanically, realisateur is the one expected to set it based on cross-project vision judgment. |

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
