# Scheduler — design notes & rationale journal

> **This is the design journal, not the manual.** For "what is this and how
> do I use it," see [`README.md`](README.md). This file keeps the *why* — the
> decisions, the gaps, and the dated history behind the current shape — so the
> README can stay short. Some dated notes below predate the
> `bin/scheduler-run` entrypoint (see README + [`MIGRATION.md`](MIGRATION.md));
> where they describe per-project `~/.local/bin/*-loop.sh` wrappers, that is
> the *legacy* path being migrated away from, kept working for backwards
> compatibility.

Starting point dumped here from a working session (2026-07-17) on
`vkv-inventory`'s bug tracker + browse-tab redesign. As of the same day,
chezz's Tier 1 bug-sweep loop is the first real migration onto
`lib/sweep-loop-common.sh` (previously a hand-duplicated copy, same as
vkv-inventory's still is) and chezz also has a built (not yet
crontab-installed) Tier 2 nightly-batch on top of the same library — see
"Existing infrastructure" below. Everything else here is still design +
example snippets to build from, not yet a running system for
vkv-inventory. See `~/WORKFLOW.md` for the original narrower write-up
this was distilled from.

## The decision this directory encodes

**No new persistent service/daemon.** Cron already is the coordinator.
What actually solves "duplication across projects" and "one place to
check every morning" is a shared script library + a report aggregator —
not a new process to keep running and debugging. A real coordinating
service (a project registry, its own scheduler) would pay off once
there are enough projects that per-project cron-entry sprawl itself is
the bottleneck — not yet, at 2 projects (chezz, vkv-inventory).

## Four standardized pieces, not two

The two tiers below are the *jobs*. Standardizing them properly also
meant standardizing what they read from and write to — four pieces total,
all meant to be the SAME shape across every project from here on:

1. **Web intake** — the tracker's own read/write HTTP contract (`GET
   ?scope=bugs...`, `POST {type:...}`). Already independently converged
   on by chezz and vkv-inventory; now written down once, formally, in
   `INTAKE.md`, so a *new* project's backend has something concrete to
   implement against instead of reverse-engineering it from an existing
   project's source.
2. **Bug Sweeper** (Tier 1) — fast, frequent, narrow, fixed daytime
   window. Mechanical fixes only.
3. **Overnight Batch** (Tier 2) — slow, thorough, broad, scoped by a
   per-project "what's actually live right now" marker (`FOCUS.md`) so
   accumulated ideas that aren't the current focus get deferred (logged
   in the report) rather than acted on just because they were sitting in
   a queue.
4. **Running list of features** — deliberately **not** a fourth file.
   `INTAKE.md` documents this directly: a `type=feature` tracker report
   *is* a feature-backlog entry. A separate `FEATURES.md` would just be a
   second place the same information could drift out of sync with the
   tracker — `GET ?scope=bugs&type=feature` (or `type=all`) is the one
   source of truth Tier 2 reads from. Nightly *reads* every feature idea
   (for its report) but does not implement any of them without the user
   weighing in first — unchanged, still deliberate, not something this
   pass altered.

## Two more standard pieces: the big-bug handoff, and QUESTIONS.md

Two real gaps, closed the same day as everything above:

- **A real bug too big for a 15-minute sweep had nowhere to go.** Tier 1's
  triage used to be Mechanical-fix / Feature-idea / Needs-a-human-call /
  Duplicate — a genuine, agent-fixable defect that just needs more time
  than a fast sweep should spend fell into "needs a human call" and sat
  there, with nothing telling Tier 2 to actually pick it up. Fixed with a
  convention, not new code: `/bug-sweep` leaves such a report open with a
  note prefixed exactly `NIGHTLY:`; `/nightly-batch`'s own fetch step
  looks for that prefix and treats it as in-scope automatically — a UNION
  with `FOCUS.md`'s stated focus, not something `FOCUS.md` needs to name.
- **Neither tier had a durable, easy-to-find place to flag a real
  judgment call.** `~/reports/<project>/LATEST.md` is good for "what
  happened," but a bigger ambiguous question (a policy fork, a real
  tradeoff) could get lost in report prose. `.claude/QUESTIONS.md` — a
  real file at each project's own repo root, not tucked in `~/reports/` —
  is now the standard place either tier appends one when it comes up
  (append-only), and it's symlinked into `questions/<project>.md` +
  printed by `bin/morning-report.sh`, so it surfaces in one place.

  **QUESTIONS.md is two-way, not just a flag.** The user answers a
  question by replying **inline** under it on a `> ` blockquote line —
  that's the whole interface, no separate tool. The contract: `/nightly-batch`
  owns answer-processing (reads the file first each run, treats a `> `
  answer as authoritative like `FOCUS.md`, acts on it, folds standing
  decisions into `FOCUS.md`, then removes the answered block — git history
  and the report keep the record); `/bug-sweep` only *appends* questions
  and must never act on or clear a `> ` answer, so the 15-minute loop
  can't race the nightly over the file. Unanswered questions are left
  alone and never re-asked; deleting a line by hand still dismisses one
  without action. See `examples/QUESTIONS.md.template` for the exact
  format both tiers write and the user answers in.

Both are documented in `examples/bug-sweep.md.template` and
`examples/nightly-batch.md.template` (and `examples/QUESTIONS.md.template`
for the file itself) and are live in vkv-inventory's real command files.
**Gap**: chezz's real `bug-sweep.md`/`nightly-batch.md` predate both
conventions and don't have them yet — same shape of gap as the
`PROJECT_KEY`/`TIER` one noted below, not fixed here.

Tying 2 and 3 together is a genuinely new mechanism this pass added:
**runtime registration**. Every job (either tier, any project) now writes
a marker to a directory shared across ALL projects
(`~/.local/share/scheduler-registry/<PROJECT_KEY>.active`) before it
starts real repo work, and a second `flock` — keyed by `PROJECT_KEY`, not
by the individual script's own `JOB_NAME` — makes a project's bug-sweep
and nightly-batch contend for the same slot. Whichever fires first wins;
the other logs *who* it deferred to and skips this run rather than racing
a second `git reset --hard`/commit/push against the same clone. This
lives in `lib/sweep-loop-common.sh` itself, so every wrapper gets it
automatically — it's not something each project's script has to
implement separately. Verified directly (two fake concurrent jobs,
same `PROJECT_KEY`, different `JOB_NAME`s — the second correctly read the
first's marker and skipped) before writing any of this down.

**This solves a different problem from schedule coordination.** The
`PROJECT_KEY` mutex above only decides who wins if two jobs for the same
project are *already running* at once — it says nothing about *when* a
job fires in the first place, and it does nothing across different
projects (chezz and vkv-inventory were never going to race each other;
they don't share a repo). That second problem — "sweep hours and batch
times configurable in one place, projects register to get scheduled at
all" — is what `schedule/*.conf` + `bin/sync-crontab.sh` (below) is for.
Deliberately not the same mechanism, and deliberately not a merged
"one sweep loop other projects piggyback on" process either — that would
edge into the daemon this directory's top decision explicitly isn't
building yet. Instead: every project's job stays its own independent
process/lock, and only *schedule authorship* — which cron lines exist,
when they fire — gets centralized into one script that owns writing
the real crontab.

## Schedule registry: `schedule/*.conf` + `bin/sync-crontab.sh`

- `schedule/<project>.conf` (see
  `examples/schedule-entry.conf.template`) — the per-project config: each
  tier's `JOB_NAME`, wrapper script path, and cron expression. Leave a
  tier's three fields all blank to skip it for that project. This is the
  file "registering with the scheduler" actually means — drop one in,
  run sync. Editing sweep hours or batch time later is: edit this file,
  re-run sync.
- `bin/sync-crontab.sh` — reads every `schedule/*.conf`, checks each job's
  existing expiry state (the same `~/.local/share/<JOB_NAME>/expires_at`
  file `lib/sweep-loop-common.sh` already writes) so an expired job gets
  pruned here instead of editing crontab itself (see the Gap note below),
  and rewrites *only* a marked block in the real crontab — anything else
  already there, including a not-yet-migrated raw entry, is left alone.
  Prints a preview and exits by default; `--apply` backs up the current
  crontab (to `.crontab-backups/`) and actually writes it. Warns (doesn't
  block) on two projects' Tier 2 sharing an identical time, since that's
  a "consider staggering" nudge, not a correctness problem.
- **Migrating an existing unmanaged crontab line** (e.g. chezz's original
  `*/15 * * * *` with no window): remove that raw line by hand
  (`crontab -e`) before running `sync-crontab.sh --apply` with a
  `schedule/<project>.conf` in place, or the job fires twice on matching
  ticks — once from the old line, once from the new managed one. Done for
  chezz already; its crontab is now fully scheduler-managed.
- **`BATCH_CRON="auto"`** (or leave it blank, with `BATCH_JOB_NAME`/
  `BATCH_SCRIPT` still set) instead of hand-picking a non-colliding Tier 2
  time. `bin/sync-crontab.sh` assigns every `auto` project a slot, in
  order by project name, `BATCH_STAGGER_MINUTES` apart starting at
  `BATCH_BASE_TIME` (both configurable in `schedule/_batch.conf`, default
  30 minutes apart starting 1am), skipping past any slot that collides
  with another project's *explicitly* set `BATCH_CRON`. This is what "set
  the scheduler up for nightly jobs to run in batches" turned into —
  chezz/vkv-inventory/home-assistant all run on `auto` now (1:00, 1:30,
  2:00 respectively); wtul kept an explicit `BATCH_CRON` since its actual
  cadence isn't nightly. More to layer onto this later (a per-batch
  concurrency cap, named batches instead of one implicit sequence) —
  `schedule/_batch.conf` is where that would live.
- **`questions/*.md`** — for every `schedule/<project>.conf` that sets
  `PROJECT_REPO_PATH`, `--apply` also symlinks that project's
  `.claude/QUESTIONS.md` into `questions/<project>.md` here (creating the
  real file with a template header first if the project doesn't have one
  yet). One place to browse every project's flagged questions without
  duplicating the file — mirrors how `bin/morning-report.sh` aggregates
  `LATEST.md`, and `morning-report.sh` now prints from here too (see
  below) so a flagged question actually surfaces on the next morning
  check, not just by knowing to go look.

## Cost of an idle run

Worth being deliberate about, since every registered project now fires a
real `claude -p --max-turns 200` invocation every night whether or not
there's anything to do: is that an acceptable thing to trigger at 3am on
a night with genuinely nothing new?

- **Most nights aren't actually idle**, by design — `nightly-batch.md`'s
  scope is `FOCUS.md` UNION any `NIGHTLY:`-flagged handoff UNION the
  accumulated `type=feature` backlog, and the autonomy policy says build
  from that backlog rather than just report on it. A project with any
  backlog depth has real work most nights; the turn budget isn't wasted,
  it's the point.
- **The real idle case** — focus fully done, no backlog, no handoff, nothing
  broke — is more a `wtul`/`home-assistant` shape (slower-moving, narrower
  scope) than a `chezz`/`vkv-inventory` one. On a night like that, the
  agent still spends some turns re-verifying and confirming there's
  nothing to do (cheap, bounded — the orient + re-verify steps, not the
  full 200) before writing a short report. That's a real but small cost,
  not a runaway one, and it's the same cost `EXPIRY_DAYS`/heartbeat
  already accept as normal background overhead.
- **Worth pre-empting where a cheap, deterministic check can rule out
  "nothing changed" before spending any agent turns at all** — that's
  what `PRECHECK_CMD` (optional, in `lib/sweep-loop-common.sh`) is for:
  a shell command, run after clone/checkout so it can inspect fresh repo
  state, that skips the `claude -p` invocation entirely (logged, no
  notification) if it exits non-zero. Opt-in — no real wrapper sets it
  yet, since a good precheck is genuinely project-specific (e.g. "tracker
  has zero open/new reports AND FOCUS.md's mtime hasn't changed AND no
  `NIGHTLY:` notes exist" for a web-tracker project; something else
  entirely for `home-assistant` or `wtul`). Worth writing one per project
  once a real idle-night pattern shows up in its reports, not speculatively
  now.

## Secrets that can't survive a clone

Every job's dedicated clone is disposable and safe to `reset --hard`
*because* it only ever holds what's actually in the repo — but a project
that depends on real credentials (API tokens, SSH keys) gitignored **by
design**, not by accident, needs those present anyway. `home-assistant`'s
real wrapper was first to need this (a Home Assistant long-lived token,
an SSH keypair, Tuya IoT Platform creds, kept in `.session-handoff/`,
deliberately outside git). Now a supported option, not just a pattern to
eyeball and reproduce by hand: `lib/sweep-loop-common.sh`'s optional
`SECRETS_SRC_DIR` (copied into the clone's `SECRETS_DEST_SUBDIR`, default
`.session-handoff/`, every run — not just on first clone, so a rotated
credential is picked up without editing the wrapper). `git reset --hard`
never touches untracked files, so copying these in before it runs is
safe. `home-assistant-nightly-batch-loop.sh` itself still hand-rolls this
ahead of sourcing the shared library (it predates the option) — worth
migrating onto `SECRETS_SRC_DIR` directly once confirmed, not fixed here
since it's a real installed script outside this directory.

## Two tiers

**Tier 1 — Bug Sweeper**: fast, frequent, narrow, fixed daytime window.
Mechanical fixes only. Existing, real, already running (chezz) or built
(vkv-inventory) — see "Existing infrastructure" below.

**Tier 2 — Overnight Batch**: slow, thorough, broad, scoped by `FOCUS.md`
(see above). One long run per project per night. Proven once, informally
— the `drilldown-browse-redesign` overnight run (6 commits, 3 real bugs
found, ~30min, `--max-turns 200`) — and now also built (not yet
crontab-installed) for chezz on the same shared-library shape; see
"Existing infrastructure" below.

## Existing infrastructure (real, on disk, as of 2026-07-17)

| What | Where |
|---|---|
| chezz bug-sweep loop script | `~/.local/bin/chezz-bug-sweep-loop.sh` — on `lib/sweep-loop-common.sh`, `PROJECT_KEY="chezz"`/`TIER="bug-sweep"` set. |
| chezz `/bug-sweep` command | `~/Documents/Project Archive/chezz/.claude/commands/bug-sweep.md` — predates the `NIGHTLY:`/`QUESTIONS.md` conventions, doesn't have them yet (chezz's own `QUESTIONS.md` already flags this as a to-do). |
| chezz crontab entry | scheduler-managed: `*/15 9-21 * * *` (sweep), `auto`-batched to `0 1 * * *` (nightly) — via `schedule/chezz.conf`, applied. |
| chezz Tier 2 nightly-batch | `~/Documents/Project Archive/chezz/.claude/FOCUS.md` + `.claude/commands/nightly-batch.md` + `~/.local/bin/chezz-nightly-batch-loop.sh` (`MAX_TURNS=200`) — installed, running. |
| chezz sweep-status readout | the live page shows "Bug sweep last ran Xm/h/d ago · N fixed", read from a `sweep-status` record `/bug-sweep` (and `/nightly-batch`) POST every run — see `leaderboard/Code.gs` in that repo. |
| vkv-inventory bug-sweep + nightly-batch loop scripts | `~/.local/bin/vkv-inventory-{bug-sweep,nightly-batch}-loop.sh` — both migrated onto `lib/sweep-loop-common.sh` with `PROJECT_KEY="vkv-inventory"` set; `examples/vkv-inventory-bug-sweep-loop.sh` is now stale as a "not-yet-adopted" example (the real script matches it). |
| vkv-inventory `/bug-sweep` + `/nightly-batch` commands | `~/Documents/vkv/inv/inventory-app/.claude/commands/` — real, live implementation of the `NIGHTLY:` handoff and `QUESTIONS.md` conventions (see above). |
| vkv-inventory crontab entry | scheduler-managed: `*/15 9-21 * * *` (sweep), `auto`-batched to `0 2 * * *` (nightly) — via `schedule/vkv-inventory.conf`, applied. |
| home-assistant | Tier 2 only (no web tracker, no Tier 1). `~/.local/bin/home-assistant-nightly-batch-loop.sh`, `PROJECT_KEY="home-assistant"`. Introduces the `SECRETS_SRC_DIR` pattern (see "Secrets that can't survive a clone" above). `auto`-batched to `30 1 * * *` via `schedule/home-assistant.conf`, applied. |
| wtul | Tier 2 only, weekly-ish cadence, `EXPIRY_DAYS=14`. `~/.local/bin/wtul-batch-loop.sh`. Explicit (non-`auto`) `BATCH_CRON` in `schedule/wtul.conf` — actively being revised, leave it alone. |
| one-off nightly-batch prototype | `~/Documents/vkv/inv/schedule-drilldown-wakeup.sh` (the one-off `at`-job pattern `examples/nightly-batch-loop.sh` generalized). |
| original narrower design doc | `~/WORKFLOW.md` |

## What's in this directory

- `INTAKE.md` — the standardized web-intake contract (read/write shape,
  the `sweep-status` extension, the "never trust a raw POST response"
  gotcha) both existing trackers already converged on independently, now
  written down once for a *new* project's backend to implement against.
- `lib/sweep-loop-common.sh` — the shared engine (lock/expiry/heartbeat/
  clone/invoke-claude/push-verification/cross-job registry). A
  per-project wrapper sets a handful of variables and sources this
  instead of repeating ~90 lines of boilerplate. Chezz's two real scripts
  (`~/.local/bin/chezz-bug-sweep-loop.sh`, `~/.local/bin/chezz-nightly-batch-loop.sh`)
  are the reference real wrappers, now including `PROJECT_KEY`/`TIER` —
  see the Gap note above; vkv-inventory's own script still hand-duplicates
  the logic (see `examples/vkv-inventory-bug-sweep-loop.sh` for the
  not-yet-adopted rewrite).
- `examples/vkv-inventory-bug-sweep-loop.sh` — what the *existing*
  vkv-inventory script would look like rewritten on top of the shared
  library, including registration, for comparison against the real,
  currently-duplicated version at `~/.local/bin/vkv-inventory-bug-sweep-loop.sh`.
- `examples/nightly-batch-loop.sh` — the Tier 2 generalization of
  `schedule-drilldown-wakeup.sh`'s one-off pattern into a real recurring
  script, using the same shared library and the same `PROJECT_KEY` as its
  project's bug-sweep wrapper.
- `examples/bug-sweep.md.template` — a `.claude/commands/` file
  distilled from chezz's real, more mature `bug-sweep.md` (the version
  with the `sweep-status` step and the `## Summary` heading convention —
  vkv-inventory's own predates both and is worth upgrading to match).
- `examples/FOCUS.md.template` — the per-project "what's live right now"
  marker Tier 2 reads before deciding scope; also states explicitly that
  the feature backlog lives in the tracker (`type=feature`), not a
  separate file.
- `examples/nightly-batch.md.template` — a `.claude/commands/` file
  mirroring `bug-sweep.md`'s own structure, for the Tier 2 job to invoke.
- `examples/schedule-entry.conf.template` — per-project schedule config
  template; copy to `schedule/<project>.conf` (see "Schedule registry"
  above).
- `schedule/*.conf` — the live per-project schedule config
  `bin/sync-crontab.sh` reads (`chezz`, `vkv-inventory`, `home-assistant`,
  `wtul` all registered and applied as of this writing). `schedule/_batch.conf`
  is the one non-project file in here (global auto-batch base time/stagger,
  leading underscore keeps it out of the per-project glob) — see
  "Schedule registry" above.
- `bin/sync-crontab.sh` — reads `schedule/*.conf`, rewrites the
  scheduler-managed block of the real crontab, auto-assigns `BATCH_CRON=auto`
  slots, and syncs `questions/*.md` symlinks; see "Schedule registry" above.
- `questions/*.md` — symlinks into each registered project's own
  `.claude/QUESTIONS.md`, maintained by `bin/sync-crontab.sh --apply`. Not
  meant to be edited here directly (it's a symlink to the real file).
- `bin/morning-report.sh` — aggregator: globs every project's
  `~/reports/<project>/LATEST.md`, then also prints any `questions/*.md`
  that has a real entry (silently skips ones that are still just the
  template header).

## To actually stand this up for a new project

1. Make sure the project's tracker backend implements `INTAKE.md`'s
   contract (copy `Bugs.gs`/`leaderboard/Code.gs`'s shape if it's Apps
   Script; the contract itself is backend-agnostic if it isn't).
2. Copy `examples/vkv-inventory-bug-sweep-loop.sh`, change the config
   vars at the top (`JOB_NAME`, **`PROJECT_KEY`** — pick something unique
   to this project, no other project's wrapper should ever reuse it —
   `REPO_URL`, `REPO_SUBDIR`), point `PROMPT` at that project's own
   `/bug-sweep` command (`examples/bug-sweep.md.template` if it doesn't
   have one yet).
3. Same for `examples/nightly-batch-loop.sh` if you want Tier 2 for that
   project too — **same `PROJECT_KEY` as step 2's wrapper**, that's the
   whole mechanism — plus drop a real `.claude/FOCUS.md` (from
   `FOCUS.md.template`) and `.claude/commands/nightly-batch.md` (from
   `nightly-batch.md.template`) into the project.
4. Drop a `schedule/<project>.conf` (see
   `examples/schedule-entry.conf.template`) with each tier's `JOB_NAME`,
   script path, and cron expression, then run `bin/sync-crontab.sh` to
   preview and `bin/sync-crontab.sh --apply` to actually install it.
   Nothing is written to the real crontab until `--apply` is passed;
   that's still a deliberate, explicit step every time — it just lives in
   one script instead of a raw `crontab -e` per project now.
5. `bin/morning-report.sh` needs no per-project setup — it just globs
   whatever's under `~/reports/`.

## Open decisions (yours, not assumed here)

- Bug-sweeper window and overnight batch time are *configurable* per
  project (`schedule/<project>.conf`'s `SWEEP_CRON`/`BATCH_CRON`) — the
  daytime sweep window (`*/15 9-21 * * *`) is still this README's example
  numbers applied as a default for chezz/vkv-inventory, not an
  independently confirmed decision; edit and re-`--apply` once real hours
  are picked (or confirm these are fine as-is).
- ~~Staggering Tier 2 across projects if two land on the same time~~ —
  automatic now via `BATCH_CRON=auto` + `schedule/_batch.conf` (see
  "Schedule registry" above). Still a human call for any project that
  wants an explicit, non-auto time instead (like `wtul`).
- Report location: `~/reports/<project>/` assumed throughout these
  examples — change `REPORTS_DIR` in `morning-report.sh` if you want
  somewhere else.
- Whether `bin/morning-report.sh` gets wired into `.bashrc`/`.profile` to
  print automatically on shell start, or stays a manual command.
- ~~Whether to backport `PROJECT_KEY`/`TIER` onto chezz's and
  vkv-inventory's real scripts~~ — done for both; see "Existing
  infrastructure" above.
- Backporting the `NIGHTLY:`/`QUESTIONS.md` conventions onto chezz's real
  `bug-sweep.md`/`nightly-batch.md` (flagged as a to-do in chezz's own
  `QUESTIONS.md`), and the reverse — chezz's own `FOCUS.md` ideas
  (work-oldest-first fairness, a 4-outcome triage, stop-by-report-time
  turn budgeting, an irreversibility gate on new external service
  dependencies) backported into vkv-inventory's `FOCUS.md` and the shared
  templates.
- Whether any project's `nightly-batch` wrapper should set `PRECHECK_CMD`
  yet (see "Cost of an idle run" above) — deferred until a real idle-night
  pattern shows up in that project's own reports.

## 2026-07-20 — the vision session, then the real-world hardening pass

Two very different halves of one long day. Full blow-by-blow for
everything below lives in `.scheduler/FOCUS.md` (dated entries) — this
is the synthesized shape, not a duplicate.

**Part 1 — vision and architecture, mostly design, not code.**

- **Vision, stated directly:** scheduler runs a fleet of autonomous
  builders, not just a fleet of maintained projects. Self-spawning
  (realisateur scaffolding new projects unprompted) is core to the value
  this system is for, not a risk to contain — safety comes from a
  *per-project* `AUTONOMY_TIER` dial (low/medium/high, matched to that
  project's actual stakes), never one global trust ceiling. One rule
  sits above any tier regardless: genuinely irreversible actions (a new
  paid dependency, physical actuation, a non-revertible cutover) always
  need a human, no matter how trusted a project is.
- **Root-caused the `.claude/**` permission gate** that had been
  blocking unattended writes to `QUESTIONS.md`/`FOCUS.md` across several
  projects — confirmed with a controlled A/B test (identical `claude -p`
  invocation, only the target path differed) that `.claude/**` is
  hard-refused in headless mode, full stop. Fix: move scheduler-tracking
  files to a top-level dir outside `.claude/` (`.scheduler/` here).
  Applied to scheduler itself as the reference implementation; other
  projects' migration is still queued (consolidation roadmap axis 3).
- **Designed but did not build:** a `REGISTRATION.md` contract +
  `SCHEDULER_CONF_VERSION` (soft-validated, warn-don't-block) +
  `bin/scheduler-register`, so a project can register itself (manually
  or autonomously) against one authoritative schema instead of
  reverse-engineering the shape from an existing project's conf. Also
  designed the target `scheduler` CLI screen in detail (a literal mockup
  is in FOCUS.md) and the `BLOCKERS.md`-as-a-computed-view redesign.
- **Item 0** (collapsing report + questions + blockers into one
  printable, stable file per project) got the most design attention of
  anything this session — then got explicitly **parked**, later the same
  day, after real friction kept surfacing faster than any of it could be
  built and verified. The reasoning, stated directly and worth keeping
  as a standing principle, not just applied once: *"my ideas outpace
  implementation of stable versions so the target is always moving."*
  Named "vision debt" — folded into chezz's own `.claude/commands/
  ideate.md` the same day as a pattern that command should watch for
  generally, not just here.

**Part 2 — the actual hardening pass, mostly real bugs found by using
the system for real, not designed in the abstract.**

This is where most of the day's durable value landed. A representative,
not exhaustive, list — see FOCUS.md for the rest:

- **A near-miss, caught just in time:** a human reply written into
  `~/reports/realisateur/LATEST.md` was invisible to `collect-feedback.sh`
  (it only recognized `%%TAG` lines, not the `> ` convention
  `QUESTIONS.md` itself documents) — one dispatch away from being
  silently destroyed when that file got overwritten. Recovered by hand,
  then fixed at the root: `collect-feedback.sh` now recognizes `> `
  replies too, merging wrapped lines into one block.
- **Same bug, twice, in two different files** — the fix above was
  regex-tested against unindented content, but the REAL convention
  indents replies two spaces under their bullet. Shipped once, found
  live (three real replies in realisateur's `QUESTIONS.md` landed
  correctly but silently never got their auto-stamp), fixed in both
  `collect-feedback.sh` and the vim auto-stamp function, retroactively
  corrected the three replies that shipped before the fix.
- **Built the vim tooling that makes the reply workflow safe by
  construction, not by discipline:** auto-timestamp + auto-sign on save
  (without faking history — only new/changed lines get stamped, once
  per reply not once per wrapped line), then auto-commit on save
  (resolves symlinks to commit into whichever repo actually owns the
  file, fully backgrounded so a slow pre-commit hook never blocks the
  editor). Scope was deliberately broadened mid-session from a fixed
  literal path list to every `*.md` file, gated by a separate
  registered-repo check — "discourage the informal path by making the
  proper one more useful, never by restricting the informal one" is the
  standing principle that decision established.
- **`scheduler sweep`** — a reactive backstop for exactly the case the
  proactive vim hook can't cover (a long-running vim session that
  predates a `~/.vimrc` change never picks up new autocmds). Built,
  proven necessary within the same session (found real unprotected
  content in crt and home-assistant immediately), then extended to also
  check every automated job's *dedicated clone*, not just human
  checkouts — the exact blind spot that would have stopped it from
  catching its own motivating example (chezz's stranded commit was found
  in a dedicated clone, not a checkout). Wired to its own independent
  15-minute cron tick, deliberately not gated by `usage-gate.sh` (sweep
  is pure git/bash, zero API cost — gating it behind a check that
  protects API spend would throttle it for a reason that doesn't apply).
- **A real, live-diagnosed git divergence in home-assistant**, root-caused
  precisely: a live-tested fix deployed straight to the device via its
  REST API got git-synced correctly, but a *separate*, git-only decision
  (disabling 5 automations) made in the same session was never deployed
  — so the nightly's own "reconcile with live instance" step (which
  trusts live over git by design) silently overwrote the undeployed
  intent with what was actually running on the hardware. Compounded by
  the checkout never being fetched against origin afterward. Reconciled
  with human direction on the one real content conflict; the pattern
  itself is recorded as a recurring shape to watch for, not a one-off.
- **Two real regressions caught by using the system, not by review:**
  `cmd_idea_push_reminder`'s own staleness/freshness check used `git diff
  --quiet`, which is blind to brand-new untracked files — exactly the
  case (`.idea` drops) it most needed to catch. And a mid-session rename
  (`cmd_idea_push_reminder` → `cmd_commit_file`, done to give the vim
  hook and the CLI one shared implementation instead of two) missed a
  call site inside `sweep` itself, which would have failed silently the
  next time sweep found something to auto-commit. Both found and fixed
  the same day, before either shipped to a real run.
- **Cross-project propagation, each with a clear boundary respected:**
  chezz's `.githooks/pre-commit` made path-aware (skips the full 3+
  minute Playwright suite for docs-only commits — verified live, 3.4min
  to 1.1s); vim-arcade's mission broadened to teach vim *and* tmux *and*
  git etiquette, not vim motions alone; crt got a heads-up to check
  scheduler's current state before more work against an interface
  (`morning-report.sh`) that's now deprecated; realisateur got a durable
  note about its eventual abstract-visioning role, explicitly parked,
  not built.
- **`bin/morning-report.sh` deprecated in place** in favor of `bin/
  scheduler` (a real, working CLI, built earlier but never brought under
  version control until this session — fixed that too, `~/.local/bin/
  scheduler` is now a symlink to a tracked `bin/scheduler`).

**What's still open, by design, not by oversight:** the live-wrapper
fixes (date-format collision, `LATEST.md`-as-symlink) only ever landed
in `examples/` templates, pending explicit go-ahead to touch the five
real installed scripts; stale-`.active`-marker detection is designed and
queued as the next concrete piece; `AUTONOMY_TIER`/the registration
contract stay parked behind the hardening-first priority, correctly not
built speculatively.

## 2026-07-23 — vision-burndown /ideate pass (weights, two-account reality)

Interactive `/ideate` session (this command was ported into
`.claude/commands/ideate.md` from chezz the same session). No
implementation code touched; decisions recorded and queued only.

**The question:** realistic burndown of the *vision* backlog given
current quota, under a zach-personal / svc-vaporwave two-account split.

**What the numbers said (rough, honest):**
- Backlog ≈ 25–27 open vision items (~23 Backlog bullets + 4 roadmap
  axes). Intake via `scheduler -i` is **non-AI, zero quota cost, no
  throttle** — ~10/week sustained with bursts (11 landed 2026-07-22).
- Clearing is quota-gated and only **two** paced jobs touch the vision
  backlog (`scheduler`, `realisateur`); they share slack with 10
  operational batches and lose to interactive human chat (~73% of spend
  per the 2026-07-18 audit). Realistic clear ≈ 2–4 items/week.
- **Net −6 to −10/week — the backlog diverges.** This is the named
  "vision debt" pattern, not a tooling failure.

**Two-account reality (user-corrected):** there is *no* clean split right
now. The user is logged into svc-vaporwave for crt dev; they hop accounts
when one caps — the account-hop is the current load-balancer. So a single
`usage-gate.sh` reading is "the account you're camped on," not a stable
per-account budget. Two quotas help *operational* separation but do
**not** add vision throughput, because the vision-clearing jobs run
wherever zach is and vaporwave quota can't cleanly be spent on scheduler
vision work (it's the Krewe nonprofit's service account; acceptable as
general AI-R&D, but a boundary smell). Verdict: **two accounts as split
today are not enough to burn down vision** — the real levers are (a) less
interactive human spend on the vision-clearing account and (b) segregation
tooling so the split is deliberate, not reactive account-hopping.

**Decision 1 — weights.** `scheduler` and `realisateur` bumped 1→3 in
`schedule/_paced.conf` (was: default 1). Rationale: they're the only
vision-clearing jobs, so they should dominate available slack. **Weight 3,
NOT always-top** — always-top starves the 10 operational batches and just
converts vision debt into operational debt elsewhere. realisateur owns
re-tuning this (docs/priority-weight.md); it already ran its own /ideate
2026-07-23 adjusting nine-speakers, so the triage-owner loop is live.

**Decision 2 — does intake-triage follow from reweighting?** Not
mechanically: weights touch the clear side; `scheduler -i` intake stays
unbounded regardless. But reweighting *raises the cost* of an un-triaged
backlog (prioritized quota wasted on low-value items). The one path where
triage does ride along: realisateur is both a vision-clearing job AND the
chartered pruner, so routing the extra turns through realisateur (not just
scheduler) means more turns → more pruning. So triage follows from
reweighting **iff the turns go to realisateur.**

**Queued for the user (QUESTIONS.md):** build account-segregation tooling
so zach/vaporwave usage is deliberately split rather than reactive
account-hopping; user flagged this as a discipline gap to address soon.

## 2026-07-24 — account model decided: Max primary + nonprofit-only vaporwave

Follows the 2026-07-23 vision-burndown pass. Decision (user-directed):
**move the primary account to Claude Max (5x), stay logged into it always,
and use svc-vaporwave ONLY for the nonprofit** (its batch jobs + nonprofit
interactive). No `svc-vision`, no account-hopping.

**Why this over the 3-base-account split:** a service user only pays off
while it can stay a cheap base-tier quota soaking spillover. The token
math (~40–80 Mtok/wk to keep pace with vision) exceeds a base quota, so a
vision service user would have needed a Max upgrade anyway — and a
*siloed* Max is strictly worse than a *pooled* Max (same price, can't lend
idle capacity to chat or vice versa). At ~14 projects and already hopping,
personal-side demand is already >1 base quota. So: one pooled Max beats
three siloed base accounts.

**Consequences for the game plan:**
- **Segregation tooling retired.** No `account` field in `_paced.conf`, no
  per-account `usage-gate` probe. Those existed to disambiguate hopping;
  hopping is now eliminated by policy, not code. Cheaper and cleaner.
- **Estimates become trustworthy.** `usage-gate.sh` now reads one stable
  primary account, so pacing/burndown readings mean what they say. (Every
  earlier number here was muddied by "which account am I probing" — the
  71%/7d in the 07-23 pass was actually vaporwave, not zach.)
- **Capacity stops the bleed but does NOT converge the debt.** ~5Q pooled
  lets vision draw its keep-pace ~40–80 Mtok/wk (was ~10–15 as leftover
  slack), moving net accrual-vs-clear from −6..−10/wk toward ~0. But
  intake stays unbounded and zero-cost, so **Max raises the ceiling the
  debt diverges under; realisateur pruning is still the only thing that
  converges it.** Do not let the Max purchase quietly cancel the pruner
  work.
- **Weight-3 bump: unchanged.** Max reduces contention so weight matters
  less on slack nights, but the exit condition stays realisateur's pruner
  standing up (per _paced.conf bootstrap note), NOT "Max landed."
- **Cost framing flips $ -> quota.** Max is flat monthly + a quota ceiling;
  the lever is quota-tokens, not dollars. Sonnet-default (07-18 audit)
  still right because Opus burns *quota* ~5x faster.
- **OAuth side benefit.** Primary always-logged-in keeps its CLI creds
  fresh -> the "Not logged in" unattended failure mode largely goes away
  for personal jobs. Open follow-up (QUESTIONS.md): verify svc-vaporwave's
  cron creds get refreshed by its own interactive use, or it can still
  lapse mid-week.

## 2026-07-24 — /ideate pass #2: pruner ownership, intake policy, housekeeping

Second interactive /ideate pass the same day. Decisions:

- **Convergence pruner is realisateur's to build (not scheduler's).**
  realisateur already owns cross-project triage, runs its own /ideate, and
  edits `_paced.conf` weights, so it owns the two-part exit condition:
  (a) a per-project stability-milestone convention, (b) default-PARK ideas
  that land past the current milestone. Queued to its inbox via
  `scheduler -i realisateur "..."` this pass. When (a)+(b) exist, drop
  scheduler+realisateur weights back toward 1.
- **Intake stays frictionless.** `scheduler -i` is unchanged; capturing
  ideas at zero friction is worth keeping. ALL triage/parking happens
  downstream in realisateur, not at intake. (Rejected: tagging at intake —
  adds friction to the one habit that's working.)
- **Leaked-credential call (BLOCKERS.md wtul section):** the Discogs token
  there is committed + pushed (in git history), which violates CLAUDE.md's
  "no secret in a tracked file." Surfaced; user judged the free, low-value
  token acceptable to LEAVE. Documented as an accepted risk inline in
  BLOCKERS.md so future passes don't re-flag it; rotation remains the only
  real un-leak if that judgment ever changes. NOT removed.
- **Fixed drift:** the ported `.claude/commands/ideate.md` still described
  account-hopping in its orient step; updated to the 2026-07-24 stable
  primary-Max model.

**Vision-debt visibility (step 4.5):** still diverging. 17 intake commits
(3 on 07-20, 11 on 07-22, 3 on 07-23); backlog ~42 markers; nothing drained
this week (quota on HOLD every reading, primary not yet on Max). Expected
to keep widening until Max lands AND realisateur's pruner exists — the
former stops the bleed, only the latter converges it.

## 2026-07-24 — /ideate pass #3: svc-vaporwave silently-orphaned finding, ownership split

Live-checked the open svc-vaporwave OAuth question from pass #1's
QUESTIONS.md entry (`sudo -u svc-vaporwave stat`/`crontab -l`, run by the
user). Findings:
- `.credentials.json` exists, last touched 2026-07-21 20:27 — not
  obviously expired, but nothing has exercised it since (see next point).
- **`crontab -l` returns "no crontab for svc-vaporwave" — literally
  empty.** `schedule/_paced.conf` disables aedile and vkv-inventory with
  `# migrated to svc-vaporwave's own crontab 2026-07-20` — that migration
  was never actually completed. Both projects have had **zero unattended
  dispatch for 4 days**, not "safely paused elsewhere." BLOCKERS.md's
  vkv-inventory entry ("Recently resolved," tracker 403) is misleading in
  the same way — the tracker fix is real, but the project hasn't run at
  all since, migrated or not.

**Ownership question this surfaced: who's responsible for catching a
silently-orphaned participant like this?** Resolved by applying the
division of labor already standing in this repo (`docs/priority-weight.md`,
FOCUS.md's cross-project-blocking section — "scheduler stays mechanism,
realisateur interprets vision/judgment"):
- **Scheduler owns detecting it.** The actual bug is a mechanism gap:
  `_paced.conf` disabled two participants on an unverified assumption
  about an external destination (a crontab entry on another account) and
  nothing ever checked that assumption held. This is the same shape of
  risk as the stranded `.active`-marker detection already queued in
  FOCUS.md's "Current focus" item 1 (NEXT UP) — a disabled-with-unverified-
  external-dependency state deserves the same generalized sweep, just not
  yet built to cover this case. Queued there as a mechanism to build:
  periodically verify that any `_paced.conf` line disabled with a
  "migrated to X" comment still has a real, live X.
- **Realisateur owns the judgment call** once it's surfaced: finish the
  svc-vaporwave migration (actually install the crontab) vs. pull both
  projects back into zach's own `_paced.conf` rotation now that Max
  removes the quota-pressure reason a second account existed for. Queued
  to its inbox via `scheduler -i realisateur` this pass (dropped as a new
  standalone `.idea` file, not a direct edit — realisateur's own cycle was
  running at the time this was filed).
- **The human owns the actual account-boundary action** — anything
  touching svc-vaporwave's crontab, credentials, or home-directory
  permissions is cross-account and hard-to-reverse-by-an-agent, so it
  stays a human action under this repo's own autonomy-tier framing
  (irreversible/external-boundary actions sit above any tier, always
  human sign-off) — matches zach's own request this pass to grant himself
  broader access to svc-vaporwave's home directory rather than have an
  agent attempt it.

## 2026-07-24 — /ideate pass #3: chezz/wtul push-gap fix, decided

Root cause (found by realisateur, routed here per its own ideate.md step
5 rather than hand-fixed): chezz/wtul's "stranded local commit" pattern
isn't a dedicated-clone-vs-working-checkout race, it's a credential gap —
the dispatch environment can push to local bare remotes (crt,
realisateur, gardien, senechal) fine, but has no SSH credentials for
GitHub-hosted remotes (`git@github.com:hf7y/{chezz,wtul}.git`). Nightly
runs commit successfully but the push silently no-ops, leaving commits
local until a human (or an interactive session with working creds)
pushes by hand — confirmed same night by manually pushing wtul's
`51e2545` and chezz's `0189195`.

**Decided (human-directed): give the dispatch environment real,
scoped GitHub access — deploy keys, not agent forwarding, not a shared
key.** Rejected alternative: leaving it credential-free and just making
the silent failure loud in `scheduler status`/`sweep.log`. That's still
worth doing as a belt-and-suspenders safety net regardless (a
stranded-commit warning should never be silent), but the chosen fix
closes the gap for real — chezz/wtul push same-run like every other
project — rather than permanently requiring a human push step.

**Queued as human-only follow-up (key generation/installation is a
cross-boundary credential action, not something an agent should execute
unattended):**
1. Generate a dedicated deploy key per repo (not one shared key across
   both) — `ssh-keygen -t ed25519 -f ~/.ssh/deploy_chezz -N ""` and same
   for wtul.
2. Add each public key as a **deploy key with write access** on the
   corresponding GitHub repo (Settings → Deploy keys → Add deploy key,
   check "Allow write access").
3. Wire each private key into the dispatch environment's SSH config
   (an `IdentityFile`/`Host` alias per repo, same pattern already used
   for scheduler's own per-repo deploy keys — see
   [[scheduler-cron-ssh-auth]]) so `git push` resolves to the right key
   without touching any other repo's credentials.
4. Verify with a real push on each project's next scheduled dispatch
   (or force one) — confirm `sweep.log` shows `pushed: yes` instead of
   the current silent no-op.
Still worth doing independent of the above: make a genuinely silent
`pushed: no` loud in `scheduler status`/`sweep.log` for ANY project, not
just these two — this was the credential gap's real blast radius (nobody
noticed for however long until tonight's manual check), and the deploy
keys don't prevent some future, different credential gap from being
silent again.

**RETRACTED, same pass (2026-07-24, caught by zach: "don't they have
deploy?") — the credential-gap diagnosis above was wrong, verified
directly instead of assumed.** `~/.local/share/chezz-nightly-batch/repo`
and `~/.local/share/wtul-batch/repo` already have `origin` pointed at
`git@github-chezz-deploy:hf7y/chezz.git` / `git@github-wtul-deploy:hf7y/
wtul.git` — real deploy-key `Host` aliases already in `~/.ssh/config`
(`chezz_deploy_key`/`wtul_deploy_key`, matching the [[scheduler-cron-ssh-auth]]
pattern already used for crt/ha/vkv). `ssh -T` authenticated cleanly for
both, and a real test push (throwaway branch, pushed then immediately
deleted) confirmed actual write access for both. **No deploy key work is
needed — retracting the "decided" plan above.** BLOCKERS.md's chezz/wtul
sections corrected to match.

What this means for the ORIGINAL symptom (chezz's `152e803`/wtul's
stranded commits realisateur saw): the credential-gap explanation was
never actually tested against the working keys before being routed here —
the real, already-documented explanation is almost certainly the
account-wide spend-limit-cutoff pattern from 2026-07-20 (see FOCUS.md
"Avoid stranded state when a run gets cut off mid-way" — commits land,
push doesn't happen because the run got cut off by quota exhaustion
mid-cycle, not because credentials were missing). That gap's real fix is
the visibility work already queued there (surface a stale/incomplete
push in `scheduler status`/`sweep.log`), not new credentials. Flagging
back to realisateur so its own memory of this incident gets corrected
too, not just scheduler's.

## 2026-07-24: multi-machine parallelism (dexter comes up as a peer) — /ideate, human-directed

**Trigger:** dexter (a box previously only known to this repo as crt's
OctoPrint-reachable VM, see BLOCKERS.md 2026-07-20) is now up with its own
WSL/Ubuntu environment — the first time a second real machine capable of
running Claude Code has existed alongside mandark. Today's dispatcher is
strictly single-host: one global `flock` in `usage-paced-runner.sh` means
exactly one participant job runs at a time, and round-robin fairness across
~14 weighted participants (not quota) is the actual backlog bottleneck (see
same-session chat: 47-50pt of unused 7-day quota slack going unspent
because nothing asks the gate to run two things at once). This is the
architecture note in FOCUS.md's "cron, not a daemon" section finally
meeting its own named revisit trigger — "scheduler running on an
always-on server instead of the laptop" — except arriving as a second
*laptop-class* peer, not a server.

**Decisions (all four asked directly, none guessed):**

1. **Execution model: dexter is a full peer, not a jump box.** It runs its
   own Claude Code processes and its own paced dispatch loop locally on
   WSL/Ubuntu — real parallelism (both boxes independently spend from the
   same account-wide quota), not just remote triggering of jobs that still
   run on mandark.

2. **Project segregation: pin by hardware/network reachability, not an
   arbitrary split.** `crt` is the clear, already-evidenced case —
   BLOCKERS.md 2026-07-20 already confirms dexter's VM network reaches
   crt's OctoPrint at `192.168.0.43`, and `schedule/crt.conf`'s
   `DEPLOY_CMD`/`DEPLOY_FRESH_CMD` sync to a VM-resident report path,
   which is presumably dexter itself. `gardien`/`senechal` are NOT
   evidenced the same way — their confs and FOCUS.md language describe a
   *permission scope* gate (no unattended RAID/home-directory access yet),
   not a network-locality requirement, so pinning them to dexter would be
   guessing. Left open, see QUESTIONS.md. Everything else (no hardware
   dependency) stays where it runs today (mandark) for the MVP rather than
   floating freely — "pin by need" implies "don't move what doesn't need
   moving," not a full re-shuffle.

3. **Scheduler topology: two independent schedulers, not one shared
   rotation.** Each box gets its own `_paced.conf` subset and its own
   rotation pointer; no distributed lock, no cross-host coordination
   mechanism. Explicitly the simpler/cheaper option, chosen over a shared
   rotation with a real distributed lock (SSH/NFS/coordination service) —
   that was named as more infra than an MVP should absorb before proving
   the concurrency-safety premise below.

   **Named risk, accepted deliberately, must be watched:** the single
   global flock today prevents quota overshoot by construction — only one
   thing spends at a time, so a re-probe of `usage-gate.sh` right after is
   always accurate. Two independent schedulers on two hosts reintroduces a
   genuine race: both can probe the account-wide headers, both see slack,
   both dispatch, and the account can overshoot between the two probes
   (headers only reflect usage AFTER a request round-trips). Nothing in
   this decision solves that race — it accepts it as a real gap for the
   MVP, to be observed empirically (does it actually overshoot in
   practice, and by how much) rather than solved preemptively. If it
   proves to matter, the fix is more likely tightening `USAGE_MIN_SLACK`/
   `USAGE_CEILING` per-host (leave more headroom since two probers now
   share one budget) than building real distributed coordination — but
   that's a follow-up call, not decided here. *(2026-07-26: the mechanism
   that makes that per-host tightening a one-line edit now exists —
   `schedule/_usage.<host>.conf`, see the dated section at the end of this
   file. The decision above is unchanged; only the cost of acting on it is.)*

4. **Sprint scope: small MVP, not the full design.** Prove concurrent
   dispatch across two hosts doesn't blow the account-wide ceiling in
   practice before building anything more elaborate (shared rotation,
   engine-enforced hardware pinning, etc.). Real coordination work, if
   still needed after observing the MVP, is deliberately a later pass.

**MVP shape (queued to FOCUS.md, not built this pass):** dexter gets its
own clone of this repo, its own crontab entry running
`usage-paced-runner.sh` against its own `_paced.conf` containing only
`crt` (the one hardware-evidenced pin) to start, logged into the SAME
primary Max account as mandark (the shared-quota premise depends on it —
a different account would silently defeat the whole point, no shared
usage-gate to race against). mandark's `_paced.conf` drops `crt` to avoid
double-dispatching the same project from two hosts. Watch `run.log` on
both boxes for a stretch to see whether the account-wide ceiling ever
actually gets hit harder than single-host operation hits it today.

**What this is NOT yet:** engine-enforced `AUTONOMY_TIER`-aware pinning,
a shared rotation, or a resolution of the probe race above — all
explicitly deferred past the MVP. See QUESTIONS.md for the concrete
human-only setup steps still open (dexter's Claude Code login, SSH/deploy
key parity, WSL2 network reachability to crt's OctoPrint re-verified fresh
since dexter's environment changed, and the gardien/senechal placement
call).

## 2026-07-24 — the 40-50pt slack turned into an actual reweight (first live use of `docs/priority-weight.md`)

**Trigger:** same unused-slack signal as the dexter entry above (this
session, chat), but the lever pulled this time is the one that was
already sitting there unused rather than a new one: `_paced.conf`'s
per-project `weight` field and its `enabled` flag. Every active
participant except `groc-mangr` was still flat at weight 1 despite
`docs/priority-weight.md` existing since 2026-07-22 — the field was
documented but nobody had actually turned it since the 2026-07-23
bootstrap bump/revert (see that entry above).

**What realisateur measured (offline, no AI judgment beyond reading the
numbers):** `bin/milestone-audit.sh`'s declared/status per project,
cross-checked against `git log --since="7 days ago"`/`--since="3 days
ago"` commit counts and raw FOCUS.md backlog size, for all 12 then-enabled
participants. Findings:
- `crt` (211 commits/7d, 78/3d, 1415-line FOCUS.md), `scheduler` (181/7d,
  89/3d, large DESIGN-NOTES/DIGEST), `home-assistant` (36/7d, HTTPS-
  reachability + soak-test still open), `wtul` (46/7d, 35/3d) all sit at
  the top of the velocity range AND have an `in-progress` milestone with
  real remaining criteria — proof they burn extra turns productively, not
  just proof they're busy.
- `groc-mangr` (5/7d), `sequestria` (5/7d), `nine-speakers` (12/7d),
  `vim-arcade` (12/7d) sit at the *bottom* of the velocity range AND have
  **no declared stability milestone** — still vision-forming (per
  STABILITY-MILESTONES.md's own vocabulary), not converging on a v1 core.
- `gardien` (24/7d), `senechal` (31/7d), `chezz` (missing milestone,
  cooling — 5 of its 23 weekly commits are from the trailing 3 days) sit
  in the middle and were left alone this pass — real activity, but not
  the standout case either lever is meant to catch.

**Decided (realisateur, interactive `/ideate`):** `crt` 1→3,
`scheduler`/`home-assistant`/`wtul` 1→2 (weight lever); `groc-mangr`/
`sequestria`/`nine-speakers`/`vim-arcade` parked, `enabled`→0 (rotation-
size lever). Net rotation slots unchanged, 13→13 — the +5 from weight
bumps is offset by the -5 from parking, so lap length stays flat while
turns shift toward projects proven to use them. Applied directly to
`schedule/_paced.conf` (commit `f9fe5f3`), with the full reasoning and a
revert recipe left inline in that file's own comments — this entry is the
narrative record, `_paced.conf`'s comment is the operational one.
Parking is explicitly **not** a verdict on the four ideas' merit — same
"parked is not debt" framing STABILITY-MILESTONES.md already established
for in-project backlogs, just applied at the project-selection level.

**Explicitly not a permanent formula.** This pass used a fixed, one-time
read of the numbers, not a repeatable rule. Raised same session: whether
a periodic, non-AI version of this same measurement (commit velocity +
`milestone-audit.sh` status) should run on its own rather than needing an
interactive `/ideate` pass each time — open question, not decided here.

## 2026-07-24 (same session, immediate follow-up): sprint-scope reversed -- realisateur self-build, not the small MVP

Immediately after the multi-machine decisions above landed, asked
directly whether to actually proceed with the small MVP (crt-only,
static config, watch for the quota-race risk) or go straight to letting
realisateur self-build dexter's registration/rotation. **Answer: go
straight to realisateur self-build**, explicitly reversing item 4 above
(sprint scope) minutes after it was decided. Recorded here rather than
silently overwritten so a future session sees both the original reasoning
AND that it was deliberately overridden, not forgotten.

**What does NOT change:** items 1-3 above (dexter as a full local peer,
hardware-evidenced pinning only, two independent schedulers with the
named-and-accepted usage-gate race) still hold -- this reversal is scope
only (how much gets built before pausing to observe), not the
architecture. The quota-race risk named in item 3 is now MORE live, not
less: realisateur self-building dexter's own rotation means a second,
independently-probing scheduler goes live faster and with less manual
sequencing than the MVP's one-pinned-project plan -- worth watching
`run.log` on both boxes closely once dexter's own paced runner starts
ticking, same signal as before, just arriving sooner and less
controlled.

**What actually happens next:** the human sets up dexter's Claude Code
login (interactive OAuth, can't be done remotely) and clones this repo,
then hands dexter's own agent (realisateur or an equivalent bootstrap
session run ON dexter) the job of registering itself as a second host --
writing its own `schedule/_paced.conf` subset, installing its own
crontab tick, and deciding its own project pins -- rather than a human
hand-writing dexter's config per the MVP steps queued in FOCUS.md. Those
FOCUS.md MVP steps are now the STARTING POINT for that self-build, not a
human checklist to execute directly.

## 2026-07-24 (later, ON dexter): dexter registers itself as a second host

First session ever run **on dexter** rather than about it. Executes the
self-build handed over by the sprint-scope reversal above. Everything here
was decided and built from dexter's own WSL2 environment; the architecture
decisions (full local peer, hardware-evidenced pinning only, two
independent schedulers with the accepted usage-gate race) were already
settled and are **not** revisited.

### The governing constraint nobody had written down yet

This repo is not just shared configuration — it is **shared running code**.
mandark executes `bin/usage-paced-runner.sh` and `lib/sweep-loop-common.sh`
out of a checkout of this same git history, on a `*/5` tick. So any commit
here can change mandark's live behavior on its next tick, without a human
in the loop and without dexter being able to observe the result.

That made "don't break the other host" a hard build constraint rather than
good manners, and it shaped every change below: **every edit to a tracked
script that mandark executes was required to be a provable no-op on
mandark**, with the new behavior reachable only on a host that opts in by
having its own config file. Each one was tested in both shapes (invoked
through a `~/.local/bin` symlink, and as a copied install) before commit.
Worth stating plainly for future sessions on either box: the blast radius
of a commit here is both machines, immediately.

### Decision: per-host conf FILES, not a HOST column in the shared file

The prompt left the mechanism open (a per-host conf, a HOST-filtered
rotation, or something else). Chose **`schedule/_paced.<short-hostname>.conf`,
selected automatically by hostname, falling back to the existing
`schedule/_paced.conf` when a host has no file of its own.**

Rejected the alternative — one shared `_paced.conf` with a HOST column
filtered at dispatch — for a concrete reason rather than taste: that file
**already has an automated writer**. `weight-audit.sh` recomputes weights
from commit velocity and commits the result (commit `53b3f6f`, earlier the
same day). A HOST column would put two machines, one of them editing
mechanically on a timer, on the same lines of the same file. The conflicts
would be automated-vs-automated, arriving as merge conflicts in a cron job
rather than in front of a person. Separate files make that collision
impossible by construction: each host writes only its own path, so there
are no competing edits to reconcile — not fewer, none.

Secondary reasons: the host set is enumerable (`ls schedule/_paced.*.conf`)
rather than inferred by reading every line of a shared file; and a host
reading the wrong file is visible as a path in `run.log` instead of a
silently-empty filter result.

**The fallback is what makes it a no-op on mandark.** mandark has no
`_paced.mandark.conf`, so it resolves to `_paced.conf` exactly as before.
Deliberately did NOT rename `_paced.conf` to `_paced.mandark.conf`, even
though the symmetry would be tidier: mandark picks up new code from this
history on its next tick but there is no evidence it pulls new *commits*
automatically (see QUESTIONS.md), so a rename could point the live host at
a file its checkout doesn't have. The unscoped file stays the default.

Supporting fix in the same script: the repo root is now found by resolving
`readlink -f` on `$BASH_SOURCE` **before** `dirname`. The old code took
`dirname` directly, which yields `~/.local/bin` when invoked through the
installed symlink — fine while the conf path was hardcoded, useless once it
needs to be repo-relative. The original hardcoded absolute path survives as
a last-resort fallback for a copied-not-symlinked install, and a missing
conf now logs `FATAL` and exits non-zero instead of being ambiguous.

### Found while building: a silent exit-0 that would have burned quota

Pinning crt to dexter meant asking what actually happens when a conf's
`REPO_URL` is unreachable — which on dexter it genuinely is (below). The
answer was worse than "it fails":

`lib/sweep-loop-common.sh` ran `git clone "$REPO_URL" "$REPO"` **unchecked**,
under `set -uo pipefail` with no `-e`. A failed clone did not stop the run.
`$REPO` was never created, so the following `cd "$REPO/$REPO_SUBDIR"` failed
too — also unchecked — and every subsequent step ran in whatever directory
cron started in (`$HOME`): `git checkout`, `git fetch`, `git reset --hard`,
and then `claude -p` with `Write,Edit,Bash` enabled. The run then reported
`=== done ===` and exited **0**.

Reproduced against the pre-fix code before fixing it, rather than reasoned
about: with a stub `claude` on `PATH` as a tripwire, the old code invoked it
outside any repo and still exited 0. Post-fix, the same invocation aborts at
the clone with `FATAL` and rc=1, tripwire untouched.

Two consequences worth keeping separate. The mild one is wasted quota — a
full nightly-batch allocation spent in the wrong directory. The sharp one is
that `git reset --hard` and an agent with write tools were pointed at the
cron working directory; `$HOME` is not a git repo on dexter so the git steps
merely failed, but nothing in the code *depended* on that. This is exactly
the "fails loud? no exit-0 no-ops" line in BUILD-DISCIPLINE.md, and it had
been latent since the library was written — dexter is simply the first host
where an unreachable `REPO_URL` was reachable-in-practice enough to hit it.
Both steps are now checked, `notify-send` on failure, no-ops on the success
path so mandark is unaffected.

### crt: pin confirmed, dispatch blocked, enabled=0

**Re-verified, not carried over.** The 2026-07-20 confirmation was against
the old full VM's networking, and WSL2's NAT does not automatically
replicate it. Checked live from this environment: ICMP to `192.168.0.43` at
0% loss, TCP 80 open, and an HTTP 302 to `/login/?...&permissions=STATUS,SETTINGS_READ`
carrying `x-clacks-overhead: GNU Terry Pratchett` — i.e. **identified as
OctoPrint**, not merely a port that happened to answer. The hardware
evidence for pinning crt to dexter holds.

**But crt cannot actually run here yet, and the reason is repo access, not
network.** `schedule/crt.conf` sets `REPO_URL="/home/zach/git-remotes/crt.git"` —
a bare repo on *mandark's* filesystem, deliberately local so crt's VM
password never leaves that machine (crt.conf's own comment). dexter has no
such path and crt has no mirror; the deploy key crt.conf mentions "if a
private GitHub mirror is wanted later" was never set up. Confirmed by
running it: `bin/scheduler-run crt batch` → `fatal: repository
'/home/zach/git-remotes/crt.git' does not exist`.

So `schedule/_paced.dexter.conf` records the pin with `enabled=0` and the
unblock condition inline. Getting crt's source to dexter is a human call
with a real security dimension (that bare repo is local *on purpose*) — filed
to QUESTIONS.md rather than guessed at. dexter's rotation is therefore
empty, which the runner now logs explicitly on every rotation change:
an idle-because-blocked host and a misconfigured one must not look alike.

Also corrected in passing: dexter's crt line calls
`bin/scheduler-run crt batch`, not mandark's
`~/.local/bin/crt-nightly-batch-loop.sh`. crt.conf sets `BATCH_PROMPT` and no
`BATCH_SCRIPT`, so the generic entrypoint is the correct caller and **no
per-host wrapper needs to exist on dexter at all** — the wrapper in
mandark's line is legacy that `MIGRATION.md` is already retiring.

### `bin/scheduler-dev-cycle.sh`: made host-agnostic, deliberately not enabled

Asked directly whether dexter needs its own wrapper or whether the script
should stop hardcoding `SCHED_REPO="/home/zach/Documents/Project Archive/scheduler"`.
**Chose host-agnostic**, same resolution ladder as the runner (env override →
the repo the script itself lives in, symlinks resolved → mandark's original
path as fallback), identified by `.git` *plus* `bin/usage-paced-runner.sh` so
an unrelated parent git repo can't be mistaken for the scheduler checkout.

Reasoning: a dexter-specific wrapper would duplicate ~130 lines of worktree,
branch, lock and merge-policy logic whose whole point is being subtle and
correct, and it would drift the moment either copy changed. That is the same
per-host-wrapper sprawl `MIGRATION.md` and `bin/scheduler-run` exist to
retire — reintroducing it at the host level while retiring it at the project
level would be incoherent. The hardcoded path was also just a latent
portability bug: the script lives *inside* the repo it operates on, so the
location was always derivable.

**Making it runnable is not the same as running it, and `scheduler` is
deliberately absent from dexter's rotation.** Two hosts self-developing one
scheduler git history, each auto-merging to its own local `main`, is a
stronger version of the divergence that bit this repo earlier the same day —
two worktrees on a *single* host drifting far enough apart that a paced cycle
refused to reconcile them and escalated it to QUESTIONS.md. That entry was
cleared by `558c1c1` while this session was running, but by **fast-forward**,
which is available only while one side has not independently advanced. Two
hosts pushing to one `origin` is exactly the condition that removes it, so the
resolution does not generalize — it mostly documents what the cheap fix
depends on. Capability now, activation after the human call. Self-development
stays single-host.

### `bin/sync-crontab.sh` is not host-scoped — tick installed by hand

Did **not** use `sync-crontab.sh --apply` to install dexter's tick, and this
was checked rather than assumed: previewing it here shows it would install
fixed-cron `BATCH` lines for `groc-mangr`, `nine-speakers`, `sequestria` and
`vim-arcade` (parked in `_paced.conf`, so not suppressed) plus a sweep tick,
all for projects with no repo on this host, and would create `focus/` and
`questions/` symlinks pointing into mandark-only paths. It derives the whole
crontab from `schedule/*.conf`, and that directory describes *mandark's*
project set.

Host-scoping `sync-crontab.sh` properly is the natural follow-up — the
`_paced.<host>.conf` split solves participant *rotation* but not project
*registration*, which is the larger half — but it is a substantially bigger
change to the component that writes the live crontab on the box currently
doing all the work, and doing it in the same pass as everything above would
have put the riskiest change next to the least-tested one. Deferred to
FOCUS.md as its own item.

dexter's tick was installed directly instead, with the schedule **derived
from `schedule/_runner.conf` rather than retyped** (`RUNNER_CRON`,
`RUNNER_ENV`, `RUNNER_CMD` sourced and interpolated), so the one-source rule
still holds even though the installer doesn't. Both the crontab block and
this note record why it was hand-installed, so the next session doesn't
"fix" it by running `--apply` here.

Verified rather than assumed: `cron` is installed, `active (running)` and
`enabled` in this WSL2 container — a crontab in a box where nothing reads it
would have been the same class of not-actually-wired failure as everything
else on this list.

### Dropping crt from mandark's `_paced.conf`: opened, not merged

Prepared on branch `dexter/drop-crt-from-mandark-paced` rather than committed
to `main`. **Merging it now would create a gap, not prevent a double-dispatch.**
The change is only correct once dexter can actually dispatch crt; today it
can't (repo access, above), so landing it would stop crt running *anywhere* —
and crt is the highest-weight participant in the rotation (weight 3, ~211
commits/7d). The double-dispatch it guards against is currently impossible
for the same reason it can't be merged.

So the change exists, reviewed and ready, with the enabling condition stated
in both `_paced.dexter.conf` and the branch's commit message: flip crt to
`enabled=1` on dexter and land that branch **in the same change**.

### Addendum, same session: first concurrent two-host contact on this history

Flagged in advance as expected-first-contact rather than a bug, and it
happened exactly as predicted. While this session worked, mandark pushed 5
commits (`558c1c1`..`28a1617`) to the same `origin/main`. `git fetch` showed
5 commits on origin against 2 local.

**Resolved by rebasing dexter's two commits onto mandark's, cleanly, with no
conflicts.** The near-miss is worth recording: the two hosts edited the *same
three files* — `FOCUS.md`, `QUESTIONS.md`, and `lib/sweep-loop-common.sh` —
and it only merged cleanly because the edits happened to land in different
regions (mandark added a push-diagnosis block at the end of the library, this
session hardened the clone/`cd` near the top). That is luck, not design. It is
the same collision the `_paced.<host>.conf` split was built to make
impossible for participant config, still fully live for prose files and code.

Two things the incoming commits changed for the work above, both folded in
rather than left stale:

1. **`28a1617` decides the transport question** this session had just filed:
   non-GitHub projects reach dexter via a local bare remote over LAN/SSH.
   That rules out the GitHub-mirror option for crt and narrows the open
   QUESTIONS.md item from "which of four approaches" to a concrete setup
   step. One factual correction fed back: `28a1617` says crt "already uses
   this exact pattern", but crt's `REPO_URL` is a plain filesystem path that
   resolves only on mandark — verified from dexter by running it. crt is the
   policy's first *unbuilt* instance, not evidence of it already working.

2. **`558c1c1` cleared the single-host worktree-divergence question** this
   session had cited as grounds for keeping self-development single-host. It
   was resolved by fast-forward — which is available only while one side has
   not independently advanced, precisely the condition two pushing hosts
   remove. The citation was reworded rather than dropped: the resolution
   documents what the cheap fix depends on, and this session's own rebase is
   the first case where that dependency no longer held.

Neither host was wrong and nothing was lost, but the ordering was pure timing:
had `28a1617` landed an hour later, this session would have filed a decided
question as open. Worth knowing that with two hosts writing prose into the
same files, "read the current state" now has a shelf life measured in minutes.

## 2026-07-24 (same session, third follow-up): auto-pull wired into usage-paced-runner.sh

Answers QUESTIONS.md item #2 from the dexter self-build: no, nothing pulled
`origin/main` on mandark before this -- confirmed live (a human had to
`git pull`/merge by hand to bring dexter's pushed commits into mandark's
checkout). Since this repo is shared **running code**, not just shared
config (both hosts execute `usage-paced-runner.sh`/`lib/*.sh` straight out
of their own checkout on a cron tick), that gap meant a push from either
host had zero effect on the other until a human intervened -- silently.

**Fix:** `usage-paced-runner.sh` now pulls at the start of every tick,
inside the flock (so it can't race a dispatch already in flight), before
resolving which participants file to read (so a freshly-landed host-scoped
conf takes effect the same tick, not one tick later). `git fetch` +
`merge --ff-only`, matching the fail-loud-not-block philosophy already used
elsewhere (`usage-gate.sh`'s ERROR -> HOLD, `SCHEDULER_CONF_VERSION`'s soft
validation): a dirty tree, failed fetch, or genuine history divergence all
log loudly and let the tick proceed on whatever's already checked out,
rather than fabricating a merge commit unattended or halting the
dispatcher entirely over something only a human can resolve. `timeout 20`
on the fetch so a dead network can't hang a tick indefinitely.

Symmetric by construction -- same script both hosts run, so this closes
the gap on dexter too, not just mandark. Deployed to
`~/.local/bin/usage-paced-runner.sh` same session; `scheduler pacing`'s
drift check confirms OK.

## 2026-07-24 (same session, fourth follow-up): crt's bare-repo access -- dexter clones mandark over SSH

Resolves QUESTIONS.md item #1 from the dexter self-build (how does dexter
reach `crt.git`, a bare repo deliberately kept local to mandark so the VM
password in HANDOFF.md never leaves that machine). Of the four options
listed there, chose **(b): dexter clones mandark over SSH**, explicitly
parking (c) "host crt on dexter instead, invert the direction" as the
eventual direction once dexter's own git hosting is proven out --
human-directed, not guessed: smaller and reversible now, bigger change
later once there's more confidence in dexter as a peer.

**Built, mandark side (this session, interactive, on mandark):**
- `openssh-server` installed and enabled (previously entirely absent --
  confirmed via `systemctl`/`dpkg` before assuming). Listens on
  `0.0.0.0:22`/`[::]:22`; mandark has exactly one real network interface
  (`192.168.0.27`, LAN), so this is LAN-scoped in practice despite the
  bind address. `sudo apt-get install`/`systemctl enable` needed an
  interactive password, so the human ran those two commands directly; this
  session only verified the result (`systemctl is-active`, `ss -tlnp`).
- A dedicated key pair (`dexter_mandark_deploy`, generated ON dexter, never
  touched mandark) added to mandark's `~/.ssh/authorized_keys` with
  `command="git-shell -c \"$SSH_ORIGINAL_COMMAND\"",no-port-forwarding,
  no-agent-forwarding,no-X11-forwarding,no-pty` -- restricted to git
  protocol only, same "own key per machine, independently revocable,
  narrowly scoped" pattern as every other deploy key in this repo
  ([[scheduler-cron-ssh-auth]]), not a general login key.
- `schedule/crt.conf`'s `REPO_URL` changed from the bare local path to
  `ssh://mandark-lan/home/zach/git-remotes/crt.git`. Safe because crt now
  runs on dexter exclusively (see below) -- mandark reaching itself over
  SSH here would be dead code, not a real case this needs to support.
- Merged dexter's prepared `dexter/drop-crt-from-mandark-paced` branch
  (crt dropped from `schedule/_paced.conf`) -- landed now rather than left
  pending, since the REPO_URL half of "DO NOT LAND ALONE" is now also
  done. mandark's own AUTONOMY/rotation is otherwise unaffected.

**Deliberately NOT done yet: `_paced.dexter.conf`'s `crt` line stays
`enabled=0`.** SSH access is provisioned but not live-verified from
dexter's actual environment -- same "verified by running it, not assumed"
standard dexter itself used to find this gap in the first place. Real
remaining steps, written directly into `_paced.dexter.conf`'s crt comment
so whoever does this next doesn't have to reconstruct them: dexter needs
the `mandark-lan` Host alias in its own `~/.ssh/config`, then
`ssh -T git@mandark-lan` (expected to drop the connection immediately --
git-shell has no interactive shell, so that's success) and
`git ls-remote ssh://mandark-lan/home/zach/git-remotes/crt.git` (the real
test -- should list crt's refs) before flipping `enabled` to `1`.

**Accepted gap in the interim:** crt currently runs on NEITHER host --
dropped from mandark, not yet enabled on dexter. Chosen deliberately over
bundling an unverified enable into this same change (which would couple
"drop from mandark" to a flip nobody could test yet, and crt is the
highest-weight participant in `_paced.conf`, so getting that coupling
wrong would be a real throughput cost, not a cosmetic one). Visible and
traceable to "waiting on live dexter verification" via the comment left
in place, not a silent gap.

## 2026-07-24 (same session, fifth follow-up): crt live-verified from dexter, enabled

Closes out QUESTIONS.md item #1 for real. From dexter itself:
`git ls-remote ssh://mandark-lan/home/zach/git-remotes/crt.git` returned
real refs (`HEAD`/`refs/heads/main`), and the SSH host key fingerprint
(`SHA256:L8eHLUaeERW+6p428gZ+V6LjoHqUAlYvuTgEXQyD3Eg`) was cross-checked
against mandark's actual `/etc/ssh/ssh_host_ed25519_key.pub` and matches --
not just "something answered on port 22," confirmed to actually be
mandark. `crt` flipped to `enabled=1` in `schedule/_paced.dexter.conf`.

crt now runs on exactly one host (dexter), reachable over the restricted
git-shell-only key, source never leaving the LAN. The interim "runs on
neither host" gap noted in the previous entry is closed as of this
commit.

## 2026-07-24 (same session, sixth follow-up): push-on-cycle, not push-on-morning-review — durable policy correction

Directly answers "why not let dexter self-develop scheduler too" (QUESTIONS.md
item #3) by fixing what actually made it unsafe, rather than adding a
scheduling mutex on top of an unsafe base. Human-directed, explicit: *"this
is the key problem and needs to be fixed durably in several places...
agents should push right away to the shared repo."*

**The bug, stated precisely:** `bin/scheduler-dev-cycle.sh` merged each
finished cycle's commits into LOCAL `main` but never pushed -- by design,
documented as "never touching main, never pushing... work builds up for a
single morning review." That was read straight out of the 2026-07-18/19
Push/Merge policy notes in FOCUS.md, which said to "prefer the old
review-gate branch behavior... until safety work lands." The failure mode
this produces has ALREADY happened for real this session (see the QUESTIONS.md
entry cleared earlier today, "main/paced-2026-07-24 divergence"): two
independent local `main`s, each with unpushed work built on the same stale
base, diverging with zero temporal overlap required -- pure sequencing, not
a race. A same-host-two-worktrees version of it is what originally
triggered noticing this; multi-host self-dev (mandark + dexter both
running this script) is the same shape with a longer, more likely-to-bite
staleness window (an unpushed local merge sits invisible to the other host
until SOMEONE pushes, which the old policy deferred up to 24h).

**Why the earlier scheduling-lookahead proposal (check if the other host
has a job due within N minutes, skip if so) does not fix this on its
own:** it prevents literal time-overlap, but the actual incidents were
sequential, not simultaneous. A mutex on timing does nothing about a cycle
that runs at 10:15, cleanly after a 10:00 cycle elsewhere finished, if the
10:00 cycle's work was never pushed. Worth having as a cheap secondary
safeguard against wasted concurrent work, but it was never the load-bearing
fix -- flagged explicitly during design so it isn't mistaken for one later.

**Fix, applied durably (code, not just documentation):**
1. `bin/scheduler-dev-cycle.sh` now pushes `origin/main` in the SAME cycle
   immediately after merging, not on a deferred human schedule. Fetches +
   `--ff-only`s onto `origin/main` right before merging (shrinks, doesn't
   eliminate, the staleness window), and on a rejected push does one
   fetch-and-reconcile retry before giving up loudly (`CRITICAL` log line +
   `notify-send -u critical`) -- local `main` is never silently left ahead
   of `origin` with no signal.
2. Review model restated explicitly, everywhere this policy is written
   down: **revert-based, not a pre-push gate.** This was already true of
   every OTHER push this repo makes (CLAUDE.md's general push permission) --
   the self-dev cycle's own deferred-push behavior was the one place still
   contradicting it, unnoticed until multi-host self-dev made the gap
   costly instead of theoretical.
3. FOCUS.md's Push/Merge policy sections corrected in place (not silently
   rewritten -- the retracted caveat is left visible with what changed and
   why), so a future read of that file doesn't reintroduce the same
   misunderstanding.

**Still open, not built this pass:** the scheduling-lookahead advisory
(cheap secondary safeguard against literal overlap) -- would need each
host to publish a small "about to dispatch X" advisory file, since
rotation isn't literally time-scheduled today. Worth doing as a fast
follow, not required for QUESTIONS.md item #3 to be considered resolved.

## 2026-07-25 — manual concurrent burst test, groundwork for a future "mega burn near quota deadline" mode

Zach asked directly to fire a burst of concurrent agents across projects,
bypassing `usage-paced-runner.sh`'s global flock on purpose, reasoning that
unclaimed quota in the current window is quota that just goes unused (the
already-documented 40-50pt/week slack finding, 2026-07-24). This is a real
test of a mechanism that does not exist yet -- there is no automated "burn
down remaining slack before the window rolls" mode today, only the steady
one-at-a-time paced rotation. This entry records what the manual version
found, as groundwork for whether/how to build that mode for real.

**What ran, on mandark, by hand:** each project's own wrapper script invoked
directly and concurrently (`chezz-nightly-batch-loop.sh`,
`gardien-nightly-batch-loop.sh`, `senechal-nightly-batch-loop.sh`,
`scheduler-dev-cycle.sh`), i.e. the same commands `_paced.conf` would run,
just not serialized through the rotation's flock or gated by a fresh
`usage-gate.sh` probe first.

**Deliberately excluded, before running anything:**
- `home-assistant` -- controls a live physical instance; unattended +
  concurrent + no human review is exactly the risk its own
  `AUTONOMY_TIER=low` and batch-prompt physical-side-effect warning exist
  for. Any real mega-burn mode should hard-exclude physical-effect projects
  by default, not opt them in unless explicitly told to.
- `realisateur` -- its own nightly-batch writes this same repo's inbox/
  FOCUS.md; running it concurrently with the live interactive session doing
  the excluding would have been a self-inflicted version of the exact
  dirty-tree-during-a-live-session hazard this ecosystem already treats as a
  hard stop. A mega-burn mode triggered FROM an interactive realisateur
  session should always self-exclude for the same reason.
- `crt`/`wtul` (dexter-pinned) -- not reachable from a mandark shell at all.
  A real cross-host mega-burn needs its own per-host trigger, or a
  mechanism that can reach both; this test only exercised mandark.

**Results:**
- `senechal`, `gardien` -- clean concurrent runs, real fixes shipped and
  pushed (senechal: a GPG-private-key-header redaction gap + a nested-
  special-file silent-drop bug, 73/73 tests; gardien: fail-loud on an
  unreadable `gardien.json` instead of a raw traceback, 66/66 tests).
  **No cross-repo interference of any kind** -- different repos, different
  working trees, nothing to contend over.
- `chezz` -- silent no-op. Its own engine considers the job `expired`
  (staleness logic keyed to its normal cadence/crontab presence) and
  declined to do real work. **This is the first real footgun for a
  mega-burn mode**: per-project wrappers built around "runs on its own
  normal schedule" assumptions can silently skip an out-of-band burst
  trigger and look identical to a real run in the exit code (0) --  only
  visible by actually reading the log, not by trusting "it ran." A real
  mega-burn mode needs either a `--force`/bypass-staleness flag threaded
  through `sweep-loop-common.sh`, or to explicitly surface "skipped as
  expired" as a distinct, loud outcome rather than folding it into a
  normal exit.
- `scheduler` -- the one real collision, and the useful finding. Its dev
  cycle hit a genuine merge conflict in `.scheduler/FOCUS.md` while
  merging `paced/2026-07-25` into `main`, racing a concurrent edit to the
  same file from the dexter-side interactive session (diagnosing the wtul
  deploy-key gap, same evening -- see `_paced.dexter.conf`'s and
  `.scheduler/QUESTIONS.md`'s wtul entries). Handled correctly: the merge
  aborted automatically rather than forcing a resolution, leaving the work
  stranded but intact on `paced/2026-07-25` (`0bc4ea3`, still unmerged as
  of this writing) for a human to resolve. **Nothing corrupted, nothing
  force-pushed, nothing silently lost** -- but it is live, not theoretical,
  confirmation of the exact risk `_paced.dexter.conf`'s own header already
  named as the reason `scheduler` is deliberately absent from dexter's
  rotation ("two hosts independently committing to one scheduler git
  history... a stronger version of the divergence that bit this repo
  earlier the same day").

**Groundwork conclusions for a real mega-burn mode, not built this pass:**
1. **Cross-repo concurrency is safe as tested** -- N different projects'
   wrappers can run fully concurrently with zero coordination beyond what
   already exists (each wrapper's own flock/logging), because they touch
   disjoint repos. A mega-burn mode does not need a new locking primitive
   for the common case.
2. **Same-repo concurrent writers are the actual danger**, not "many
   projects at once" in general. The rule a real mega-burn mode needs: never
   dispatch two writers against the same repo concurrently, whether that's
   two participants pointed at the same project (shouldn't happen given
   today's config) or -- the case that actually bit this test -- one host's
   automated cycle and a second host's interactive session both live on the
   same repo at the same time. `scheduler` is the one project this
   ecosystem already self-develops from two independent surfaces (mandark's
   paced cycle, any interactive session on either host); anything else that
   grows a second interactive/dev surface inherits the same risk.
3. **This test did not exercise the actual quota-overshoot risk.** It ran a
   fixed, hand-picked set of 4 wrappers directly, never consulting
   `usage-gate.sh` at all -- so it proves concurrent *execution* is safe,
   not that N-way concurrent dispatch stays inside the account's real 5h/7d
   ceiling. A real mega-burn mode needs its own gating step: read remaining
   slack once, estimate a per-job cost budget, and burst only as many
   participants as plausibly fit -- not "fire everything and hope."
4. **Staleness/expiry logic needs a bypass path** (see `chezz` above) or a
   mega-burn mode will silently under-deliver against projects that look
   included but quietly no-op.
5. **Exclusion list needs to be a first-class input, not ad hoc.**
   Physical-effect projects (`home-assistant`, and by the same logic
   anything gardien eventually does with real deletes) and the
   triggering session's own project (`realisateur` here) should be
   excluded by default, overridable only with an explicit ask -- this test
   got that right by hand, a real mode should encode it structurally.

Not built this pass, deliberately -- this is exactly the "genuinely new
mechanism, record and queue" case per `/ideate`'s own contract (see
realisateur `.claude/FOCUS.md` 2026-07-25 for the cross-referenced entry).
Immediate cleanup still pending from this test: resolve the stranded
`paced/2026-07-25` merge conflict in `.scheduler/FOCUS.md` by hand.

## 2026-07-25 — follow-up to pass #3: the orphaning ended the same day it was found

The 07-24 entry above ("`crontab -l` returns 'no crontab for
svc-vaporwave' — literally empty", zero dispatch for 4 days) was **true
when written**. What it never got was a closing line: the crontab was
installed later that same day, and BLOCKERS.md's own entry recorded that
("Fixed: home-dir access granted, both nightly-batch loops installed and
confirmed via `crontab -l`"). Verified again today with
`sudo -u svc-vaporwave crontab -l`: both lines present, and both ran —
vkv-inventory 04:00→04:05 pushing `c2f7d9d`, aedile 03:00→03:06 pushing
`aedile-nightly/2026-07-25` and PR #3. `scheduler glance` had been showing
them 5–6h fresh all along.

The cost was in the copy that didn't get the closing line.
`schedule/_paced.conf` carried "confirmed 2026-07-24: no crontab exists
there" on both project lines as a statement of *current* state; a
2026-07-25 ecosystem audit read it, believed it over the live glance, and
ranked "silently orphaned, zero dispatch for four days" as its **#1
finding** — recommending a remedy (a human installing a crontab) that
would have been a no-op. Corrected in `d14a2f2`; both projects are now
adopted into a scheduler-managed block (`774f55a`) and stay at weight 0
deliberately, because re-enabling locally would double-dispatch.

The durable lesson, now doctrine in realisateur's BUILD-DISCIPLINE.md as
pattern 7 ("a claim outlives its verification"): a dated journal entry is
safe because it is *stamped* — it says when it was true. A bare comment in
a live config file is not, because it reads as present tense forever.
State that changes belongs in something that *derives* it (the queued
`scheduler dispatchers` command), not in prose that has to be maintained
in four places. What was real underneath: aedile's `run.log` shows
completed cycles on 07-20, 07-21 and 07-25 only, a genuine 07-22→24 gap
whose likely cause was world-writable `~/.ssh` blocking `git push` —
which aedile's own 07-25 run detected and fixed.

## 2026-07-26 — /ideate: ecosystem-wide roadmap realignment (four decisions)

Interactive /ideate pass, human-directed, scoped by the ask: "adjust
scheduler's FOCUS.md roadmap/milestones based on a universe/ecosystem-wide
understanding of scheduler's role." Inputs: realisateur's doctrine set
(UNIVERSE.md's mechanism/judgment anatomy and Law 3, PLAYBOOK.md's
2026-07-26 build/import/retire audit, PRECIPITATION.md's stamping
doctrine, BUILD-DISCIPLINE pattern 13) plus this repo's own FOCUS/
QUESTIONS/BLOCKERS state. No implementation code touched. All four
decisions were asked directly (AskUserQuestion), none guessed.

**1. Milestone transition — front-door consolidation is now the Current
stability milestone.** The zero-silent-failure bar sits at 4/5 with its
last box (QUESTIONS-reply consumption, the vkv-inventory gap) routed to
realisateur — unclosable from this repo. Meanwhile realisateur's doctrine
already treats scheduler's front-door redesign as Law 3's first
retirement-pressure proof, an accretion freeze was already in effect, and
the 2026-07-25 19:51 backlog entry (itself a re-derivation-convergence
promotion) carried the full locked spec. Declaring it merely aligns
FOCUS.md with reality. Old bar recorded as reached-pending-external; the
weight exit (scheduler 4→3, realisateur 3→1) now keys off the new bar.

**2. Axis 1 resolved: option (a), converge paced dispatch on
`bin/scheduler-run` — WITH a hard sequencing gate.** The 2026-07-25
finding stands (MIGRATION.md's flip is a no-op for every project it
names). Rather than scoping the axis down or retiring it, the paced
`_paced*.conf` command column itself migrates to `scheduler-run` — but
only AFTER the live-edit risk is closed: the paced runner must dispatch
from a committed/validated conf (the approved symlink-deploy import +
the refuse-dirty-confs item are that gate). Then flip one project at a
time, chezz first. This also unblocks Play 3's loop-fork retirement in
its clean form. QUESTIONS.md's open entry got its `> ` answer.

**3. PLAYBOOK asks approved: catabolic worklist + import swaps (a)-(c).**
The two empty `> ` slots under BLOCKERS.md ## realisateur calls 3 and 4
are now answered (approved) — symlinks for pacing deploy/drift, ccusage
core, gitleaks-under-harness; and the ~1,000-line retirement list, one
retirement per pass. (d) restic waits for gardien to unpark. Both queued
as [batch] backlog items here so they have a dispatch path
(BUILD-DISCIPLINE pattern 13: a decision without a dispatch path is not
wired). Calls 1, 2, and 5 in that BLOCKERS entry remain open for Zach.

**4. Backlog deduplication per PRECIPITATION stamping doctrine.** Three
same-shape re-arrival clusters merged into single dispatch units at the
top of the Backlog, originals stamped subsumed (spec stays in place,
dispatch moves): [iface: sweep-attribution] (21:22 + 21:56),
[iface: usage-ceiling-conf] (22:15 + 17:06 + the filed-separately
pointer), [iface: crash-durability] (09:32 committed-unpushed rescue +
the dirty-worktree crash-aftermath item — one guard, same code site).

**Vision-debt reading (ideate step 4.5):** backlog ≈78 top-level items,
oldest un-started material dates to 2026-07-18-19; intake this week ran
~10+ items against ~2-3 cleared. Still diverging — but this pass moved
the drain side: the new milestone is itself a large retirement, the
catabolic worklist deletes rather than adds, and the merges cut three
future passes into one each. The convergence lever remains realisateur's
pruning + the re-admission policy call still open in BLOCKERS.

## 2026-07-26 — the usage-gate ceiling reads from a conf, not just env

Queued as a FOCUS.md backlog item 2026-07-25 (human-directed) and built
this paced cycle. The pacing knob that decides whether *any* background
job runs — `USAGE_CEILING` — lived in exactly one place before today:
`bin/usage-gate.sh`'s own `CEILING="${USAGE_CEILING:-0.85}"`. Changing it
durably meant editing `RUNNER_ENV` in `schedule/_runner.conf` and running
`bin/sync-crontab.sh --apply`, which ends with the value **retyped onto a
generated crontab line** — a build-discipline violation ("config read from
one source, not retyped per file") on the single most consequential dial in
the system.

Now: `schedule/_usage.conf` (base) and `schedule/_usage.<host>.conf`
(per-host) are read directly by the gate, resolved **per field**, with
explicit env still winning. Edit the conf, the next 5-minute tick uses it —
no `--apply`, no crontab edit, no redeploy.

Three details worth recording, because each was a decision:

1. **Parsed, not sourced.** Every other conf in `schedule/` is sourced.
   This one is scanned for `KEY=value` lines instead: the gate holds a live
   OAuth token and its own `CEILING`/`QUIET` variables at that moment, and
   sourcing would let a stray line in a config file clobber them. Scalar
   knobs don't need shell semantics, so nothing is lost.
2. **A bad value is a loud ERROR, not a silent fallback.** An unparseable
   or out-of-range knob exits 2 (which every caller already treats as
   HOLD) naming the file, the key, and the value. Deliberately chosen over
   warn-and-use-the-default: pacing against a typo'd ceiling is the failure
   mode you cannot see, and stopping dispatch is the recoverable direction.
   `USAGE_CEILING=85` (percent instead of fraction — the likely typo) is
   caught by the range check, not accepted as "way above any utilisation."
3. **Provenance is in the output.** The verdict line gained one field:
   `knobs=ceiling:_usage.mandark.conf,min_slack:default,rush_min:default`.
   Without it, "is my edit live?" is unanswerable except by reasoning about
   precedence — and the ambient-env case below is exactly why that matters.
   No new output *lines*, per the accretion freeze on scheduler's views;
   `bin/scheduler pacing` prints the gate's line verbatim and was verified
   to still parse it.

**Retired, named explicitly:** setting `USAGE_CEILING` via `RUNNER_ENV`.
It still physically works (it is plain env, so it lands at precedence 1),
but `_runner.conf` now says not to — because env outranking the conf means
a forgotten value on the crontab line would silently beat the file someone
just edited. Live evidence this is not hypothetical: today's cycles ran
with a **hand-set `USAGE_CEILING=0.99` in the dispatcher's environment**
while `_runner.conf` says only `PACED_MAX_PER_TICK=16` and the crontab
preview matches the repo — noted by an earlier cycle today as supporting
evidence for this very item, and confirmed again here (the gate's live
verdict at the built-in 0.85 default is HOLD; at the hand-set 0.99 it is
what has actually been dispatching). This change does not disturb that: env
still wins, so live pacing behavior is byte-identical until a human either
uncomments a value in `_usage.conf` or drops the ambient override.

**Fixed in passing, same file:** `USAGE_RUSH_BEFORE_RESET_MIN` was read
inside the python decision core via `os.environ`, but the gate never passed
it there — so it only ever took effect when a *caller* had exported it, and
a shell-var (or, now, conf) value would have been silently ignored. It is
now passed explicitly alongside `CEILING`/`MIN_SLACK`.
