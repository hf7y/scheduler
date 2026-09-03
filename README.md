# Scheduler

Coordinates autonomous `claude -p` jobs across several projects — nightly
feature/maintenance batches and frequent bug sweeps — on top of plain cron.
It is **not a daemon**: cron is the coordinator. This repo is a shared engine
+ a config registry + a report aggregator.

For the *why* behind past decisions (dated history through 2026-07-29), see
`vault:scheduler/DESIGN-NOTES.md` — reaped out of this repo once its content
was fully superseded by this README and safely archived (#238/#240). The
one-time move off the legacy per-project wrapper scripts is **complete** —
see "Backwards compatibility" below for the witness, and
`ecosystem1/scheduler/MIGRATION.md` in the vault for how it was done.

## The two job tiers

- **Tier 1 — Bug Sweeper**: fast, frequent, narrow, fixed daytime window.
  Mechanical fixes only.
- **Tier 2 — Overnight Batch**: slow, thorough, broad. One long run per
  project per night, scoped by that project's own GitHub issue tracker
  (`gh issue list`) — the scope and the backlog both live there.

A project can register either tier, both, or (like `scheduler` itself) just
Tier 2.

## Registering a project — one file, plus arming

Registering a project means dropping **one** file here:
`schedule/<project>.conf`. That file is the single source of truth for *how*
a job runs (repo, prompt, per-tier knobs). There is no longer a per-project
wrapper script to write — the generic `bin/scheduler-run <project>
<sweep|batch>` entrypoint reads everything it needs from the conf.

`bin/sync-crontab.sh`, which used to also decide *when* a job fires by
writing per-project cron lines, was retired (#454/#488): nothing installs a
per-project cron line any more. Tier 2 (overnight batch) dispatch is instead
driven by the usage-paced runner reading a rotation + an arm/park switch, so
getting a new project actually dispatching is a few more steps than dropping
the conf:

```sh
cp examples/schedule-entry.conf.template schedule/myproject.conf
$EDITOR schedule/myproject.conf            # fill in repo, prompt, knobs
git add schedule/myproject.conf && git commit -m "register myproject" # land it (PR + merge to main -- see below)

bin/enrole-selfdev.sh myproject --apply    # add/enable its row in schedule/_paced.<host>.conf (the rotation)
$EDITOR schedule/ROSTER                    # human step: add its "myproject|account@host|rate|parked" row by hand
                                            # (dose --arm below only flips an EXISTING row's state -- it exits
                                            # GAP, not 0, for a project the roster doesn't name yet)
bin/dose-project.sh myproject --arm        # human-only (#291): opens a PR flipping that row to 'live'
bin/dose-project.sh myproject --apply      # once that PR merges: converge THIS host's crontab to the roster
```

`dose --apply` doesn't write a per-project cron line either — it converges
the one shared `*/5` RUNNER tick (`schedule/_runner.conf`) that the paced
rotation dispatches every registered, armed project *from*. Deregistering:
`bin/dose-project.sh myproject --park` (PR, human-only), then delete
`schedule/myproject.conf` and `bin/enrole-selfdev.sh myproject --retire`
(flips its rotation row back to `|0|` — the row itself stays, see that
script's header for why). The `schedule/ROSTER` row itself is never deleted
by tooling either, same reasoning.

Tier 1 (bug sweeper) has **no automated installer** since
`sync-crontab.sh`'s retirement — a project that wants the fast daytime sweep
needs its `SWEEP_CRON` line added to the account's crontab by hand, tagged
`# scheduler:<project>:SWEEP` so `bin/build-services-view.sh` can read it
back out and report what's actually installed against what the conf asks
for.

### Committed-config gate

Deploying cron lines (or a `schedule/ROSTER` arm/park) generated from an
uncommitted working tree is config that exists in one directory and nowhere
in history; this repo has already been bitten by exactly that (2026-07-26, a
usage-ceiling edit that lived only in the working tree, `a9bffa2`). The
gate — any tracked modification, staged change, or untracked
`schedule/*.conf`, or the tree not being inside a git repo at all
(unverifiable is treated as dirty, not clean) — now lives in its own script,
`bin/schedule-clean-check.sh`, extracted from `sync-crontab.sh --check-clean`
when that script was retired (#488): it was the only half of it with a live
caller outside itself (`bin/usage-paced-runner.sh`'s dispatch-critical
gate). Exit 0 (clean) or 2 (dirty/unverifiable); writes nothing and reads no
crontab, so it's safe to call from a sweep or another script.

## What's in here

| Path | What it is |
|---|---|
| `lib/sweep-loop-common.sh` | The engine: lock / expiry / heartbeat / dedicated clone / `reset --hard` / invoke-claude / push-verify / cross-tier registry mutex. Sourced, not run. |
| `bin/scheduler-run` | Generic entrypoint. `scheduler-run <project> <sweep\|batch>` reads `schedule/<project>.conf` and sources the engine. Replaces per-project `~/.local/bin/*-loop.sh` wrappers. |
| `bin/sync-crontab.sh` | **Retired 2026-09-02 (#454/#488).** Used to read every `schedule/*.conf` and rewrite the scheduler-managed crontab block, including per-project `SWEEP`/`BATCH` lines and the two meta ticks. Nothing installs a per-project cron line any more — see "Registering a project" above. Its two still-live pieces moved out: the committed-config gate is now `bin/schedule-clean-check.sh`, and converging the shared RUNNER tick to `schedule/ROSTER` is now `bin/dose-project.sh`. |
| `bin/dose-project.sh` | `dose <project>` — converges **this host's** crontab to `schedule/ROSTER`'s row for that project, read fresh from GitHub via `gh api` every run (never a local clone, which can be days stale). `--check`/`--apply` install/verify the one shared `*/5` RUNNER tick that the paced rotation dispatches every armed project from — refuses (exit 7) if the roster says the project belongs to a different host. `--arm`/`--park` flip `schedule/ROSTER`'s `state` column via a self-merging PR; **human-only** (#291) — refuses a uid 3000-3099 self-dev caller and a project whose unix account doesn't exist on the roster's host, so an agent can never arm itself. `--now` dispatches once immediately, bypassing the usage gate and tempo, hopping over ssh to the roster's host if run elsewhere. `--sprint <dur>` lets a project ignore the gate's PACE hold/tempo until an absolute wall-clock deadline (the CEILING itself is never bypassed). Exit: 0 kept, 2 usage, 4 gap (no roster row), 5 broken, 6 blind, 7 refused. Witness: `tests/dose-project-witness.sh`. |
| `bin/schedule-clean-check.sh` | The committed-config gate (see below), extracted out of `bin/sync-crontab.sh --check-clean` when that script was retired — the only half of it with a live caller outside itself (`bin/usage-paced-runner.sh`'s dispatch-critical gate). Exit 0 if `schedule/` matches `HEAD`, 2 if dirty or unverifiable. Writes nothing, reads no crontab. |
| `schedule/ROSTER` | The only surface that arms or parks a project (#364/#429) — `project \| account@host \| rate \| state` rows, `state` is `live` or `parked`. Read fresh from GitHub by `bin/dose-project.sh` and by `bin/usage-paced-runner.sh`'s host-mode dispatch on every tick, never from a local clone. Only a human edits the `state` column directly, or `dose <project> --arm`/`--park` on their behalf (refuses a uid 3000-3099 self-dev caller outright, #291) — an agent arming itself is the one thing that guard exists to prevent. `schedule/_paced.<host>.conf` is still the rotation source in account mode (which rows exist, what each runs) until #364 retires it in favor of this file. |
| `bin/tracker-bug-sweep-precheck.sh` | Reusable `PRECHECK_CMD` gate: skips the `claude` call entirely when the tracker's open-report set is unchanged. |
| `bin/morning-report.sh` | **Deprecated 2026-07-20** — superseded by `bin/scheduler` (see below). Aggregates every project's `~/reports/<project>/LATEST.md` + flagged questions, prints a `DEPLOY PENDING` line for a stale deploy. Left working, not the thing to build against now. |
| `bin/scheduler` | The current CLI — `scheduler` (glance — also flags any registered project sitting on stranded, unpushed commits in its dedicated clone, e.g. a silent push-credential gap, or a branch beyond `main` with unmerged commits (a finished `nightly/<date>`/`paced/<date>` cycle nobody merged yet), without needing a separate `sweep` run), `scheduler -f/-q/-r [project]`, `scheduler -i <project> "idea"` (auto-commits and, since 2026-07-22, auto-pushes that single `.md` — fast-forwarding first if the repo is merely behind origin, so the idea can't strand as a local-only commit dispatch never sees; a genuine ahead+behind divergence is still never auto-resolved, just reported with the recovery command), `scheduler status <project>` (`-c`; offline git/feedback/questions/last-run deep-dive, no AI by default — the last-run block is CRON_ACCOUNT-aware since 2026-07-28: a job that runs under another unix account has its state read from that account's home via `sudo -n -u`, and an unreadable one prints `BLIND` naming the account/path instead of silently reading `$HOME`'s path and reporting a healthy job as never-run — `--claude` for a read-only one-shot summary, `--interactive`/`-I` for a live session preloaded with the same report), `scheduler <project>` (bare registered project name, no verb — shorthand for `scheduler status <project>`), `scheduler sweep`/`-s` (offline, read-only except auto-committing safe `*.md` drift: dirty working checkouts, unpushed dedicated clones, and stale `~/.local/share/scheduler-registry/*.active` markers left by a run that was killed/crashed before its own exit trap could clean up; later passes add `MIGRATED to <host>` re-verification, tripped `expires_at` dead-man switches, installed-vs-git drift via `bin/deploy-drift-check.sh`, a project enabled in more than one host's rotation via `bin/rotation-lint.sh`, and — last — checks that exist but nothing runs, via `bin/check-witness-lint.sh`; also reports a `schedule/` left sitting uncommitted, via `bin/schedule-clean-check.sh` — the passive half of the committed-config gate). `scheduler man` (`-m`) opens the maintained man page (`docs/scheduler-cli.md`) — the glance itself now shows a one-line legend instead of the old in-screen explanation block. `~/.local/bin/scheduler` is a symlink to this file. |
| `bin/scheduler-completion.bash` | Bash tab-completion for `bin/scheduler` — completes subcommands and, for the ones that take one, project names (reuses the same `schedule/*.conf` glob `scheduler` itself uses, so it can't drift out of sync). Source it from your shell rc: `source ".../scheduler/bin/scheduler-completion.bash"`. |
| `bin/publish-report.sh` | The one way to publish a run's report and re-point `~/reports/<project>/LATEST.md` at it: `publish-report.sh <project> <dated-file> [--from <src>\|-]`. **Retires the "write the dated file, then `cp` it onto LATEST.md" convention** the prompt generators used to ask authors to remember — on 2026-07-28 that `cp` followed the LATEST.md *symlink* and overwrote 2026-07-27's report in place, unrecoverably (`~/reports` is not a git repo). LATEST.md is always a symlink, replaced atomically (`ln -sfn` to a temp name + `mv -T`), so no write can follow the old pointer; a pre-existing regular-file LATEST.md (the legacy copy shape, still live for several projects) is preserved as `LATEST.md.orphaned-<stamp>` rather than deleted, loudly. Wired into the prompts generated by `bin/overnight-dev.sh` (the other original caller was retired -- hf7y/scheduler#190). Test root override: `SCHEDULER_REPORTS_ROOT`. |
| `bin/build-services-view.sh` | Regenerates the plain-text per-service audit under `services/`. |
| `bin/deploy-drift-check.sh` | Read-only "is what's installed still what's in git?" check: compares every `~/.local/bin/<name>` against this repo's `bin/<name>` at a git ref (`origin/main` by default), flagging a copy that has drifted (naming the commit it *does* match, so staleness is a fact) and a copy that matches today but can silently rot — a symlink can't drift, a copy can. Wired into `scheduler sweep` as its ninth pass; prints the `ln -sfn` fix but never touches anything under `~/.local/bin` (installed wrappers stay a human step). |
| `bin/unprinted-facts.sh` | The scheduler sprint's step-2 measurement, run by hand: for every fact the machinery records on disk, whether any view a human opens actually prints it — `PRINTED <view>` / `UNPRINTED` / `BLIND` (recorded nowhere, so not answerable even in principle). Exists as a script rather than a hand-kept list because a one-night inventory decays into a claim; this re-derives its evidence every run. Read it before changing what the glance shows — step 3's absence-surface is supposed to be designed against this, not against memory. Read-only, exits 0 whatever it finds (a measurement, not a gate). |
| `lib/paced-conf.sh` | The one source for the two rotation questions. **`paced_membership_set <repo-root>`** answers *"does the paced system own this project's Tier 2?"* — `PACED_MEMBERS`, the **union** across `schedule/_paced.conf` and every `schedule/_paced.<host>.conf`, because a fixed nightly cron line for a project *another* host's runner dispatches is cross-host double dispatch. It was what `bin/sync-crontab.sh` suppressed a project's fixed nightly `BATCH` cron line on before that script was retired (#454/#488; the union was the only monotonically safe answer for a crontab writer — it could suppress a line that used to be emitted, never arm one that wasn't). No per-project cron line is written by anything today, so this question no longer has a live crontab-writing caller; `paced_membership_set` is currently unreferenced outside this file and its own tests. Added 2026-07-29 after `sync-crontab.sh` was found reading only the shared file — so commenting out mandark's `scheduler|1|3` line to make its self-dev *dark* (58d6495) simultaneously **armed** an auto-staggered nightly dispatch line for the next `--apply`, restoring mandark as a second writer of scheduler's own git history one command after the decision to stop being one (reproduced in a sandbox; the witness for this, `tests/sync-crontab-paced-witness.sh`, was deleted along with `sync-crontab.sh` itself in #488 — `paced_membership_set` is still covered by `tests/arming-precedence-witness.sh` and `tests/final-newline-rows-witness.sh`, just not against this specific incident any more). **`resolve_paced_conf <repo-root>`** answers the narrower *"which rotation runs HERE, right now?"* and sets `PACED_CONF`/`PACED_CONF_SRC` from `schedule/_paced.<short-hostname>.conf` if present, else `schedule/_paced.conf` (explicit `PACED_CONF` still wins; neither file present is a loud refusal with `PACED_CONF` left *empty*, never a plausible default). Sourced by `bin/scheduler` so `next`/`run`/`weight`/`-p` describe the rotation that actually dispatches here. `bin/usage-paced-runner.sh` deliberately keeps its copy **inline** — it is the live `*/5` dispatcher and resolves its conf before it has anything safe to `source` from — so the agreement is mechanized instead: `tests/paced-conf-witness.sh` extracts the runner's block by its `>>>`/`<<<` markers and fails if the two ever disagree. Built 2026-07-29 after `bin/scheduler` was found hardcoding the shared file: on `dexter` it answered *"'scheduler' is not a participant"* about the one project dexter's rotation has enabled, and `scheduler weight <p> <n>` edited and committed **mandark's** rotation — the cross-host write the per-host split exists to prevent. |
| `lib/check-witness.sh` | The one source for the runtime-witness convention every check in `bin/` follows: `check_witness <name>` stamps `~/.local/share/scheduler-checks/<name>.lastrun` as the check's first act. Sourced, not run; never fatal — bookkeeping must not be able to break a check. |
| `bin/rotation-lint.sh` | Read-only "one project, one dispatcher" check across the **host split**. Two checks, both zero-false-positive: a project `enabled=1` in more than one `schedule/_paced*.conf` (two machines dispatching one project into one git history, with no shared lock), and a name listed twice in the *same* file (the runner has no dedup, so two enabled copies double-dispatch on one host; one enabled and one not is a shadowed line that makes the next "flip the X line" ambiguous). Retires a **prose convention, not a mechanism** — there was none: moving a project between hosts is a two-file edit (enable here, park there) and the rule was stated only in capitals in the conf files themselves (*"DO NOT LAND THIS ALONE"*, *"PAIRED, NOT LANDED ALONE"*), held together by whoever was editing remembering both halves. Deliberately does **not** check "enabled in *no* rotation" — parked-on-purpose and lost-in-a-move are the same bytes, and ~10 projects sit intentionally at `\|0\|` today, so that check would FLAG ten intentional parks to catch one accident. Not affected by an explicit `PACED_CONF` (that would pin it to one file and make it pass vacuously); point it elsewhere with `SCHED_ROOT`. Exit 0/1/3, where 3 is BLIND. Wired into `scheduler sweep` as its **tenth** pass; witness `tests/rotation-lint-witness.sh`. |
| `bin/check-witness-lint.sh` | Read-only "this check exists; nothing has run it since \<date\>" — reads the witnesses back and reports `NEVER RUN` (built, never called) or `STALE` (was wired, silently unwired — e.g. a `sweep` pass deleted in a refactor). Deliberately not static analysis: grep proves a check is *mentioned*, and a call site in a branch that never executes greps identically to a live one. Same dead-man-switch shape as `EXPIRY_DAYS`, applied to checks. Wired into `scheduler sweep` as its **eleventh and last** pass — last so the passes that invoke the other checks have already refreshed their witnesses, and a wired check can't be reported stale by the sweep that just ran it. Grace period `CHECK_WITNESS_STALE_DAYS` (default 2). |
| `schedule/*.conf` | One per registered project. Underscore-prefixed files are meta-config, not projects (`_paced.conf`, `_runner.conf`, `_usage.conf`, ...). |
| `schedule/_usage.conf` | The pacing knobs `bin/usage-gate.sh` reads — `USAGE_CEILING`, `USAGE_MIN_SLACK`, `USAGE_RUSH_BEFORE_RESET_MIN`, `USAGE_PROBE_MODEL`. Resolved per field: explicit env > `_usage.<host>.conf` (per-host, same convention as `_paced.<host>.conf`) > this file > the gate's built-in defaults. Edit it and the next tick picks it up — no crontab write needed, unlike the `RUNNER_ENV` route it retires. An out-of-range value is a loud `ERROR` (exit 2 → HOLD) naming the file; the gate's verdict line reports which source each value came from (`knobs=ceiling:_usage.conf,...`). |
| `examples/` | The conf template + the canonical `.claude/` command/FOCUS templates a project copies in, plus `CLAUDE.md.template` (the "suggest `/ideate` instead of implementing" guardrail — see `docs/priority-weight.md` for the realisateur/scheduler split this belongs to). |
| `docs/scheduler-cli.md` | The maintained man page for `bin/scheduler` (`scheduler man` opens it in `$PAGER`): glance column meanings, the `*` convention, where each number comes from, and the files behind them. The terse per-command list stays only in `scheduler --help` so the two can't drift. |
| `docs/offline-first-checks.md` | The reusable pattern behind `bin/scheduler status`: build a check entirely out of deterministic scripts first, layer AI on top only as an opt-in (one-shot summary or interactive session) — a template for any project that wants the same kind of status check. |
| `docs/priority-weight.md` | The optional `weight` field in `schedule/_paced*.conf` — currently inert on every live row, and structurally forced to 1 under `schedule/ROSTER` host-mode dispatch. |

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
project migrated on its own schedule without a flag day.

**That migration is complete, and the compatibility path above is now dead
code.** The step-by-step move was consigned to the vault
(`ecosystem1/scheduler/MIGRATION.md`, 2026-08-01) and removed from this repo
on 2026-08-10, because every project it named has either migrated or been
unregistered.

WITNESS (re-run it; do not trust this paragraph):

    grep -l '^\(SWEEP\|BATCH\)_SCRIPT=' schedule/*.conf
    # -> schedule/scheduler.conf ONLY, which never used the shared engine
    ls ~/.local/bin/*-loop.sh
    # -> No such file or directory

## Two coordination mechanisms (don't conflate them)

- **Schedule registry** (`schedule/*.conf` + `schedule/ROSTER` +
  `bin/dose-project.sh`): decides *when*/*whether* a job fires, centralized
  so no `crontab -e` per project — the conf holds runtime knobs, the
  roster's `state` column is the single arm/park switch, `dose <project>
  --apply` converges a host's crontab to it.
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

See `vault:scheduler/DESIGN-NOTES.md` → "Cost of an idle run" for the
measured numbers behind those two levers.
