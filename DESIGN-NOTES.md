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
