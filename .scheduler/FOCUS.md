# FOCUS — scheduler (what its own nightly job should work on)

The scheduler's Tier 2 job (`/nightly-batch`) is scoped by this file, same
as every other project. Difference: this project is the **meta-tool** that
controls all the other jobs.

## The long arc (2026-07-28, interactive `/ideate`, realisateur)

*Written because the vision was true but scattered: it lived in six
sections of this file (Vision 2026-07-20, Architecture 2026-07-20,
Registration, Short list + roadmap 2026-07-24, Consolidation roadmap
2026-07-20, and the 2026-07-25 19:51 front-door entry now serving as the
milestone spec), plus DESIGN-NOTES.md. None of them was wrong. But
answering "what are we building, and is this idea on the path" required
reading all six and reconciling three re-sequencings. This section is the
single telling. The six sections below stay as the DETAIL and the
receipts — where a claim here is thin, they are the authority; where they
disagree with each other, this section is the reconciliation.*

**Not decided by writing this down.** Everything below that is a decision
carries its own date and provenance from those sections. Where something
is genuinely still open, it says so by name rather than being smoothed
over — silence here does not mean settled.

### The vision, in one paragraph

Scheduler runs **a fleet of autonomous builders, not a fleet of
maintained projects.** Projects propose their own work, build it
unattended, and push it; the human's role is not to operate the machine
but to be the one thing the machine cannot supply — judgment on the
questions it has correctly identified as beyond its authority. Safety
comes from a **per-project autonomy dial matched to that project's actual
stakes**, not one global trust ceiling: a vim game and a home-assistant
install with physical devices should never share a policy. Above the dial
sits one universal gate that no tier overrides — genuinely irreversible
actions (a new paid dependency, a physical actuation, a non-revertible
production cutover) always need a human. Self-spawning is the *point*,
not the risk: realisateur scaffolding new projects unprompted is the
value this system exists to produce, and the job is to make that safe by
construction (bare local remotes, cost caps, the tier) rather than to
rein it in afterward.

The human surface to all of that is **three printable views and a text
file** — not a dashboard, not a TUI. You read what is happening, you
answer inline, the answer round-trips into the next run.

### Why the surface keeps being the bottleneck

The recurring failure mode of this project, in Zach's own words
(2026-07-20, and re-derived independently 2026-07-25):
*"my ideas outpace implementation of stable versions so the target is
always moving."* Every capability added so far arrived with its own view
— glance, status, overview, next, explain, focus, questions, report,
pacing-show — because adding a surface is cheaper than folding one. The
result is a tool whose `usage()` is longer than most of its commands and
which the owner operates by trust rather than understanding. The
ACCRETION FREEZE now in force is the correction: **no view gains a legend
line or a new verb until the fold lands.** New needs go into the spec, not
into the tool.

This is also why the roadmap is sequenced the way it is below. Every
consolidation step is a **retirement**, and each one names what it
replaces. A step that only adds is out of order by definition.

### The milestone chain, working backward from the vision

**Now (in progress) — one front door.** Fold the entire human surface
into three stable PRINTABLE views: `scheduler` noargs (now/next plus a
one-line gate/dials footer), `scheduler <project>` (detail, inline reply,
reorder and reweight from there), `scheduler blockers` (the one
blocked-on-you place). Every legacy view retires to a one-line redirect
stub; `usage()` drops to ~20 lines; each view footer prints its own
mutation one-liners. Locked decisions: HARD FOLD + RETIRE, STATIC + VERBS
(no TUI), DIALS as a one-line footer with full pacing detail staying under
`pacing`. **Open inside this step:** what happens to the editor-opening
verbs (`-p`, `-f`, `-q`, `-b`) — the bar names printable views, and those
four print nothing. Filed as a question, not assumed either way.

**Next (not started) — dispatch converges on one path.** The paced
runner's `_paced*.conf` command column becomes `scheduler-run <project>
nightly-batch`, retiring the per-project loop-script forks to 5-line
shims. **Hard sequencing gate, not optional:** the live-edit risk closes
FIRST — the runner must dispatch from a committed, validated copy of
`_paced*.conf` (symlink-deploy plus refuse-dirty-confs are the two halves)
and drift must fail loud. Then one project at a time, chezz first,
watching a full dispatch before the next. This is where `AUTONOMY_TIER`
stops being a declared-but-unread field and becomes engine-enforced, and
where `REGISTRATION.md` plus a conf schema version have to exist so the
migration has something to stamp.

**Then (decided in shape, not scheduled) — one file per project.** Item 0:
collapse the report and `QUESTIONS.md` into a single file the human
answers inline in, once every project has settled onto
`SCHEDULER_SUBDIR=".scheduler"`. Deliberately parked behind the layout
migration so the two file-shape changes can be verified independently.

**Later (direction only, deliberately vague) — scheduler leaves the
laptop.** No local checkout; scheduler owns its own scope and is runnable
anywhere; the GitHub-hosted projects come off this machine. That world is
where the daemon question genuinely reopens — the 2026-07-20 decision was
"keep cron," and its named revisit trigger is not project count but
`usage-paced-runner.sh` itself becoming observably expensive to re-derive
every 15 minutes. Until then the build-toward-it rule binds every new
mechanism: state in files and re-derivable per invocation, idempotent
poll-friendly checks, dispatch logic separable from what triggers it.

**Not queued.** Google Calendar integration, glance-formatting polish, the
BLOCKERS-as-computed-view redesign, the status-vocabulary unification.
Real, kept, past the current bar.

### What this arc implies for triage

An idea belongs in the ACTIVE set only if it serves the current step —
folding a view, retiring a surface, or closing the dirty-conf gate that
gates the next step. An idea that adds a view, a verb, or a legend line is
**against** the current step, not merely past it. That is a sharper test
than park-by-default and it is the one to apply until the fold lands.

## Stability milestone

**Current:** the entire human surface is three stable PRINTABLE views — `scheduler` noargs (now/next + one-line gate/dials footer), `scheduler <project>` (detail, inline reply, reorder/reweight from there), `scheduler blockers` (the one blocked-on-you place) — with the legacy views (glance/status/overview/next/explain/focus/questions/report/pacing-show as separate surfaces) retired to one-line redirect stubs and `usage()` ≤ ~20 lines; ACCRETION FREEZE holds until then (no view gains a legend line or new verb — new needs go into the spec) — status: in-progress

*(Declared 2026-07-26, interactive /ideate, human-directed: adopted from
the 2026-07-25 19:51 front-door-consolidation entry in the Backlog, which
carries the full locked decisions — HARD FOLD + RETIRE, STATIC + VERBS no
TUI, DIALS as a one-line footer. This is Law 3's first retirement-pressure
proof per realisateur/UNIVERSE.md, and the stated `_paced.conf` weight
exit: scheduler 4→3, realisateur 3→1 when this bar is reached.)*

**Previous milestone (zero silent failures) — 4 of 5 boxes done; treated
as reached-pending-external 2026-07-26:** the one open box (every
project's `/nightly-batch` consuming its own QUESTIONS replies — the
vkv-inventory gap) is routed to realisateur and cannot be closed from
this repo; it stays tracked below as that project's obligation, not as
this repo's active bar. Original bar text follows for the record:

scheduler dispatches every registered project unattended with zero silent failures — a run that gets cut off, can't push, or has its assumed external dependency (a migrated crontab, a credential) quietly stop being true is always flagged loudly, never left to look like nothing happened — and the user can explain how the system actually works instead of just trusting `bin/scheduler` to smooth over the parts they don't follow — status: in-progress
Done when:
- [x] Stale `.active`-marker / stranded-run detection built (a run cut off before any commit shows up nowhere today) — queued 2026-07-20, built on `paced/2026-07-24` and reconciled into `main` 2026-07-24: `cmd_sweep` in `bin/scheduler` scans `~/.local/share/scheduler-registry/*.active` and flags any marker whose PID is no longer running as stranded (its EXIT trap never fired — killed, crashed, or a reboot, most likely before any commit, which is why the git-based checks can't see it), plus a softer "still running, unusually long" flag for a live PID past `STALE_ACTIVE_MARKER_SECONDS` (default 7200s). Verified with fabricated markers (dead-PID correctly flagged STALE, live-PID/just-started correctly silent).
- [x] Stale/incomplete-push visibility built (`pushed: no` in `scheduler status`/`sweep.log` says WHY — spend-limit cutoff vs. something else — instead of a silent generic no-op; this is what the 2026-07-24 chezz/wtul credential-gap misdiagnosis actually needed and didn't have). Built this paced cycle: `lib/sweep-loop-common.sh`'s existing `WARNING: local commit made but NOT pushed` case now emits a `push reason:` line distinguishing four causes — claude's own run exited non-zero (STATUS=FAILED, likely a turn/spend cutoff before it reached a push step); `git ls-remote` couldn't read `origin/$BRANCH` at all (SSH/auth/network failure); local is a clean fast-forward of remote and a read-only `git push --dry-run` says it WOULD succeed (claude simply never ran `git push` this cycle, not a credential/conflict problem); or remote has commits local doesn't (genuinely diverged, needs merge/rebase, not a credential issue). All read-only (`--dry-run` only, no live push attempted by this diagnostic). `bin/scheduler`'s `build_status_report` now greps and surfaces the new `push reason:` line alongside the existing `WARNING:` line. Verified: `bash -n` on both files; the fast-forward/dry-run-succeeds and genuinely-diverged branches each reproduced against real throwaway git repos; the unreachable-remote branch reproduced with `env -u SSH_AUTH_SOCK` (simulating cron with no agent) against a real GitHub SSH remote, correctly surfacing "Permission denied (publickey)" as the reason instead of a generic no-op; a fabricated `sweep.log` confirmed `scheduler status`'s grep picks up the new line end to end. Earlier partial progress (the glance-view "stranded local commits" footer, visibility that it's unpushed) stays as-is, unchanged. The credentials half (issuing a real deploy key per repo) is still human-only, unchanged.
- [x] Generalized "disabled-with-unverified-external-dependency" sweep built (any `_paced.conf`/`schedule/*.conf` line with a `MIGRATED to X` comment gets its claimed destination checked to still exist) — the exact gap that let aedile/vkv-inventory sit undispatched 4 days undetected, fixed by hand 2026-07-24 and generalized on `paced/2026-07-24`: `cmd_sweep` now re-checks every claim on every sweep — SSH-unreachable reports UNVERIFIED (never silently treated as confirmed), reachable-but-no-matching-crontab-entry reports ORPHANED, reachable-and-found reports verified. Verified live against the real aedile/vkv-inventory case — `svc-vaporwave` correctly comes back UNVERIFIED, fails fast (~0.05s) rather than hanging.
- [x] A real, honest explainer of how the system currently works exists — built on `paced/2026-07-24` as `scheduler explain`/`-e`: a plain-English "here's what happens when you do X" walkthrough covering paced vs. cron dispatch, what a run actually does, the push/merge review gates, how a `> ` reply round-trips, and an explicit "not built yet" section so it doesn't overclaim. Lives next to the tool (`cmd_explain` in `bin/scheduler`), not a file that goes stale.
- [ ] Every registered project's `/nightly-batch` actually consumes its own `QUESTIONS.md` replies via `collect-feedback.sh --consume` (audit opened 2026-07-22; vkv-inventory gap CONFIRMED 2026-07-24 via read-only check of its dedicated clone — see the matching Backlog entry below. Fix is outside this repo's scope (vkv-inventory's own `.claude/commands/nightly-batch.md`), routed to realisateur.)

Ideas beyond this bar are PARKED by default (see
realisateur/STABILITY-MILESTONES.md) — this is a **big reservoir named by
category, not itemized line-by-line** given this file's size: the merged
report+questions file / future TUI (item 0), the consolidation roadmap
(axes 1/3/4/5 — `bin/scheduler-run` migration, `.scheduler/`-subdir
rollout to remaining projects, no-local-checkout design, cloud hosting),
`AUTONOMY_TIER` + `REGISTRATION.md` formalization, `BLOCKERS.md`-as-
computed-view redesign, the active/parked/waiting status-vocabulary
unification (already routed to this backlog 2026-07-23), and every
Backlog-section idea (Google Calendar integration, glance-view formatting
polish, etc.). None of this is discarded — it stays visible below,
revisit once the checklist above is genuinely done. *(Milestone drafted
2026-07-24 via realisateur's `/ideate`, human-directed that pass; checkbox
states reconciled 2026-07-24 when `paced/2026-07-24` — a same-day branch
that had independently built 3 of these 4 items before this milestone text
was drafted — was merged into `main`.)*

**Push policy (changed 2026-07-18, human-approved; SUPERSEDED 2026-07-24 —
see below):** the nightly job MAY push its own commits directly to
`origin/main` — no `nightly/<date>` branch, no human merge step required.
Review is *revert-based*, not a pre-push gate: every push MUST be flagged
prominently in that night's report (what was pushed, why, and how to
revert it — e.g. `git revert <sha>`) so the human can review it after the
fact, not before.

**2026-07-24 update, human-directed — the "prefer the old review-gate
branch behavior... until safety work lands" caveat above is RETRACTED,
not just superseded quietly:** it was read (by this file's own earlier
`bin/scheduler-dev-cycle.sh` — see Merge policy below) as license to merge
into local `main` but hold the push back for a once-daily human review.
That turned out to be a real bug, not extra caution: multi-host self-dev
(mandark + dexter, see "Multi-machine parallelism" section below) hit a
live divergence from exactly this — one host's cycle merged locally,
didn't push, the other host's cycle pulled a stale `origin/main`, merged
its own work on top of the old base, and now two hosts had different
unpushed history built on the same stale point. Holding the push back
bought zero review benefit (review already happens after the fact, via
revert, same as any other push this repo makes per CLAUDE.md) while
adding real staleness risk. **Corrected policy: every self-dev cycle
that merges into local `main` pushes to `origin/main` in the SAME
cycle, immediately — no accumulate-and-review-once-a-day, single host or
multi-host, no exception.** File this broadly so it isn't
re-litigated: also documented in `bin/scheduler-dev-cycle.sh`'s own
header/comments (the actual enforcement point) and DESIGN-NOTES.md
2026-07-24 "push-on-cycle, not push-on-morning-review" (full rationale +
the divergence incident that triggered it).

**Merge policy (changed 2026-07-19, human-directed; push behavior
corrected 2026-07-24, see immediately above):** `bin/scheduler-dev-cycle.sh`
merges each finished paced cycle's commits from `paced/<date>` into
*local* `main` right after the cycle (`git merge --no-ff`), **then pushes
that merge to `origin/main` in the same cycle** (changed 2026-07-24 —
this used to stop at the local merge and hold the push for a human;
that's the retracted behavior above). Review still happens — just after
the fact (`git show <merge-sha>`, revert with `git revert -m 1
<merge-sha>`) instead of before. This is a **toggleable flag**, not a
rewrite of the safety model: `~/.local/share/scheduler-paced-dev/merge_mode`
holds `merge` (default) or `branch` (manual pause — commits stay on the
branch, a human merges+pushes by hand; an intentional opt-out for a
specific risky stretch, not "the safer everyday choice" — don't read its
existence as still-recommended caution). The cycle also self-guards: if
`main` isn't clean and checked out in the scheduler repo when a cycle
finishes (e.g. another session has an in-progress edit, as has happened
with `crt.conf`), it automatically falls back to leaving commits
unmerged rather than merging into a dirty tree; and re-fetches +
`--ff-only`s onto `origin/main` immediately before merging (best-effort
freshness, not a guarantee) and retries a rejected push once after
reconciling, logging CRITICAL + `notify-send -u critical` if it still
can't push rather than silently leaving local `main` ahead of origin.

## Architecture: cron, not a daemon (reaffirmed 2026-07-20)

Revisited explicitly this session — the original "no daemon" call in
`DESIGN-NOTES.md` named its own trigger condition: *"would pay off once
there are enough projects that per-project cron-entry sprawl itself is
the bottleneck — not yet, at 2 projects."* Now at 11. Re-examined with
real pros/cons (not just re-asserted):

- **What actually pulled toward a daemon this time** wasn't project count
  — it was two ideas raised in the same session (bottleneck-aware
  cross-workstream scheduling above, and "nudge a project to run sooner
  after answering a blocker," explicitly rejected earlier in this file).
  Both want live state a daemon is naturally good at.
- **But the specific trigger from the original decision — cron-entry
  sprawl — is already solved without a daemon**, by `schedule/*.conf` +
  `sync-crontab.sh` + the paced governor. Project count alone isn't the
  signal.
- **Decision: keep cron.** Both daemon-shaped wants above are cheaper to
  approximate with data (a future `DEPENDS_ON` conf field, a precheck)
  than with a new always-on process that needs its own crash/supervision
  story — real rewrite cost against unproven need.
- **The real revisit trigger, named explicitly so it isn't re-litigated
  from scratch next time:** if `bin/usage-paced-runner.sh` itself grows
  complex/stateful enough that re-deriving everything from scratch every
  15 minutes becomes an OBSERVED bottleneck (not hypothetical) — that's
  the signal, not project count and not a feature wishlist.
- **Refined 2026-07-20: the daemon isn't rejected outright, it's PARKED
  for a specific future world — scheduler running on an always-on server
  instead of the laptop, not this laptop-bound cron setup.** That's
  exactly the world item 4/5 (no local checkout, scheduler owns scope,
  runnable anywhere) is already building toward — a daemon is the natural
  fusion of "scheduler can run anywhere" with "scheduler is always
  running," not a separate, unrelated leap. **Build-toward-it principle,
  effective now for any NEW mechanism this roadmap adds:** prefer state
  that lives in files/is fully re-derivable on each invocation over
  anything held only in one process's memory; prefer idempotent,
  poll-friendly checks over logic that assumes a specific cron cadence;
  keep dispatch logic (what runs next, and why) separable from HOW it
  gets triggered (a cron tick today, an event loop later) so swapping the
  trigger mechanism later is small, not a rewrite. Every item in this
  roadmap (`AUTONOMY_TIER`, the registration contract, the blockers
  aggregation above) should already read this way by construction — this
  bullet is the explicit check to apply when reviewing new design work,
  not a new item to build separately.

## Vision (2026-07-20, human-directed session)

**Scheduler runs a fleet of autonomous builders, not just a fleet of
maintained projects — and safety comes from a per-project autonomy dial
matched to that project's actual stakes, not one global trust ceiling.**
A hobby vim-game and a home-assistant install with physical devices should
never share one policy. Self-spawning (realisateur scaffolding new
projects unprompted) is core to the value this system is for, not a risk
to contain — the job is to make that pattern safe *by construction*
(sandboxed remotes, cost caps, the tier below), not to rein it in after
the fact.

**`AUTONOMY_TIER` — the dial, one field per project, not yet built:**
- **`low`** — branch-only commits; a human merges by hand; never deploys.
  (Matches vkv-inventory/wtul's current default posture — this becomes
  their explicit tier once the field exists, not a behavior change.)
- **`medium`** — may push directly to `main` (flagged + revertible in the
  report), but merging larger multi-branch work and deploying stay human.
  (Matches scheduler's own current push policy above, and chezz's
  autopilot-with-irreversibility-gate.)
- **`high`** — push, merge, AND deploy autonomously when the deploy target
  is confirmed revertible (a stable dev-deployment id, not a hard
  production cutover). (Matches scheduler's own merge-policy note above,
  and vkv-inventory's own standing direction to push/deploy when
  revertible.)

This is a **formalization of policy that already exists, scattered**
across this file's push/merge notes, chezz's FOCUS.md, and vkv-inventory's
QUESTIONS.md answers — not new behavior being invented. The point of
building it is to make the tier an engine-enforced field
`schedule/<project>.conf` sets and `lib/sweep-loop-common.sh`/
`scheduler-run` actually reads, instead of policy living only in each
project's prose (which a run can misremember or a new project can lack
entirely).

**One rule sits ABOVE the tier system, at every level, always:**
genuinely irreversible actions — a NEW paid external service dependency, a
physical device actuation, a non-revertible production cutover — always
need explicit human sign-off, no matter the tier. The dial governs
*revertible* autonomy (push/merge/deploy that can be undone with a `git
revert` or a redeploy); irreversibility is a separate, universal gate that
transcends tier, same principle chezz's FOCUS.md already uses.

**Newly self-spawned projects (the realisateur pattern) get no special
starting tier** — a spawned project's own `schedule/<project>.conf` claims
whatever `AUTONOMY_TIER` its own scaffolding session set, same as a
hand-registered project. Trust the scaffolding process, don't
double-gate it. (The existing convention of spawned projects using a
local bare git remote instead of GitHub — crt/realisateur/groc-mangr's
precedent — already provides real containment underneath this regardless
of tier: no credentials to leak, nothing reaches the outside world.)

**Roadmap implication:** `AUTONOMY_TIER` becomes Phase 1.5 — natural to
build alongside axis 1 (registration migration) below, since that work is
already touching every project's `schedule/<project>.conf` one at a time;
adding the tier field in the same pass avoids a second full sweep across
every conf later. Not designed further than the tier definitions above
yet — the engine-enforcement mechanics (how `lib/sweep-loop-common.sh`
and each project's `/nightly-batch` command decide whether to merge/
deploy based on the tier) are real design work for a future session or
unattended cycle, not done in this one.

### Registration — the Claude-native contract (2026-07-20, human-directed)

Registration (a project joining this fleet at all) is autonomy tier zero:
the one-time decision to commit real recurring cron/quota to a project,
forever, until someone notices and deregisters it. Today it's implicit —
`examples/schedule-entry.conf.template` + prose comments an agent has to
read and interpret correctly with no human proofreading it, and no schema
version, so drift is silent (already happened once this session:
`_paced.conf`/`_runner.conf` broke `build-services-view.sh`'s glob before
anyone noticed; `SCHEDULER_SUBDIR`'s own meaning just changed under us).
**Decided shape, matching the "lean into autonomy" vision above — light
gates, not heavy ones:**

- **Self-registration auto-applies, same as any other conf edit.** A
  realisateur-style agent writing `schedule/<project>.conf` directly and
  running `--apply` stays exactly as trusted as it is today — flagged in
  the next report for awareness, not held for approval. Consistent with
  "self-spawning is the point, don't double-gate it" above.
- **`REGISTRATION.md`** — a new top-level contract doc, same spirit as
  `INTAKE.md`: the complete field schema (required vs optional,
  `AUTONOMY_TIER` values, what `SCHEDULER_SUBDIR` must point at, etc.) —
  written once, versioned, so an agent has one authoritative source
  instead of reverse-engineering the shape from an existing project's
  conf or scattered README/DESIGN-NOTES prose.
- **`SCHEDULER_CONF_VERSION=N`** — a required field in every
  `schedule/<project>.conf`, declaring which schema version (as defined in
  `REGISTRATION.md`) that conf was written against. **Soft validation**:
  `sync-crontab.sh` checks it and prints a clear warning (also surfaced in
  `morning-report.sh`) on a missing/unknown version or a field that fails
  schema checks — it does **not** block or refuse to apply. Matches this
  repo's existing philosophy (colliding Tier 2 batch times already warn,
  don't block) — an unattended run should never grind to a halt over a
  schema nit. This is the forward-compat mechanism: old confs keep working
  under their declared version's rules as the schema evolves, making the
  existing `*_SCRIPT` back-compat pattern explicit and general instead of
  a one-off.
- **`bin/scheduler-register`** — a single new entrypoint wrapping
  copy-template → fill → validate (prints warnings, doesn't block) →
  preview → apply as one discoverable, scriptable command, matching
  `sync-crontab.sh`'s existing preview-by-default/`--apply` shape, instead
  of a multi-step doc-following process spread across several tool calls.

**Build order (this is prerequisite work, sequenced BEFORE axis 1's
per-project sweep below):** `REGISTRATION.md` + schema v1 + the soft
validator + `bin/scheduler-register` need to exist first (schema v1 has
to be defined before any conf can meaningfully declare
`SCHEDULER_CONF_VERSION=1` against it). Once that lands, axis 1's
per-project pass (already touching every conf for the `*_SCRIPT`
migration, already adding `AUTONOMY_TIER` per item 1.5) picks up
`SCHEDULER_CONF_VERSION=1` in the same sweep — three related fields, one
pass per project, not three.

## This project dogfoods its own system

The scheduler uses the exact pieces every registered project uses, no
bespoke ones:

- **Its files live in `.scheduler/`** (this folder — moved 2026-07-20 from
  `.claude/scheduler/`; see "Permission gate" below for why it's
  deliberately OUTSIDE `.claude/` now, not just a naming choice): `FOCUS.md`,
  `QUESTIONS.md`, `schedule.conf`. Registration symlinks them into
  scheduler's aggregation folders (`focus/`, `questions/`, `schedule/`) —
  `schedule/scheduler.conf` is already a symlink back to
  `.scheduler/schedule.conf`.
- **Reports** go to `~/reports/scheduler/` like everyone else.
- **The backlog lives HERE, in this file** (the section below) — not in a
  separate `TODO.md` anymore (retired 2026-07-18). The scheduler has no
  tracker and no end users filing reports, so FOCUS.md is both scope *and*
  backlog. Introduce an idea by adding a line to the Backlog section; that's
  the whole intake mechanism.
- **Questions** (`.scheduler/QUESTIONS.md`) for anything needing a
  human decision — appended, never acted on unilaterally.

## Cost insight (2026-07-18 usage audit — read before touching model/effort settings)

> **2026-07-24 amendment (post-Max):** the primary account is now Claude
> Max (5x), always logged in; svc-vaporwave is nonprofit-only. Under a
> subscription the lever is **weekly quota-tokens, not dollars** — but the
> conclusions below still hold, because Opus burns *quota* ~5x faster than
> Sonnet just as it burned dollars. Read "$" below as "quota." See
> DESIGN-NOTES.md 2026-07-24 for the full account-model decision.


Audited real token usage across `~/.claude/projects/*.jsonl` since 2026-07-17.
Findings, so this doesn't get re-litigated or blamed on the wrong thing:

- **The bug sweeper is cheap** (~$72 of ~$1245 total, ~6%). It was suspected
  as the usage drain and it is not — don't spend effort "fixing" it on that
  theory.
- **Interactive human chats are ~73% of spend** (~$907), automation
  (nightly-batch + bug-sweep + scheduler self-runs combined) is ~27% (~$339).
- **The real per-token cost lever is model choice, not reasoning effort.**
  Opus is ~5x Sonnet's price per token (both input and output/thinking).
  Effort level only trims how many tokens Opus emits per turn — "Opus on
  low effort" for routine work still pays the full Opus per-token premium
  for a lower-quality answer. Human default model has been switched to
  Sonnet 5 (2026-07-18) for exactly this reason.
- **Scheduler's own self-runs and the nightly batches are a real, separate
  cost center worth slimming** — 07-18 alone saw automation jump to ~$284
  in one day (scheduler self-run ~$134, vkv-inventory-nightly ~$73,
  chezz-nightly ~$28). Action item: scheduler should look at what model/
  effort each `*_TIER*_MODEL` in `schedule/*.conf` is actually set to, and
  whether nightly/batch tiers that don't need Opus-grade reasoning (routine
  sweeps, mechanical migrations) can run on Sonnet instead. This is a
  concrete, cheap win — fold it into the "Optimal-usage scheduling" backlog
  item below rather than treating it as a new one-off.

## Short list + roadmap (2026-07-24, /ideate pass #3 — derived from a longer
vision list the same pass; see DESIGN-NOTES.md for the full writeup)

**Blockers to clear before batch work resumes (only 2 of the original 8
long-list items actually gated anything — the rest are real but don't
block scheduler/realisateur's own weight-3 work, since neither touches
svc-vaporwave):**
1. Zach grants himself broader access to `svc-vaporwave`'s home
   directory — **DONE 2026-07-24** (`chmod 777`).
2. Correct the stale "migrated"/"confirmed working" claims about
   aedile/vkv-inventory's svc-vaporwave crontab — **DONE this pass**
   (BLOCKERS.md's aedile section, `_paced.conf`'s aedile/vkv-inventory
   comments, and the local `NEXT-STEPS.md` handoff note itself).
3. **DONE 2026-07-24, added mid-pass:** svc-vaporwave's crontab was
   never actually installed (confirmed via full-retention `syslog`
   check — no REPLACE/EDIT event ever, only LIST). Installed for real
   this session: `0 3 * * * .../aedile-nightly-batch-loop.sh` and
   `0 4 * * * .../vkv-inventory-nightly-batch-loop.sh`, confirmed via
   `crontab -l`. Worth a follow-up check in a day or two that the first
   real cron-driven cycle (not today's manual verification) actually
   ran clean.
4. **RETRACTED, not actually needed:** chezz/wtul already have working,
   write-verified GitHub deploy keys (`github-chezz-deploy`/
   `github-wtul-deploy` in `~/.ssh/config`) — the "credential gap"
   diagnosis was wrong, caught and corrected same pass (zach: "don't
   they have deploy?"). See DESIGN-NOTES.md 2026-07-24 for the
   correction and what actually explains any stranded commits instead
   (the already-documented spend-limit-cutoff pattern, not credentials).

**Short list is now fully clear** — all 4 items resolved (1 done by
zach, 2 corrected docs, 1 installed crontab, 1 retracted as a
non-problem).

**Roadmap — batch work under fresh Max quota + the priority buildout:**
1. Let scheduler + realisateur (weight-3) run under the newly-`RUN`
   quota reading — watch `run.log` to confirm they actually dispatch,
   not just eligible. Passive, no action needed unless it doesn't
   happen.
2. Realisateur's next cycle processes two inbox items: the pruner-
   ownership decision (pass #2) and the aedile/vkv-inventory
   finish-vs-pull-back judgment call (pass #3).
3. Once realisateur answers #2, execute whichever path it judges —
   still a human action either way (crontab install, or re-enabling the
   `_paced.conf` lines here).
4. Weight-3 is explicitly time-boxed (see `_paced.conf` bootstrap
   comment) — drop scheduler + realisateur back to weight 1 once
   realisateur's stability-milestone + default-park convention lands.
5. The hardening-vs-consolidation resequencing question (does abundant
   quota change the "hardening first" priority below?) stays parked —
   not urgent enough to gate 1-4, revisit after they settle.

## Current focus

*(This section is where the `## Stability milestone` above was drafted
FROM, 2026-07-24 — the four checklist items there are items 1-2 below,
formalized into a checkable bar. Keep them in sync: if this section's
priority order changes, update the milestone checklist to match, don't
let the two drift into two different stories about what's active.)*

**SEQUENCING (re-decided AGAIN 2026-07-20, human-directed, later the same
day — item 0 is PARKED, not top priority, reversing the ordering above
from earlier today.** Reasoning, stated directly by the user and worth
keeping verbatim in spirit: *"my ideas outpace implementation of stable
versions so the target is always moving"* — a named, recurring pattern
(see "vision debt," folded into chezz's own `.claude/commands/
ideate.md` same session), not unique to item 0. Chasing the single-file
merge now would be doing the exact thing that pattern warns against:
letting a good-but-bigger idea displace finishing the version already in
flight. **Item 0 stays fully designed (nothing below is deleted or
devalued) but is explicitly NOT the thing to build next.**

**Actual current priority: hardened, well-understood stability of the
system AS IT EXISTS TODAY (the three-plus-one-file shape: `FOCUS.md`,
`QUESTIONS.md`, reports, `BLOCKERS.md`) — so scheduled jobs and
interactions don't break, and so the user can actually explain the
system to themselves, not just operate it by trusting `bin/scheduler` to
smooth over the parts they don't yet follow.** Concretely, in order:
1. Keep closing the real bugs this system already surfaced when
   exercised for real this session (the `> ` indentation-matching bug,
   the untracked-file commit bug, the slow-hook-on-docs-commit waste —
   all fixed same session, this IS what "hardening" looks like in
   practice, not an abstract goal).
   - **DONE 2026-07-24 paced cycle: stale `.active`-marker / stranded-run
     detection.** `cmd_sweep` in `bin/scheduler` now scans
     `~/.local/share/scheduler-registry/*.active` as a third pass (after
     the working-checkout pass and the dedicated-clone pass) and flags
     any marker whose recorded PID is no longer alive as STALE — that
     run's own `trap ... EXIT` (in `lib/sweep-loop-common.sh`) never got
     to fire, meaning it was killed/crashed/rebooted, most likely before
     making any commit at all, which is exactly the case the git-based
     dedicated-clone check can't see. A live PID still gets a softer flag
     if it's been running past `STALE_ACTIVE_MARKER_SECONDS` (default
     7200s), for a hang rather than a crash. Verified with fabricated
     dead-PID and live-PID markers (correct STALE vs. silent output) and
     `bash -n bin/scheduler`.
   - **DONE 2026-07-24 paced cycle: migration-destination verification.**
     The same "verify a claimed migration destination, don't just assume
     it" shape found for real 2026-07-24 (see DESIGN-NOTES.md
     "silently-orphaned finding") — `_paced.conf` disabled aedile and
     vkv-inventory on the unverified assumption their migration to
     svc-vaporwave's crontab had completed, it hadn't, and both sat with
     zero dispatch for 4 days undetected. `cmd_sweep` now has a fourth
     pass: it scans every `schedule/*.conf` for a `MIGRATED to <host>`
     comment and re-verifies it every sweep (SSH-unreachable → UNVERIFIED,
     reachable-but-absent → ORPHANED, reachable-and-present → verified),
     the same flag-drift treatment the stale `.active`-marker pass already
     gets. Verified live against the real aedile/vkv-inventory case —
     `svc-vaporwave` correctly comes back UNVERIFIED, fails fast (~0.05s),
     no hang. Scheduler's job here is only the mechanism check; what to DO
     about a confirmed-orphaned participant (finish the migration vs. pull
     it back) stays realisateur's call, queued to its inbox separately —
     unchanged by this.
   - **DONE 2026-07-24 paced cycle: stale/incomplete-push visibility
     (says WHY, not just THAT).** `lib/sweep-loop-common.sh`'s
     `WARNING: local commit made but NOT pushed` case now emits a
     `push reason:` line: claude's own run failed (STATUS=FAILED, likely
     a turn/spend cutoff before a push step); `origin/$BRANCH` was
     unreachable at all (SSH/auth/network failure); a read-only
     `git push --dry-run` says the push would succeed right now (claude
     just never ran `git push` this cycle); or remote has diverged
     (needs merge/rebase, not a credential issue). `bin/scheduler`'s
     status view surfaces the new line too. See the matching Stability
     milestone checklist item above for full verification detail — kept
     in sync here per this section's own header note.
   - **PARKED (human-directed 2026-07-20), explicitly NOT a live risk:**
     the `LATEST.md`-symlink fix from earlier today. Verified directly
     against `lib/sweep-loop-common.sh`: `collect-feedback.sh` reads
     `LATEST.md` BEFORE `claude -p` is invoked, and the overwrite only
     happens as the last thing that same run does — so a reply left via
     `scheduler -r <project>` is always read before any overwrite,
     symlink or not. The bug's real remaining cost is narrower than
     "replies get lost": the permanent dated-file historical record
     won't reflect a reply left only in `LATEST.md`. A documentation/
     audit-trail gap, not an operational one — fine to leave queued
     behind higher-value work, not urgent.
     - **UNPARKED 2026-07-28 (paced cycle): it stopped being hypothetical
       and destroyed a report.** This cycle ran `cp <today>.md LATEST.md`
       to refresh the pointer. `LATEST.md` was a symlink to
       `2026-07-27-paced.md`, so `cp` **followed it** and wrote today's
       report over yesterday's. `~/reports/` is not a git repo and has no
       backup, so the tail of that file is permanently gone; the head was
       reconstructed from session context and the file now carries a
       reconstruction banner saying exactly what was lost. Nothing
       operational broke (the commits are the durable record) — but the
       cost analysis above, "a documentation/audit-trail gap," was right
       about the category and wrong about the size: the failure mode is
       not "a reply is missing from the archive," it is **silent
       destruction of an arbitrary past report by an ordinary write to
       `LATEST.md`.**
       The fix is one line and belongs to whoever writes the pointer, not
       to the reader: **never `cp` onto `LATEST.md`** — write the dated
       file, then `ln -sfn <dated> LATEST.md.tmp && mv -T LATEST.md.tmp
       LATEST.md` (atomic, and can't be followed). Better, per this
       repo's own "generate, don't type" rule: this is a convention an
       author has to remember, i.e. a latent bug, so the durable version
       is a tiny `bin/publish-report.sh <project> <file>` that both
       `/nightly-batch` and `lib/sweep-loop-common.sh` call.
     - **BUILT 2026-07-28 (later paced cycle): `bin/publish-report.sh`.**
       `publish-report.sh <project> <dated-file> [--from <src>|-]` writes
       the dated file (never through a symlink) and re-points LATEST.md
       atomically (`ln -sfn` to a temp name + `mv -T`), so LATEST.md is
       always a symlink and no write can follow the old pointer into a
       past report. A pre-existing REGULAR-file LATEST.md — still the
       live shape for chezz, home-assistant, wtul, vkv-inventory,
       groc-mangr, nine-speakers, sequestria, gardien as of today — is
       never deleted blindly: differing content is preserved as
       `LATEST.md.orphaned-<utc-stamp>` and said out loud. **Wired** into
       the prompts generated by `bin/scheduler-dev-cycle.sh` and
       `bin/overnight-dev.sh` (both now tell the run to call it and name
       the `cp` failure), and used by this cycle's own report — the
       human-sense witness. Verified against a throwaway
       `SCHEDULER_REPORTS_ROOT`: the original `cp`-follows-symlink
       destruction reproduced first (yesterday's file really did end up
       containing today's text), then the script's repoint left it
       intact; plus `--from -`, the legacy-regular-file preservation
       path, and five refusals (LATEST.md as target, missing target,
       unknown project, `../` escape, path outside the report dir).
       **Still open, needs an interactive session:** `/nightly-batch`'s
       own instruction lives under `.claude/`, which unattended runs are
       hard-refused on writing, and `lib/sweep-loop-common.sh` does not
       write LATEST.md at all today (the run's agent does) — so a
       per-project run following its own `.claude/commands/nightly-batch.md`
       still gets no guard. That copy is where this fix has to land next.
2. **DONE 2026-07-24 paced cycle: `scheduler explain` (`-e`).** Prints a
   plain-English "here's what happens when you do X" walkthrough covering
   paced vs. cron dispatch, what a run actually does (fresh clone, reads
   scope from the checkout not the symlink), the push/merge review gates
   (per-project, not one global rule), how a `> ` reply round-trips via
   `collect-feedback.sh --consume`, and what `scheduler` itself does vs.
   doesn't do — plus an explicit "not built yet" section (AUTONOMY_TIER,
   merged report file, scheduler-owned scope) so it doesn't overclaim
   design work as shipped. Lives next to the tool (`bin/scheduler`,
   `cmd_explain`), not a file that goes stale. Verified: `bash -n
   bin/scheduler` clean, ran `scheduler explain` and `scheduler -e` and
   read the output end to end for accuracy against the actual scripts
   (`bin/scheduler-run`, `lib/sweep-loop-common.sh`, `bin/usage-gate.sh`).
3. Only after 1-2 are genuinely solid: revisit item 0, the consolidation
   roadmap axes below, and any other bigger redesign — same "vision
   debt" discipline applied to this file's own backlog, not just to
   individual project ideate sessions.

**Any new/big idea from here forward gets a durable, findable parking
spot (this file, or the relevant project's own FOCUS.md/QUESTIONS.md) —
never just left in chat.** That's the concrete fix for "make sure we
will for sure get to them," per the user's own framing — not a promise
to build sooner.

0. **PARKED 2026-07-20 (see "SEQUENCING" note above — not top priority,
   fully designed, deliberately not being built next).** Collapse report
   + questions into one file I actually read. Today I
   have to open a report AND separately edit `QUESTIONS.md` to answer
   things — too many files, and the answer workflow is disconnected from
   where I actually see the question. Preferred workflow (may partially be
   superseded by the TUI in item 3 below, but worth building now — could be
   good enough on its own even once the TUI lands):
   - The **morning report and the open questions/decisions live in a single
     markdown file**, one per project, owned by scheduler.
   - I open that one file, read what happened + what's pending, and **write
     my answers inline right there** (e.g. under each question, same `> `
     convention as today's QUESTIONS.md).
   - That file is what's symlinked into each project today (or, once a
     project has no local checkout per item 4's design, copied into the
     ephemeral clone before `claude` runs) — so the next night's job reads
     my inline answers straight out of it, same round-trip QUESTIONS.md
     already does, just merged with the report instead of a separate file.
   - Concretely: look at whether `focus/<project>.md` (scope),
     `questions/<project>.md`, and `~/reports/<project>/...` can become one
     `report/<project>.md`-shaped file per project — newest report on top or
     appended, open questions inline, my `> ` replies picked up and cleared
     next run. Don't lose the history reports currently have; append rather
     than overwrite.
   - Do this incrementally and verifiably like everything else in this file
     — pick one project (scheduler itself is the safest first mover, as in
     item 4) to prototype the merged-file shape before touching others.

   **Target UX (2026-07-20, human-directed session) — what `scheduler` with
   no args should print once this + the tier/registration work land.** Not
   built yet — a concrete screen to build TOWARD, not a description of
   current behavior (today's `scheduler` reads three separate
   `focus/`/`questions/`/`LATEST.md` sources per project, and no conf has
   an `AUTONOMY_TIER` yet):

   ```
   $ scheduler
   scheduler — 11 projects · 3 need you · last checked 2m ago

     PROJECT          TIER    NEXT            STATUS
     chezz            medium  paced (#2/9)    clean
     vkv-inventory    medium  paced (#4/9)    tracker down (403) — needs you
     home-assistant   low     paced (#5/9)    2 questions open
     wtul             low     Wed 03:14       clean
     crt              medium  paced (#7/9)    deploy pending
     scheduler        high    03:00 daily     clean
     realisateur      high    paced (#9/9)    1 question
     groc-mangr       high    paced (#1/9)    new — unaudited
     nine-speakers    high    paced (#3/9)    new — unaudited
     sequestria       high    paced (#6/9)    new — unaudited
     vim-arcade       high    paced (#8/9)    new — unaudited

     branches awaiting review:
       vkv-inventory   nightly/2026-07-19  4 commits, not merged
       scheduler       paced/2026-07-20    merged locally, not pushed

     run `scheduler <project>` to open its report + reply to questions inline
     run `scheduler blockers` for cross-project human-owned items
   ```

   `scheduler <project>` opens that ONE project's merged `report/<project>.md`
   in `$EDITOR` — last run's narrative on top, open questions inline with
   `> ` reply slots right where the context is, older reports below. Reply
   inline, save, quit; next run reads it first, acts, clears the block —
   same round-trip `QUESTIONS.md` does today, one file instead of two.

   What each already-decided roadmap piece buys in that screen, concretely:
   - `AUTONOMY_TIER` (item 1.5) → the `TIER` column.
   - Registration contract (axis 0) → the `new — unaudited` marker, driven
     by a real field instead of memory of which projects realisateur spawned.
   - Sweep pacing (axis 2) → `NEXT` reads as one consistent shape (paced
     position or cron time), not two different mental models per project.
   - Layout consolidation (axis 3) → the merged report files all live in
     one predictable place per project, no `.claude/` permission surprises.
   - Branch-awareness (standing direction, 2026-07-19) → the "branches
     awaiting review" block.

   **Refined target shape (2026-07-20, human-directed, later the same
   day) — the merged per-project file should read as a STABLE, PRINTABLE
   document, not just "less files to open."** Concretely: "I'd send a job
   to my 2D printer, read this at my desk" — the file should be clean
   enough as plain markdown/text that printing it produces something
   genuinely readable away from a screen, with inline questions and short
   reply "hooks" (a one-liner you can type back later, not necessarily a
   live edit-in-place) rather than requiring an editor open. This
   reframes the earlier "one file per project" goal: it's not just about
   file COUNT, it's about the file being a stable enough artifact to
   leave your desk with. Two intake modes should both funnel into the
   SAME underlying questions/blockers store (never a second place that
   drifts): (a) the fast inline-vim-edit habit already built (keep
   improving it — it's the default, low-friction path), and (b) a
   slower, thorough, print-and-return path for when a report deserves
   real attention away from the keyboard. Not designed further than this
   framing yet — real work: what the "reply hook" syntax looks like
   (an ID you can text/type back? a `scheduler answer <project> <id>
   "..."` command?), and an actual `lp`/`lpr`-backed `scheduler print
   <project>` command. Genuinely new scope, not yet broken into
   buildable pieces.

   **Design principle for the space between the two intake modes
   (2026-07-20): discourage the informal path by making the proper one
   MORE useful, never by restricting the informal one.** Concretely
   decided this session, in response to `RFP-GALLERY.md` sitting
   uncommitted with no safety net: the auto-commit hook's SAFETY NET was
   broadened to cover ad hoc project-doc edits too (see
   `docs/feedback-tags.md`'s "Auto-commit on save" section) — the fast
   habit stays fully supported, nothing about it got harder. The actual
   discouragement should come entirely from the proper single-inbox path
   (once item 0 above exists) being clearly the better place to put a
   real question or blocker — faster to open, guaranteed to be read by
   the next run, printable — not from making ad hoc doc edits riskier or
   less convenient. If ad hoc editing stays genuinely more convenient
   than the proper inbox once it exists, that's a sign the proper inbox
   isn't good enough yet, not a reason to restrict the ad hoc path.

   **Confirmed later the same day: questions and blockers have no real
   remaining DATA distinction, only a presentational one.** Both are "a
   human needs to reply inline, an agent reads it and acts" — the only
   actual difference is per-project view (`QUESTIONS.md`) vs.
   cross-project aggregated view (`BLOCKERS.md`). This is exactly why the
   design below already treats blockers as a computed VIEW over the same
   underlying files rather than separate storage — that instinct was
   right the first time; today's conversation just confirmed it directly
   instead of leaving it implicit. Practical upshot: don't design
   `QUESTIONS.md`-shaped and `BLOCKERS.md`-shaped features as if they're
   answering different kinds of questions — they're the same list,
   filtered two different ways.

   **How `blockers` actually works, target design (2026-07-20,
   human-directed session):**
   - **`BLOCKERS.md` as a separate hand/agent-maintained file is
     RETIRED, target state.** Today it's a real duplication risk — content
     gets manually copied from a project's own `FOCUS.md` into it (see
     crt's hardware items, moved by hand 2026-07-20), the exact
     drift-prone pattern `INTAKE.md` already rejected for the feature
     backlog ("a second place the same information could drift out of
     sync"). `scheduler blockers` becomes a **live aggregated view**: it
     scans every project's own merged `report/<project>.md` (item 0, once
     scheduler-owns-scope-as-master per item 4/5 below has landed) for a
     `## Blockers`/needs-human-flagged section and assembles the
     cross-project screen by reading, not by a separately maintained copy.
   - **Explicit dependency: this needs item 4/5 (scheduler owns each
     project's scope file as the master copy) to land FIRST.** Until then,
     there's no single file scheduler can both read live AND consider
     authoritative to write your reply into — so `BLOCKERS.md` keeps
     working exactly as it does today as the bridge, not replaced
     prematurely. Sequence: item 4/5 → item 0 (merged report+questions
     file per project) → THEN blockers becomes a view over those merged
     files, `BLOCKERS.md` retired.
   - **Timing: your inline reply takes effect on that project's NEXT
     scheduled dispatch, same as every other inline-answer flow
     (`QUESTIONS.md`, report feedback) — deliberately no "nudge a project
     to run sooner right now" mechanism.** Considered and explicitly
     rejected for now: adding real design/build work (rotation-priority
     bump, or an ad hoc immediate run) to close an "I answered, why
     hasn't it happened yet" gap that's rare enough to handle manually
     (you can always run that project's wrapper by hand if something is
     truly urgent). Revisit only if this actually becomes a recurring
     complaint once the aggregated view is live.
   - Once aggregated, "propagates right away" means: your edit lands
     directly in the one true (scheduler-owned) copy the instant you save
     it — no separate consume/sync step, no drift risk. It does NOT mean
     the owning project's agent acts on it instantly; that still only
     happens at its next paced/cron dispatch, same as today.

   **Concrete mechanics for `bin/scheduler blockers` (2026-07-20, refined
   human-directed session) — a real script under `bin/`, not just a
   concept:**
   - **Scrape, don't rely on a push.** Every invocation walks every
     registered project's own scheduler-owned scope file (once item 4/5
     lands) fresh, looking for its blocker-flagged section. No cached
     state between runs of the command itself.
   - **Report what's silent, not just what's flagged.** A project with
     nothing under its blockers section is ambiguous — "confirmed nothing
     blocking" and "this project's report pipeline is stale/broken and
     never got a chance to say so" look identical unless the command
     distinguishes them. Cross-reference against that project's last
     report timestamp (or paced-rotation last-ran marker): a project that
     hasn't reported in an abnormal window gets its own "not reporting —
     check it" line, separate from and never confused with an empty
     blockers section.
   - **Spawns a synthesized buffer, not a symlinked file.** Since this is
     an aggregate over N different projects' own files, `scheduler
     blockers` writes a temp file assembling every project's section
     (clearly delimited, same visual shape as today's `BLOCKERS.md`
     headings) and opens THAT in `$EDITOR`. **On save, a wrapper
     (`BufWritePost` autocmd calling back into a `bin/scheduler` dispatch
     subcommand, or a post-edit diff step run right after `$EDITOR`
     exits — implementation detail to work out, not decided here) parses
     which section(s) changed and writes each change back into that
     project's own real scheduler-owned file, not the temp buffer.** This
     is real, non-trivial plumbing (multi-file back-propagation from one
     synthesized buffer) — flagged here as a concrete build requirement,
     not solved by this design pass.
   - **Redundancy: agents must not depend on back-propagation having
     worked.** Same principle already used everywhere else in this system
     (a run always re-reads its own `FOCUS.md`/report file fresh, never
     relies on being "notified" of a change) — every project's own
     `/nightly-batch` (and `/bug-sweep`) command must read its own
     scheduler-owned file's blockers section directly as a normal part of
     its run, regardless of whether `scheduler blockers`'s write-back
     mechanism is known to be working. If back-propagation has a bug and
     silently fails to reach the source file, the human's edit is still
     recoverable (it's sitting in the temp buffer / a backup), but the
     agent-side read must never be the ONLY path an edit can take effect
     through.
   - **Auto-clear policy — this is a discipline choice for you, but
     agents must not depend on you exercising it.** Explicit tags
     (`%%APPROVE` etc.) already exist and remain the clean, unambiguous
     signal when used — but the realistic expectation is you often won't
     bother typing one. **Agents MAY self-clear a blocker without an
     explicit tag, but ONLY when the resolution is objectively verifiable
     by the agent itself** — a specific commit exists, a test now passes,
     a state-check the agent can run directly confirms it — never for
     anything requiring real-world/physical confirmation only a human can
     give (most of what's actually in `BLOCKERS.md` today: hardware,
     measurements, physical installs). **Any self-clear, tagged or not,
     must be narrated explicitly in that run's report** ("cleared blocker
     X because Y, verified via Z") so it's visible and reversible if
     wrong — never a silent removal. This extends a pattern already used
     elsewhere in this system (e.g. chezz's nightly already resolves
     tracker reports itself when the fix is objectively done, not waiting
     for a human tag) to the blockers construct specifically.

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
   - **DONE 2026-07-24 paced cycle: `home-assistant` and `wtul` step-1
     fields copied.** `schedule/home-assistant.conf` gained `REPO_URL`,
     `REPO_SUBDIR`, `SECRETS_SRC_DIR` (reproduces the wrapper's pre-clone
     `.session-handoff/` copy-in — `lib/sweep-loop-common.sh` already
     supports this generically, so nothing wrapper-specific is lost),
     `BATCH_MAX_TURNS`, `BATCH_EXPIRY_DAYS`, `BATCH_ALLOWED_TOOLS`, and
     `BATCH_PROMPT`. `schedule/wtul.conf` gained `REPO_URL`, `REPO_SUBDIR`,
     `BATCH_MAX_TURNS`, `BATCH_EXPIRY_DAYS`, and `BATCH_PROMPT`. Both keep
     `BATCH_SCRIPT` set (still authoritative — no dispatch behavior
     changed). Verified: sourced each conf directly and diffed the loaded
     fields against the wrapper's own variables (byte-for-byte match,
     including the multi-line prompts); `bin/sync-crontab.sh` preview
     output diffed before/after (via `git stash`) and confirmed
     byte-identical. `chezz` was already done (2026-07-19); `vkv-inventory`
     deliberately skipped — its batch tier now runs entirely outside this
     scheduler under svc-vaporwave's own crontab (see its conf's own
     `MIGRATED to` comment), so migrating dead/inert fields here isn't
     verifiable against a real dispatch path and would just be unused
     scaffolding. Remaining: apply the same step-1 copy to `vkv-inventory`
     only if/when it's ever pulled back under this scheduler's control;
     until then this backlog item is otherwise clear.

2. **SUPERSEDED 2026-07-20 — see "Consolidation roadmap" → axis 3 below.**
   The target path changed: `SCHEDULER_SUBDIR=".scheduler"` (top-level,
   outside `.claude/`), not `.claude/scheduler/` as originally written here
   — the permission-gate investigation found `.claude/**` writes get
   hard-refused in unattended runs, so nesting under `.claude/` would have
   propagated the same bug to every project. Follow the roadmap section
   instead of this item.

3. **"scheduler" glance command (scoped 2026-07-19).** Goal: run `scheduler`
   in a terminal, see at a glance what's scheduled per project + whether it
   has open questions, then jump into a report and answer inline — vim
   native, not a custom UI.
   - **First cut BUILT 2026-07-20** (`~/.local/bin/scheduler`, NOT in this
     repo's git history, same as every other `~/.local/bin` wrapper): `scheduler`
     (glance -- project, open-question count from `questions/*.md`, open
     `BLOCKERS.md` item count per project), `scheduler -b`/`blockers`,
     `scheduler -f`/`focus [project]`, `scheduler -q`/`questions [project]`,
     `scheduler -r`/`report [project]` (opens `~/reports/<project>/LATEST.md`
     in `$EDITOR`). This is (b) below in spirit but skipped ahead of (a) --
     it reads today's separate `focus/`/`questions/`/`LATEST.md` files
     as-is rather than waiting on the merged-file design, so it's a real
     shortcut today, not a placeholder for the eventual merged file. Open
     question/blocker counts are a rough heuristic (bullet-line count minus
     lines matching "resolved"/"acknowledged", or bullets under a matching
     `## <project>` heading in `BLOCKERS.md`) -- not a real parser, will
     miscount on anything that doesn't follow the usual `- **` convention.
     Not yet showing next-dispatch timing (paced-rotation position / cron
     time) or `git log main..<branch>` awaiting-review counts -- still
     open, see (b)/(c) below.
   Sequencing (build item 0's merged file FIRST; the command is mostly a
   thin wrapper around it):
   a. **Prototype the merged `report/<project>.md` file on scheduler itself**
      (item 0 above) — newest run appended, `## Questions` section using the
      existing `> ` reply convention, next cycle reads its own prior answers
      back out of the same file. Don't lose history; append don't overwrite.
   b. **Add a `scheduler` subcommand** (`bin/scheduler-run scheduler` or a
      thin new `bin/scheduler` wrapper) that prints one screen: per project,
      next scheduled dispatch (paced-rotation position for paced
      participants, cron time for fixed ones) and an open-questions flag;
      and `scheduler open <project>` that just execs `$EDITOR` on that
      project's merged report file — no custom TUI framework, no parsing
      layer beyond what already reads `QUESTIONS.md` today.
   c. **Blocker "approve/clear" = `git log main..<branch>` + manual
      `git merge`/`git revert`**, same as the merge-policy note above — the
      glance screen can show "N commits on <branch> awaiting review" and
      shell out to `git log`/`git diff` on demand, but do not auto-merge
      from inside this command; that stays a human action (or the separate,
      already-toggleable `scheduler-dev-cycle.sh` merge policy for this
      project's own self-dev branch specifically).
      **The "N commits on <branch> awaiting review" half DONE 2026-07-25
      (paced cycle):** `cmd_glance`'s footer now surfaces this directly
      (new `extra_branches_detail` helper in `bin/scheduler`, reusing
      `extra_branches` — the bare-name list `cmd_sweep`'s third pass
      already built), same "don't make me run `sweep` separately"
      treatment already given to the stranded-local-commits footer line.
      Verified live against real state on this machine: correctly listed
      groc-mangr/vim-arcade/vkv-inventory/wtul's real unmerged branches
      with accurate ahead-counts, and correctly EXCLUDED chezz's
      `readable-html`/`chezz-classic` (confirmed via direct `git
      rev-list --count` — both are 0 commits ahead of `main`, i.e.
      already merged, so correctly not "awaiting" anything) — an early
      draft using the bare stripped branch name to compute the ahead
      count silently mis-scored any origin-only branch (no local
      tracking ref) as 0 regardless of its real state; fixed by
      resolving against the local ref if one exists, else `origin/<name>`,
      before re-verifying. No shell-out beyond read-only `git`; nothing
      auto-merged. Still just the read-only surfacing half of item (c) —
      the shell-out-to-`git log`/`diff`-on-demand interaction and (a)/(b)/(d)
      remain open.
      **Follow-up DONE, same paced cycle:** `cmd_sweep`'s own third pass
      (`branches beyond main`) still called the old bare-name
      `extra_branches()`, so `sweep`'s output and `glance`'s footer showed
      the same signal in two different shapes — `sweep` said "1 stray
      commit" and "23 commits, needs real review" identically (bare branch
      name only), forcing a manual `git rev-list --count` to tell them
      apart, exactly the gap the glance footer fix above just closed for
      the daily view. Switched `cmd_sweep`'s third pass to
      `extra_branches_detail` too, so both surfacings are consistent.
      Verified: `bash -n bin/scheduler` clean; ran `scheduler sweep` live
      and cross-checked its new ahead-counts against `git rev-list
      --count` per branch (groc-mangr 6, vim-arcade 1, wtul 1/1/3,
      vkv-inventory 19/19/19, this repo's own `paced/2026-07-25` 1 —
      matches `origin/main..paced/2026-07-25`, since the two earlier
      commits on this branch had already been merged+pushed to
      `origin/main` mid-cycle by `scheduler-dev-cycle.sh`); also ran under
      `env -u SSH_AUTH_SOCK GIT_SSH_COMMAND="ssh -o BatchMode=yes"`
      (simulating cron) — exit 0, output unchanged, no regression in the
      other five `sweep` passes.
   d. Migrate one project at a time after scheduler's own prototype is
      verified; old `LATEST.md`/`QUESTIONS.md` stay as fallback until each
      project's wrapper is confirmed reading the merged file correctly.
   Pick off (a) first, verify it round-trips a real inline reply before
   touching (b)-(d).

4. Lay the groundwork for a long term design which allows me to remove these github hosted projects from my system entirely. The code lives on github and only gets pulled if necessary to do work. If it's better to cache the downloaded repo somewhere, that's fine. The goal here is to clean up my working environment so me moving these projects around to different locations doesn't effect scheduler's ability to run their improvements.

   **Design direction (decided 2026-07-18 with the human — build toward this, don't
   land it in one run).** The blocker is that today's `focus/`+`questions/`
   symlinks point *out of scheduler into each project's local working copy*
   (`focus/chezz.md -> /…/chezz/.claude/FOCUS.md`). Delete that checkout and
   the symlink dangles — so "no local checkout" and "symlink into the
   checkout" are fundamentally incompatible. The batch already does NOT read
   through the symlink anyway: it clones `origin/main` fresh, `reset --hard`,
   and reads FOCUS.md from *that ephemeral clone*. The symlink is only a
   human browse/edit convenience, and edits to it still have to be committed
   + pushed before a clone sees them.

   The target shape that survives removing the checkout:
   - **Scheduler owns the human-authored scope.** Store each project's
     FOCUS.md (and QUESTIONS.md) *inside scheduler* as the master — the
     natural home is the existing `focus/<project>.md` / `questions/<project>.md`
     slots, but as **real files, not symlinks** once a project has no local
     checkout. The project repo's `.claude/FOCUS.md` flips from master to a
     synced artifact.
   - **The run injects scope into the ephemeral clone.** `scheduler-run`
     (or the engine) writes the scheduler-owned FOCUS.md/QUESTIONS.md into
     the throwaway clone after `reset --hard`, before invoking `claude`, so
     the project's `/nightly-batch` still just reads `.claude/FOCUS.md` as it
     does today — no per-project command change needed. If a question got a
     `> ` answer, the same round-trip carries the edit back.
   - **Repo cache, not a checkout.** Pull-on-demand into a scheduler-managed
     cache dir (keyed by repo, reused across runs — this is the dedicated
     clone the engine already maintains per `JOB_NAME`); a human moving or
     deleting the project's own working copy no longer affects anything.
   - **Migration is incremental and per-project.** A project keeps its
     symlink (checkout present) until it's explicitly switched to
     scheduler-owned scope; don't flag-day it. Design a single flag/marker
     (e.g. a conf field like `SCOPE_SOURCE=scheduler|repo`) that
     `sync-crontab.sh` reads to decide symlink-vs-real-file, mirroring how
     `SCHEDULER_SUBDIR` and the `*_SCRIPT` backwards-compat already work.
   - **Out of scope of this design, unchanged:** a project's *public intake*
     (e.g. chezz's web tracker fed by player chat submissions) is web-hosted
     and independent of where code lives — it stays as-is. Only the
     human-authored scope migrates into scheduler; do NOT try to pull player
     backlogs into FOCUS.md (two stores that would drift). FOCUS.md points at
     and prioritizes tracker items; it does not duplicate them.

   First verifiable pieces (pick off one per run, review-gate as usual): (a)
   a `SCOPE_SOURCE` conf field + `sync-crontab.sh` honoring it (real file vs
   symlink) with a preview that stays byte-identical for existing
   `repo`-source projects; (b) the inject-scope-into-clone step in the engine
   behind that flag; (c) the repo-cache reuse. Scheduler itself is the safest
   first mover (local-only, already dogfoods every mechanism).

5. Step 4 above should make it possible for scheduler to run on any machine, cloud host or my desktop, freeing up my laptop from this workflow. Since scheduler isn't usage aware right now, just lay the groundwork for features 4 and 5. 

6. Note: pushing this repo is now something scheduler can do itself. As long as that's revertable, it's just something that needs to be flagged for me to review (that it happened, what the consequences are/why I might want to revert it). To avoid conflicts with other scheduled jobs, we need awareness of effects. It makes sense to push/schedule this utility's development changes to occur after upcoming jobs are run, but before the morning.

## Shared-host footprint (this project's machine-wide surface)

*(Added 2026-07-26, human-directed, after `~/.local/bin/usage-paced-runner.sh`
— the file cron runs every 5 minutes — was found DRIFTED two days stale
against this repo. Build discipline requires this declaration and never had
one here. Senechal holds the same statement, filed via `notify-senechal`, so
the repair does not depend on anyone reading this file.)*

`# verified 2026-07-26 via crontab -l; ls -l ~/.local/bin; ls -d ~/.local/share/scheduler-*`

**Crontab (this user), scheduler-owned — 2 lines, both self-tagged
`# scheduler:<job>:<kind>`:**
- `*/5  * * * * PACED_MAX_PER_TICK=16 USAGE_CEILING=0.99 ~/.local/bin/usage-paced-runner.sh`
- `*/15 * * * * ~/.local/bin/scheduler sweep`

**`~/.local/bin` — expected state, and the repair when it is wrong:**
- `scheduler` → **symlink** into `bin/scheduler`. Cannot drift.
- `usage-paced-runner.sh` → **symlink** into `bin/usage-paced-runner.sh`
  **as of 2026-07-26**. It was a `cp` deploy and had silently fallen two
  days behind, missing the dead-man-switch block added 2026-07-26 — so
  expired participants kept consuming dispatch slots even though the repo
  said otherwise. The deployed copy contained NOTHING the repo lacked
  (verified by diff before replacing), so nothing was discarded.
  **Repair:** `ln -sfn "<repo>/bin/usage-paced-runner.sh" ~/.local/bin/usage-paced-runner.sh`
  (use a temp name + `mv -T` for the atomic swap — cron may fire mid-edit).
- `usage-gate.sh`, `scheduler-dev-cycle.sh` → **symlinks as of 2026-07-27**,
  converted in the same session. Both were byte-identical to the repo at the
  time, so nothing about what runs changed; what changed is that they can no
  longer diverge. This is realisateur/PLAYBOOK.md Play 2 in miniature:
  symlinks retire the drift class, rather than a `deploy` verb that re-copies
  it.

**All four are now symlinks, which makes Play 2's retirement available:**
`deployable_scripts()` returns EMPTY, so `scheduler pacing` prints "(nothing
deployable found)" and `scheduler pacing deploy` has nothing it can act on —
both are now dead weight rather than a guess about future need. Retiring
them (`deployable_scripts()`, `cmd_pacing_deploy`, the drift block in
`cmd_pacing`, the `deploy` line in `usage()`, ~80 lines and one verb) is a
clean catabolic pass with a real precondition met, and it is exactly the
kind of surface Law 3 says never gets removed on its own.
`# verified 2026-07-27 via ls -l ~/.local/bin; scheduler pacing`

  **DONE 2026-07-27 (paced cycle) — the retirement above is executed.**
  `deployable_scripts()` → `installed_scripts()` (now includes symlinks,
  since they are what it checks); `cmd_pacing_deploy` and the copy-based
  drift block are gone; `pacing deploy` is a one-line loud stub (exit 1,
  names what retired it) so a `cp`-era habit can't look like it worked;
  `usage()` loses the `pacing deploy` entry. Net −24 lines, one verb
  retired, **no new verb** (accretion freeze respected: same block, same
  place in `pacing show`). What replaced the drift check is the
  PRECONDITION check — every installed counterpart must still be a
  symlink that still resolves: `COPY` (a real file re-appeared, the
  2026-07-26 `usage-paced-runner.sh` case), `BROKEN` (dangling),
  `FOREIGN` (points at a different script), `OK` (with resolved target).
  Verified: all four branches plus the none-installed case exercised in a
  fabricated `HOME`, live run clean (four `OK`), retired-verb stub and bad
  verb both exit 1, `bash -n` clean, and re-run under
  `env -u SSH_AUTH_SOCK` (identical). This is the human-approved import
  swap (a) from BLOCKERS.md `## realisateur` call 3 / PLAYBOOK Play 2 —
  the **second of the two halves NAMED** as the axis-1 sequencing gate
  (first half: `sync-crontab.sh --apply` refuses a dirty `schedule/`,
  `e1042a4`, earlier today).
  **NOT clearance to flip a command column yet, and this is a real gap in
  how the gate was specified, not a technicality:** both named halves are
  now done, but the gate's stated *intent* — "the paced runner dispatches
  from a committed/validated copy of `_paced*.conf`" — is still NOT met.
  `usage-paced-runner.sh` is a symlink into the canonical checkout and
  reads `schedule/_paced.conf` out of that checkout's **working tree**, so
  an uncommitted edit to the command column still goes live on the next
  5-minute tick with nothing checking it. Symlinking fixed script drift;
  it does not make the conf a committed artifact. Filed as a judgment call
  in `.scheduler/QUESTIONS.md` (2026-07-27) rather than decided here.
  **DECIDED 2026-07-27 (`/ideate`, human-directed):** build the missing
  third piece — `usage-paced-runner.sh` refuses (or reads `git show
  HEAD:...` instead) when the relevant conf line is dirty relative to
  HEAD, reusing `e1042a4`'s `--check-clean` gate — BEFORE flipping any
  command column, chezz's included. Full rationale: `DESIGN-NOTES.md`
  2026-07-27; cross-referenced in `BLOCKERS.md` `## scheduler`. Queue
  this as the next `/nightly-batch` item once picked up from the backlog.
- `<project>-nightly-batch-loop.sh` / `-bug-sweep-loop.sh` (~20 legacy
  wrappers) → copies, but they only set variables and then
  `source "<repo>/lib/sweep-loop-common.sh"` by absolute path, so the LOGIC
  they run is never stale. New projects use `bin/scheduler-run` and add no
  wrapper at all.

**Detection:** `deployable_scripts()` in `bin/scheduler` deliberately skips
symlinks — a symlinked entry leaves drift scope because it can no longer
drift, and anything re-copied over one re-enters it and gets reported by
`scheduler pacing`.

**`~/.local/share` (state, not config):** `scheduler-registry/` (per-project
`.lock`/`.active`/`.interactive`), `scheduler-glance/seen.tsv`,
`scheduler-paced-runner/`, `scheduler-token-usage/`,
`scheduler-checks/<check>.lastrun` (runtime witnesses, added 2026-07-28 —
written by `lib/check-witness.sh`, read by `bin/check-witness-lint.sh`;
pure state, safe to delete, the next `sweep` re-creates one per wired
check), and one `<job>/` dir per registered job (log, expiry stamp,
deferral counter, dedicated clone).
**Not yet live** — created on first run of the merged code, so it needs a
`notify-senechal` line at merge, not now (nothing outside this worktree
has changed).

**Not scheduler's, listed so nobody re-owns them by mistake:** the
`~/.claude/settings.json` SessionStart/SessionEnd hooks and the
`6:30 weight-audit.sh` crontab line are **realisateur's**; the `~/.vimrc`
autocommit/merge hooks call `scheduler _commit-file` but live in the
human's own dotfiles.

## Watch and report tonight

- **Per-project pre-commit hook cost — SURVEYED 2026-07-24 (paced cycle),
  original ask now answered.** This item was flagged in an earlier
  2026-07-24 cycle's report as an open judgment call ("is this still
  live, or superseded?") but never actually got a `.scheduler/QUESTIONS.md`
  entry — the same "flagged in a report, not in the durable inbox" gap
  this file elsewhere warns against. Closing that gap here with a direct,
  read-only survey instead: checked every registered project's
  `git config core.hooksPath` (native `.git/hooks/pre-commit` is
  irrelevant — nothing here uses it; `chezz` sets `core.hooksPath=.githooks`,
  same convention `docs/feedback-tags.md` documents). **Result: of all 14
  registered projects (`aedile`, `chezz`, `crt`, `gardien`, `groc-mangr`,
  `home-assistant`, `nine-speakers`, `realisateur`, `scheduler`,
  `senechal`, `sequestria`, `vim-arcade`, `vkv-inventory`, `wtul`), only
  `chezz` has an actual hook.** Read it directly
  (`chezz/.githooks/pre-commit`, reading outside this repo is fine, same
  rule used elsewhere in this file) — it already carries the exact
  mitigation this backlog item was asking for, dated **2026-07-20** (two
  days after this item's original 2026-07-18 writeup — the fix landed
  before today's flag-it-again cycle, which apparently missed it):
  `check-syntax`/`check-size` run
  every commit, but the full Playwright suite (3+ min) only runs when a
  staged file falls outside `.claude/`, `README.md`, `DESIGN-NOTES.md`,
  `.githooks/`, `.gitignore` — added specifically because "a docs-only
  commit paid the full 3.4min cost for zero reason" (the hook's own
  comment). So the generalized awareness mechanism this item proposed
  (engine-side commit timing in the state dir) would be built for a
  problem that currently has exactly one instance, and that instance
  already self-mitigated its worst case. **Downgraded, not struck**:
  residual risk is real but narrower than originally scoped — a run that
  makes several *non-docs* chezz commits in one cycle still pays 3+ min
  per commit and could still stall past a tool timeout. Worth revisiting
  the generalized timing mechanism only if (a) chezz's hook regresses,
  (b) another project adds a heavy hook, or (c) that narrower multi-commit
  case is actually observed. Not worth building speculatively for a
  single, already-mitigated case today.

## Backlog (the intake — add a line to propose an idea)

- **2026-07-28 14:55 (via `scheduler -i`):** SECOND WITNESS + A REFUTATION for the unpushed-sweeper question filed this morning as 8c94eff. The sweep left ANOTHER commit stranded today: realisateur `30f1caa`, "scheduler sweep: adopted dirty .scheduler/QUESTIONS.md ... (2026-07-28T14:45)", committed and NOT pushed, found by `closeout-lint` at session close and pushed by hand (d6c8e01..30f1caa). Same message signature as chezz `3cf830e` at 10:15. Two repos, two occurrences, one day. THE REFUTATION, and it matters because it points the investigation somewhere else: 8c94eff`s leading hypothesis was that chezz pushes over the `github-chezz-deploy:` SSH alias and the sweeper has no reachable ssh-agent, so `focus-commit` dies at the push into an unread stderr. That cannot explain this one. **realisateur`s origin is a LOCAL BARE REPO** -- `/home/zach/git-remotes/realisateur.git` -- no SSH, no network, no agent, no credential of any kind. It still did not push. So the cause is in the sweep path itself, not in credentials, and the ssh-agent hypothesis should be dropped rather than carried forward. CONTROL, from the same repo and the same hour: two `scheduler -i realisateur` writes at 14:00 (964ad2f) and 14:14 (d6c8e01) both committed AND pushed successfully through focus-commit. So focus-commit`s push works fine in that repo, under that user, against that remote. It is specifically the `sweep` -> `cmd_commit_file` path that commits and does not push -- which is the interesting part, because cmd_commit_file is supposed to ROUTE FOCUS.md/QUESTIONS.md/BLOCKERS.md through focus-commit precisely so they get pushed. Worth checking whether that routing is reached at all on the sweep path, whether focus-commit`s exit status is being discarded there, or whether the sweep invokes a different branch of cmd_commit_file than the interactive `-i` path does. IMPACT UNCHANGED BUT NOW BROADER: any project whose runs reset a dedicated clone --hard to origin cannot see a commit that never left the local checkout. This morning that hid seven human answers from chezz`s nightly for a day. It is not chezz-specific and not remote-type-specific, so under the move-everything-to-dexter policy every project inherits it. Both instances were caught by a human/lint at close, never by a guard -- that is the part that should not survive the fix.

- **2026-07-28 14:54 (via `scheduler -i`):** FF-ONLY PULL OF THE HUMAN-FACING CHECKOUT -- Zach-directed 2026-07-28, and he explicitly framed it as general: "Other repos should probably behave similarly anyway." He plans to build the fix himself after; this is the spec, not a request for someone to race him to it. THE PROBLEM, generalized. `focus/<proj>.md` and `questions/<proj>.md` are symlinks into a project`s LOCAL WORKING CHECKOUT (PROJECT_REPO_PATH + SCHEDULER_SUBDIR, wired by sync-crontab.sh:419-433). That checkout is never refreshed by anything. Today it drifts whenever the project`s own nightly pushes; under the new move-everything-to-dexter policy (a36d3c0) it drifts on EVERY run of every moved project, because the writer is a different machine and Zach is no longer the one who happens to pull. The result is not a missing file, it is a STALE file that looks authoritative -- Zach reads questions that were already answered, or fails to see questions that were filed. This is not hypothetical: on 2026-07-27 three chezz questions were invisible to him for two days through exactly this path, and five tracker notes plus two nightly reports told him an answer was awaited in a file that did not contain the question. THE FIX. Before any read of a project`s FOCUS.md/QUESTIONS.md through the scheduler interface -- `scheduler status <proj>`, `scheduler focus`, the survey commands, and whatever opens these for editing -- run `git -C "$PROJECT_REPO_PATH" fetch --quiet` then `git merge --ff-only origin/<branch>`. WHY --ff-only SPECIFICALLY, and this is the whole safety argument: it refuses rather than inventing a merge commit or clobbering local changes, so it can only succeed where success is unambiguous. If Zach has uncommitted answers in the tree they survive (ff does not touch the worktree`s local modifications when they do not conflict); if the checkout has diverged it REFUSES and says so, which is the correct outcome -- divergence is a merge decision and bin/scheduler already states it is "NOT auto-resolved, ever". Precedent worth reusing rather than reinventing: cmd_commit_file already does exactly this fetch/ff-only/stall-reason dance around line 1180, including the loud WARNING text for the behind-but-not-fast-forwardable case. Lift that, do not rewrite it. TWO THINGS TO GET RIGHT. (1) FAIL LOUD, never silently skip. A refresh that quietly no-ops on error reproduces the exact bug it exists to fix -- if the ff cannot happen, SAY the checkout may be stale and why, at the top of the output where a human reads it, not into a log. (2) It only half-solves the round trip. This fixes remote->Zach. Zach->remote is the separate, already-filed defect (8c94eff): the ~30-minute sweeper committed chezz`s answers at 10:15 on 2026-07-28 and left them UNPUSHED, so a dedicated clone resetting --hard to origin could never see them; a human caught it, not a guard. Landing the ff-only pull without that push fix leaves the channel broken in the other direction, and worse, makes it LOOK fixed. SCOPE NOTE: this becomes load-bearing the moment a project`s execution leaves the host holding its human checkout. chezz is first (its dexter credential bar cleared today), but by the new policy every project follows.

- **2026-07-28 14:13 (via `scheduler -i`):** BLIND SPOT the "move everything to dexter" policy makes systemic: a project that moves to dexter goes DARK in mandark`s `scheduler status`, silently, and nothing announces it. Mechanism, from bin/scheduler:538 -- run state (sweep.log, expires_at, the dedicated clone) lives under $HOME/.local/share/<job-name> on the host that EXECUTES the run. Move the participant to dexter and that state stops being written on mandark, but `scheduler status <proj>` keeps reading mandark`s copy and keeps printing it as if current. WITNESS, live right now, not theoretical: `scheduler status crt` on mandark reports `=== done 2026-07-24T23:59:28-05:00 (54s) ===` -- four days stale -- because crt moved to dexter. crt has presumably been running fine there; mandark simply cannot see it. Nobody noticed for four days, which is the tell: this does not fail loud, it fails by looking normal. Under the old pin-by-need policy this affected one project. Under move-everything it becomes the default state of every project, and mandark`s status output degrades into a wall of stale timestamps that all LOOK like healthy last-run records. What survives the move without help, for the record: BLOCKERS.md (lives in this repo, git-tracked, both hosts have a checkout -- unaffected), and a project`s FOCUS.md/QUESTIONS.md (arrive by git pull, provided a checkout stays on mandark and gets refreshed). It is specifically the RUN LOG / last-run outcome that is host-local. Three shapes worth considering, in rough order of cost: (a) accept it, but make it LOUD -- if the executing host for a participant is not this host, `scheduler status` should say "runs on dexter -- last-run state not visible from here" instead of printing a stale record as if it were current. Cheapest, and it converts a silent wrong answer into an honest missing one, which is the actual bug; (b) have each run write its outcome into a git-tracked file in the project repo (chezz already writes a dated nightly report), and let `scheduler status` fall back to that when local run state is absent or older than the repo`s -- makes run history travel with the project rather than with the machine; (c) a real remote status fetch over ssh, most faithful and most machinery. RECOMMEND (a) NOW regardless of which of the others lands later: it is small, it is honest, and without it every future dexter move quietly makes mandark`s status output less true. Filed from an interactive /ideate pass 2026-07-28 while scoping the chezz move; the same gap will hit chezz the day it moves.

- **2026-07-28 14:00 (via `scheduler -i`):** POLICY CHANGE, human-directed by Zach 2026-07-28 (interactive /ideate): **the dexter pinning policy is REVERSED. The policy is now to move everything possible to dexter.** This SUPERSEDES the "pin by need" rule that says only hardware/network-evidenced projects belong on dexter and that a project must not be moved there just to balance load. Under the new policy, dexter is the default execution host and the question flips: instead of "does this project have hardware evidence justifying a move?", ask "is there anything preventing this project from running on dexter?" -- and if not, move it. Hardware evidence is no longer the entry bar; it was the entry bar. WHAT STILL STATES THE OLD RULE, and needs amending by whoever owns each file (naming these loudly rather than assuming someone will notice): (1) `schedule/_paced.dexter.conf` lines 29-33, the "PINNING POLICY: only hardware/network-evidenced projects belong here. Do NOT move a project here just to balance load" block -- this is the most authoritative-looking statement of the rule and it is now WRONG, but that file is dexter-owned ("dexter writes ONLY this file") so it must be amended in a human session ON dexter, not from mandark; until then an agent reading it will follow a retired policy. (2) `DESIGN-NOTES.md` around lines 785, 901 and 927, which record hardware-evidenced-pinning-only as a 2026-07-24 decision -- those entries should get a dated SUPERSEDED note rather than being rewritten, since they are the historical record of why the old rule existed. (3) `schedule/_paced.conf` line 162 references the crt precedent as a hardware-evidenced pin; still true as history, but no longer the gating criterion. WHAT DOES NOT CHANGE: the credential bar. wtul was moved to dexter 2026-07-25 and reverted the SAME DAY because dexter lacked the SSH host alias and deploy key, so `git ls-remote` failed at name resolution. "Move everything possible" makes that bar MORE important, not less -- "possible" means the remote is live-verified reachable FROM dexter before the participant line moves, per project. A policy that moves projects faster than credentials are provisioned just converts one revert into many. Also unchanged: two hosts must never dispatch the same participant, so each move is a paired edit (drop/disable in _paced.conf, add in _paced.dexter.conf) and the second half happens on dexter. IMMEDIATE CONSEQUENCE: chezz no longer needs a named exception to move -- the "chezz would be the second non-hardware exception" concern raised earlier today in chezz .scheduler/QUESTIONS.md (d7f1229) is RETIRED by this decision. The remaining chezz questions there are about the answer surface, move scope, branch model and the Gemini key -- not about permission to move.

- **2026-07-28 13:59 (via `scheduler -i`):** FOLLOW-UP to today's pin-policy supersession (2026-07-28, realisateur /ideate close): the DECISION is filed but the DOCTRINE TEXT still says the opposite, and nothing has reconciled them.

`schedule/_paced.dexter.conf`'s header still carries, verbatim: "PINNING POLICY: only hardware/network-evidenced projects belong here. Everything else stays on mandark. Do NOT move a project here just to balance load." Zach superseded that today -- pin by contention relief, chezz moves -- and that decision is recorded in this FOCUS.md. The conf comment was deliberately NOT edited, for a stated reason: that file's own concurrency story is "dexter writes ONLY this file, mandark writes ONLY _paced.conf", so hand-editing it from mandark would violate the exact invariant that makes the two-host design safe by construction. Refusing was right; leaving it unreconciled is not the end of the obligation.

Why this specific gap deserves a fix rather than a note: it is the failure mode this whole session kept finding. crt's dexter pin is justified in that same file by OctoPrint reachability -- but crt moved to potato on 2026-07-23, so the stated rationale decayed while the conclusion survived and became true again for an unrelated reason. A rationale that outlives its evidence is the hardest kind to catch, because nothing fails. `_paced.dexter.conf` now contains a policy statement that the ecosystem has decided against, sitting in the file a future session reads FIRST when deciding whether a project may be pinned there. The predictable outcome is someone correctly following the file and reversing a decision Zach made.

WHAT SHOULD HAPPEN, in preference order:
1. A session running ON dexter edits the header itself -- respects the write-ownership invariant, no coordination needed.
2. Failing that, scheduler's own loop reconciles it as an explicit exception with the reasoning recorded, since scheduler owns the file's semantics.
The edit itself is small: replace the pin-by-need paragraph with pin-by-contention-relief, KEEP the named-risk paragraph (the usage-gate race is now live rather than theoretical, since dexter dispatches for real as of today), and note wtul's 2026-07-25 exception is subsumed rather than still an exception.

Reader: whichever of the above runs first. This is a doctrine-text reconciliation, not a behavior change -- nothing dispatches differently either way, which is precisely why it will not surface on its own.

- **2026-07-28 13:55 (via `scheduler -i`):** chezz -> dexter move (from an interactive /ideate pass, 2026-07-28). Zach is moving chezz execution to dexter, minimal build, production flow unchanged; the GitHub-issues redesign of the question channel is a deliberately later pass. Four calls are recorded in chezz .scheduler/QUESTIONS.md (d7f1229) awaiting his answer -- this note is the scheduler-side half, since the mechanics live in this repo. THE ONE HARD PREREQUISITE, already proven: dexter needs a `github-chezz-deploy` SSH host alias + the chezz deploy key, verified by `git ls-remote git@github-chezz-deploy:hf7y/chezz.git` run FROM dexter, before any participant line moves. wtul was moved to _paced.dexter.conf on 2026-07-25 and reverted the SAME DAY for exactly this gap; chezz must be held to the same bar crt was. Not verifiable from mandark -- no key here authenticates to dexter, and _paced.dexter.conf is owned/written on dexter in a human session, which is consistent with policy rather than a gap. POLICY CALL, not just config: _paced.dexter.conf pins only hardware-evidenced projects, with wtul as a named exception; chezz would be the SECOND non-hardware exception, so the pinning policy needs an explicit amendment or an explicit second exception rather than a quiet line move. Note chezz has TWO participants (`chezz|1|2` and `chezz-sweep|1`); moving one and not the other means two hosts dispatch the same project, which both confs must then state honestly. FINDING WORTH KEEPING regardless of the move: sync-crontab.sh:419 already treats PROJECT_REPO_PATH as optional and only creates the focus/questions symlinks when it is set -- so the engine already supports a project with no local working copy. The thing that breaks without a local checkout is the HUMAN answer surface, not dispatch. That is the actual design constraint for any no-repo-on-mandark future, and it is worth stating in the docs where someone will find it before they discover it by unsetting the field.

- **2026-07-28 13:38 (via `scheduler -i`):** CORRECTION to the chezz migration checklist filed earlier today (2026-07-28, realisateur /ideate): step 4's proposed roster line DOES NOT WORK. Verified live on dexter, not reasoned about.

WHAT I FILED: `chezz|1|2|/home/zach/scheduler/bin/scheduler-run chezz batch`, on the reasoning that dexter's existing crt line uses that form and the 2026-07-24 decision says no per-host wrapper should need to exist.

WHAT ACTUALLY HAPPENS: `scheduler-run chezz batch` exits **rc=2** with "BATCH_SCRIPT is set in schedule/chezz.conf -- that legacy wrapper is authoritative for tier 'batch'; run it directly, or remove BATCH_SCRIPT to migrate onto scheduler-run (see MIGRATION.md)". chezz.conf sets BATCH_SCRIPT=/home/zach/.local/bin/chezz-nightly-batch-loop.sh, a path that exists on mandark and not on dexter. Credit where due: this fails loud and correct, which is why it took one probe instead of a silent 3am no-op -- contrast the 401 finding in the original filing.

THE REAL FORK, which is scheduler's to settle, not realisateur's:
(a) Remove BATCH_SCRIPT from chezz.conf, migrating chezz onto scheduler-run per MIGRATION.md. Clean, and moves chezz off the legacy path permanently. BUT the blast radius is BOTH HOSTS: chezz.conf is one shared file and mandark executes from this same git history on a */5 tick, so this changes how mandark dispatches chezz on its next tick, unreviewed. That is exactly the governing constraint DESIGN-NOTES names ("the blast radius of a commit here is both machines, immediately"). If this is the path, it wants the same treatment every other shared-script edit got: proven equivalent on mandark first, not just assumed.
(b) Install chezz-nightly-batch-loop.sh at the same ~/.local/bin path on dexter. Smaller blast radius, works immediately. BUT it re-creates the per-host wrapper duplication that the 2026-07-24 decision explicitly rejected, and the wrapper already carries a known drift hazard: its PROMPT hardcodes .scheduler/FOCUS.md, which silently pointed at a nonexistent file for a day when chezz moved that path on 2026-07-24, and any run dispatched in that window ran UNSCOPED. Two copies doubles that surface.

A third possibility worth naming rather than assuming away: this may be the concrete case that motivates the queued "one resolver for per-project path + ref" item, since both options above are workarounds for the same root cause -- a conf that mixes host-specific absolute paths with host-independent project identity.

ALSO WORTH KNOWING, since it bears on which option is cheap: chezz's toolchain on dexter is now fully provisioned and proven under simulated cron (env -i + crontab PATH + /bin/sh -c): node v24.18.0, npm 11.16.0, headless chromium LAUNCH_OK. A PATH= line was added to dexter's crontab because cron gave only /usr/bin:/bin while ~/.bashrc returns early for non-interactive shells before its nvm block -- every scheduled job on dexter was previously unable to see node. Filed to senechal. So nothing about the toolchain blocks either option; the only remaining external blocker is registering dexter's new deploy key on the GitHub repo.

- **2026-07-28 12:53 (via `scheduler -i`):** PIN POLICY SUPERSEDED (2026-07-28, Zach-directed via realisateur /ideate): pin by CONTENTION RELIEF, not only by hardware/network need.

_paced.dexter.conf's standing rule -- "only hardware/network-evidenced projects belong here ... do NOT move a project here just to balance load" -- was written 2026-07-24 when mandark was not contended. It now is: bibliothecaire's overnight OCR and the newly-registered ecosim competed for memory on the same box and ended in a plasma crash senechal had to repair. Zach's decision: self-contained projects (no mandark-local hardware, no mandark-local path dependency) move to dexter deliberately, to relieve mandark. chezz is the first, beyond wtul's existing named exception.

STATE THE COST HONESTLY, because this is what the old policy was protecting: the 2026-07-24 usage-gate race (both hosts probe account-wide headers, both see slack, both dispatch, account overshoots between probes) was accepted as an MVP risk to be OBSERVED empirically. It has never been observed, because dexter has never dispatched -- see the finding below. Moving real projects there is what finally makes that race live. The one-line lever if it bites is per-host USAGE_MIN_SLACK/USAGE_CEILING in schedule/_usage.dexter.conf; that mechanism already exists.

BLOCKING FINDING, same session, verified live on dexter at 12:40: dexter's paced runner has NEVER dispatched anything. ~/.local/share/scheduler-paced-runner/run.log shows 338 consecutive "HOLD (gate rc=2) verdict=ERROR reason=no_headers http_code=401" entries, every 5 minutes since 2026-07-25T23:55. grep -c DISPATCH = 0. dexter's Claude Code is not logged in. crt has sat there enabled at weight 3 for three days running zero times, and nothing reported it -- the runner logs a HOLD and exits 0, so this is invisible to every existing survey. Worth a mechanism: a paced runner that has HOLDed on the SAME error N times consecutively should surface that somewhere a human or ecosystem-survey reads, rather than logging quietly forever.

ALSO FIXED this session (verified safe first, not guessed): dexter's ~/scheduler clone was 168 behind / 3 ahead of origin/main and could not fast-forward -- it had been executing pre-rebase, three-day-stale shared dispatch code. All three "ahead" commits were confirmed already-superseded duplicates: their content landed on main under different SHAs in a 2026-07-25 rebase (12ce8a3->7aa042f, 45b317b->3b0ad9f, 59dd864->8d27aa9), and main has since moved 184 further lines on lib/sweep-loop-common.sh. Tree was clean. Tagged pre-reset-2026-07-28 on dexter, then reset --hard to origin/main (now 15948a8, 0/0). Nothing lost; the old SHAs survive under that tag.

CHEZZ MIGRATION CHECKLIST (recorded, not executed -- /ideate does not build):
1. dexter Claude Code login, same primary Max account as mandark. Gates everything; a different account silently defeats the shared-quota premise.
2. node + npm are MISSING on dexter. chezz has package.json/node_modules/playwright.config.mjs, so this is a real toolchain install plus `npx playwright install` and its headless-browser system deps -- chezz is self-contained in NETWORK terms, not in toolchain terms. Do not assume "self-contained" means "nothing to install."
3. chezz deploy key on dexter: a `github-chezz-deploy` Host block in ~/.ssh/config plus the key, matching schedule/chezz.conf's REPO_URL. Same pattern as the existing dexter_scheduler_deploy / dexter_wtul_deploy entries.
4. Roster line in _paced.dexter.conf using the scheduler-run form the crt line already uses -- `chezz|1|2|/home/zach/scheduler/bin/scheduler-run chezz batch` -- NOT a per-host wrapper copy (2026-07-24 decision: no per-host wrapper should need to exist).
5. Flip chezz (and chezz-sweep, decide separately) to enabled=0 in _paced.conf the same commit. The double-dispatch hazard is confirmed live, not theoretical -- see the aedile/vkv-inventory lines.
6. Note schedule/chezz.conf's PROJECT_REPO_PATH is "/home/zach/Documents/Project Archive/chezz", a mandark-specific path. Confirm dispatch on dexter resolves the repo via REPO_URL clone and does not silently depend on that path existing. This is the same class of bug as crt's REPO_URL-unreachable-on-dexter finding.

- **2026-07-28 12:43 (via `scheduler -i`):** A bare `git commit` (no pathspec) in a shared repo silently ADOPTS another session's staged work. Witness (chezz, 2026-07-28 11:32, `e3590c3`): ecosim `bin/install-silence-audit.sh` left 19 repos dirty; the follow-up hand-commit of chezz's CLAUDE.md ran a bare `git commit` while an interactive session had 5 unrelated source files STAGED, waiting on a ~5min pre-commit Playwright suite. Result: one commit titled "CLAUDE.md: adopt the silence-audit checklist retirement" containing 329 insertions of Gemini spend-cap code plus 6 lines of CLAUDE.md -- ~3% of the diff matches the message -- and the staging session's own commit message, which documented the design rationale, was discarded. Nothing was lost; the history now lies about what happened, which is worse than a conflict because it does not announce itself. This is EXACTLY the race `focus-commit` was built for, on source files instead of FOCUS.md/QUESTIONS.md -- and nothing guards that case. Note the amplifier: a long pre-commit hook widens the window between `git add` and the commit landing from milliseconds to minutes, so the busier the repo the likelier the collision. Ask: should any cross-project script that commits in a repo it does not own be required to pass an explicit pathspec (`git commit -- <paths>`), the way focus-commit already does, and/or run check-project-busy first? A one-line change in each such script; the failure it prevents is invisible by construction.

- **2026-07-28 10:49 (via `scheduler -i`):** SIM EVIDENCE for the cross-account status bug already filed as 523ee65. A toy cybernetic model of this ecosystem (realisateur branch research/ecosystem-cybernetics) was run across 11 arms, 60 seeds and 10 disturbance regimes. Result: adding a BLIND output symbol to a single sensor cut unregulated-disturbance ticks by ~88 percent versus the current two-symbol baseline, and the effect survived a hostile parameterisation where a BLIND report only leads to a structural fix 20 percent of the time. Adding MORE sensors while they share the same $HOME-scoped blind spot produced a byte-identical result to the baseline -- literally zero improvement -- which is the modelled form of why sensor reconciliation cannot fix a correlated blind spot. The minimal, behaviour-preserving change is therefore NOT to make status read the other account, but to stop it asserting a negative over a domain it never read: when a project's conf sets CRON_ACCOUNT to another user and that account's state is unreadable, print BLIND naming the domain, never the local $HOME path's state.

- **2026-07-28 10:37 (via `scheduler -i`):** PRECONDITION-GATED BACKLOG ENTRIES: let an entry carry a probe that decides whether it is true yet. Origin: 2026-07-28 interactive /ideate, Zach-directed, after the same answer came up three times in one session -- what mechanism covers this? none, but here is prose that behaves like one. THE OBSERVED GAP. An event in project A is often material for project B, and there is exactly one real fan-out path in the ecosystem: notify-senechal, hardcoded to one recipient and one event class (machine-wide config). Everything else is a human noticing and filing by hand. Today the concrete case was: decide.sh option 2 archives orphaned wrappers under svc-vaporwave, and bibliothecaire briefs/stigmergy.md wants that as a fourth exhibit -- but only AFTER the archive actually happens, and nothing fires when it does. THE WORKAROUND, which is the proposal in embryo. The note was filed ahead of the action with its own precondition at the top: run  sudo -n -u svc-vaporwave ls -d /home/svc-vaporwave/archive-2026-07-28  -- if the path is absent the entry is not yet true, stop, leave it. The entry is inert until the disk says otherwise. This inverts a trigger into a guard, and it works without any new engine support, but only because that particular event left a filesystem trace to point at. THE PROPOSAL, smallest useful form: a first-class GATE field on a FOCUS.md backlog entry -- a read-only shell probe plus the expected outcome -- that an unattended run evaluates before treating the entry as actionable, and skips (silently, not as a failure) when it does not pass. This is engine work because the value is in every run honoring it uniformly, which is exactly what prose cannot guarantee: today the guard holds only because one entry happens to say so in its first sentence and a future run happens to read carefully. WHY THIS SHAPE AND NOT THE OTHERS, stated so they are not re-proposed. A generalized notify-project <name> was considered and rejected as near-duplicate of scheduler -i, which already writes through the front door; the part notify-senechal adds beyond -i is confirming the note reached the remote, which is a smaller fix to -i itself, not a new command. An event-class subscription registry (projects declare which events they care about) was considered and deprioritized as speculative and daemon-shaped -- it wants live state, and the 2026-07-20 keep-cron decision names its own revisit trigger, which this is not. THE RISK, which is the real design question and should be settled before any code. A shell probe embedded in a markdown file is arbitrary code that an unattended run would execute, in a file with multiple writers including agents. That is a materially worse blast radius than anything the FOCUS format carries today, and it argues for a closed vocabulary of gate types (path-exists, file-newer-than, command-exit-zero-from-an-allowlist) rather than an eval of whatever string is present. If that constraint makes the feature not worth building, that is a legitimate outcome and better than a permissive version. WHAT WOULD MAKE THIS PROPOSAL WRONG, stated deliberately per the same session prose-trap finding: if in practice almost no cross-project event leaves a probeable trace, the gate field is machinery for a case that mostly cannot use it, and the honest fix is the boring one -- a human files the note after the fact. One data point is not a pattern; this proposal rests on a single occurrence, and the correct next step may be to notice two more before building anything.

- **2026-07-28 10:27 (via `scheduler -i`):** Did the ~30min sweeper actually PUSH? Witness (chezz, 2026-07-28): `scheduler sweep` committed 3cf830e ("adopted dirty .scheduler/QUESTIONS.md") at 10:15 carrying 46 lines of Zach answers -- and left it UNPUSHED. Found and pushed by hand at ~10:20 in an interactive session. The usage text for `sweep, -s` says it "auto-commits AND pushes"; cmd_commit_file routes QUESTIONS.md through focus-commit, which does push and dies loudly on failure. So the commit-half fired and the push-half did not, silently, from the caller nobody reads. Cost if unnoticed: chezz nightly resets its dedicated clone --hard to origin, so three answered design questions would have been re-triaged a third consecutive night as "awaiting a human answer" -- the exact stranded-commit failure the 2026-07-26 freshness-check fix was written to end, reappearing on the focus-commit path instead of the bare-git one. Leading hypothesis, unverified: chezz pushes over the SSH alias `github-chezz-deploy:hf7y/chezz.git` (deploy key), and the sweeper is likely running without an ssh-agent/key it can reach, so focus-commit fails at the push and its die() output goes to a cron/hook stderr with no reader. Two questions: (1) would the next sweep have caught its own miss, or does an unpushed-but-committed repo look clean to the scan? (2) whatever the cause, a sweeper whose push silently no-ops needs a witness that is not cron stderr.

- **2026-07-28 09:48 (via `scheduler -i`):** ENGINE PROPOSAL from realisateur /ideate 2026-07-28 (Zach asked: 'the scheduler watcher eating commits mid-change is a huge problem, worth addressing immediately?'). Filed here rather than hand-edited, per /ideate step 5.

DEFECT: cmd_sweep guards adoption with interactive_holder "$name" -- a presence marker keyed to the project whose file the EDITOR opened (hold_project_marker, set by open_file/session-marker.sh). But this ecosystem is built on cross-project writes: realisateur's /ideate cross-write privilege, notify-senechal, focus-commit <repo>, and any agent editing another repo. A session holding realisateur's marker while writing wtul leaves wtul looking abandoned, so sweep adopts a live edit mid-write. cmd_commit_file also PUSHES, so a half-finished FOCUS.md/QUESTIONS.md reaches origin/main -- the exact ref every unattended run clones.

NOT THEORETICAL: 7 adoptions ecosystem-wide in the 36h to 2026-07-28 (wtul, senechal, bibliothecaire, vim-arcade, scheduler x3). One (wtul 4b02419, 2026-07-27T14:30) swallowed Zach's own live reply-writing burst. Another took a realisateur session's 116-line in-progress QUESTIONS.md restoration at 09:30 today and committed it as 'author unknown'; it was caught only because the session happened to check git log immediately after.

The honest-attribution work (2026-07-26) fixed what the commit message CLAIMS. It did not change when adoption fires. The message is now accurate about not knowing whose work it is -- which is the finding, not the fix.

PROPOSED, for Zach to choose (realisateur has NOT implemented any of these):
(a) QUIESCENCE -- record a per-file hash each tick; adopt only if identical two ticks running. An in-flight edit changes between ticks, an abandoned one does not. Needs no marker, so it covers cross-project writes, GUI editors and agents for free. Cost: backstop latency 15min -> 30min. This is realisateur's recommendation.
(b) GLOBAL MARKER -- defer if ANY *.interactive marker is live, not just this project's. Simplest; misses writers that hold no marker.
(c) BOTH.
(d) SWEEP STOPS PUSHING -- smallest change, keeps mis-attributed local commits but stops a half-written file reaching the clone ref.

Sweep's own comment already argues deferral is free ('sweep runs again in 15 minutes, and sweep only ever commits, so a deferral leaves the file exactly as the human has it') -- that reasoning supports (a) directly.

- **2026-07-28 (from the wtul question-backlog investigation, Zach-directed):
  the `%%TAG` path in `collect-feedback.sh` still destroys unacted feedback.**
  Fixed today for `> ` replies (`3170b81`): `--consume` marks them `>>`
  instead of deleting, because stripping the marker was a side effect of
  *reading*, before the caller had decided whether to act. `%%ACTION`/
  `%%BLOCKER`/`%%QUESTION`/`%%NOTE`/`%%APPROVE`/`%%REJECT` lines are still
  deleted outright by the same call and have the identical defect.
  The live failure this class already caused: wtul run 28 (2026-07-27,
  wtul `0baabb6`) consumed 28 of Zach's replies, judged them "mostly not
  actionable", deleted zero entries, and left the answers as unattributed
  prose inside still-open questions — invisible to every later run.
  Recovered 2026-07-28 (wtul `cbe597d`) only because the markers survived
  in git. A `%%TAG` has no such luck: its keyword IS the marker, so a
  destroyed one leaves a bare sentence with nothing identifying it as
  feedback at all. Needs a marking convention that survives the round
  trip and is skipped on re-read, the way `>>` is — `%%~ACTION` or
  similar, chosen so the existing `^%%(ACTION|...)` match cannot see it.
  Not done today: it touches the documented tag vocabulary in
  `docs/feedback-tags.md` and every consumer of it, which is a wider blast
  radius than the reply fix and deserves its own pass.

- **2026-07-28 08:48 (via `scheduler -i`):** `scheduler -i` exits 0 when its write never reached origin. Found by senechal 2026-07-28; deferred at the time because check-project-busy reported scheduler BUSY, filed now that the lock cleared.

REPRODUCED, not theorised. Filing a cross-write into wtul at 08:26:
  - focus-commit did exactly the right thing: it committed c80e8d9, hit a rejected push, fetched, rebased, detected that the rebase changed the meaning of the commit, undid the rebase, restored the tree, pushed NOTHING, printed
      'FAIL: REBASE CHANGED WHAT OUR COMMIT MEANS ... NOTHING PUSHED'
      'WARNING: focus-commit exited 1 ... the edit is NOT on origin. A scheduled run resets its clone --hard to origin, so it stays invisible to dispatch until this is resolved by hand.'
    and exited 1.
  - The wrapping `scheduler -i` printed all of that and then returned rc=0.

WHY IT MATTERS MORE THAN A COSMETIC EXIT CODE. A caller that checks the exit status -- which is what any unattended run, batch wrapper, or agent following BUILD-DISCIPLINE is told to do -- concludes the note was filed. It was not. Worse, the failure mode is silent in the direction that loses data: a scheduled run resets its clone --hard to origin, so the local commit is not merely unpushed, it is scheduled for deletion. The warning text says this explicitly and the exit code contradicts it.

This is BUILD-DISCIPLINE 'fails loud / no exit-0 no-ops' in the one place it is least affordable: the guard that exists to make cross-project writes safe. A guard that refuses correctly and then reports success has spent its correctness.

ASK: propagate focus-commit's exit status through `scheduler -i` (and any sibling verb that wraps it). If there is a reason the wrapper must return 0 -- e.g. the idea file itself was written locally and that counts as partial success -- then it needs a distinct nonzero code for 'staged locally, NOT on origin' rather than collapsing to 0.

CLOSE CHECK (senechal keeps this open until it re-probes this itself; filing is not closing):
  # in a repo whose upstream has moved with a conflicting FOCUS.md edit:
  scheduler -i <project> "probe"; [ $? -eq 0 ] && echo 'OPEN: still exits 0'

Recorded as senechal ESTATE.md finding 9 (senechal b85640c). Note this same session ALSO hit the guard working perfectly: the wtul note was resolved by hand, verified as a pure 30-line addition removing nothing, and pushed as 39ef7aa. The guard is good. Only its exit status lies.

Second, smaller, same family: check-project-busy reported 'free' for wtul seconds before wtul's own run 31 pushed and caused the conflict above. That is a race, not a bug -- busy-checks are advisory and the content guard is what actually held. Worth a line in the docs saying so, so callers do not treat 'free' as a lock.

- **2026-07-28 08:36 (via `scheduler -i`):** ECOSYSTEM ANNOUNCEMENT (addressed to BOTH realisateur and scheduler; filed to each — 2026-07-28, Zach-directed via /ideate gardien): we need managed resources on dexter as soon as possible. Trigger: on the night of 2026-07-27/28, bibliothecaire ran OCR jobs that consumed system memory all night while the new ecosim ran models competing for the same memory; the contention ended in a plasma crash that senechal had to repair. Standing direction: mandark-independent projects should migrate to dexter by default, with mandark demoted to a jump box — which means dexter is about to host substantially MORE concurrent heavy work, not less, and this incident is a preview rather than an outlier. Gardien has just confirmed (FOCUS.md 2026-07-28, decision 2) that its own nightly rsync will keep executing ON dexter, co-located with the backup disk — deliberately accepting that it becomes one more tenant competing for the same box. That decision is explicitly conditional on this announcement existing: gardien is a tenant of a resource-management mechanism, not the owner of one. What is needed, and belongs to realisateur/scheduler rather than to any single project: (a) resource caps that a dispatched job actually runs under — cgroup/systemd MemoryMax, MemoryHigh, IOWeight, nice — rather than each project being trusted to behave; (b) an admission policy for who may run heavy work when, so two memory-hungry projects cannot both be dispatched into the same overnight window; (c) some form of pressure sensing so the ecosystem notices contention before a desktop session dies, rather than after senechal repairs it. Realisateur owns the cross-project policy question (which projects are heavy, what the weights/windows mean); scheduler owns the dispatch-layer enforcement (actually launching jobs inside a constrained slice). Neither half is gardien to build. Please treat this as a persistent item, not a one-off note — it should stay visible until real caps exist, because every project that migrates to dexter in the meantime silently assumes it has the box to itself.

- **2026-07-28 01:01 (via `scheduler -i`):** ENGINE BUG, top-ranked finding of the 2026-07-28 human-directed /ideate deep-dive into dexter + svc-vaporwave. 'scheduler status' ACTIVELY MISREPORTS both svc-vaporwave projects, and it misreports them in the direction of alarm. VERIFIED TONIGHT by running it: 'scheduler status aedile' prints 'last scheduled run (aedile-nightly-batch) -- no log yet at /home/zach/.local/share/aedile-nightly-batch/sweep.log', i.e. never run. 'scheduler status vkv-inventory' prints '=== FAILED 2026-07-20T01:41:23-05:00 (1148s) === WARNING: local commit made but NOT pushed to origin'. Both readings are false. Read from the account that actually runs them, aedile has succeeded every night through 2026-07-27 (svc-vaporwave ~/.local/share/aedile-nightly-batch/run.log, last '==== done 2026-07-27T03:05:35-05:00 ====', pushed 148833a, PR #5) and vkv-inventory has succeeded 07-24/25/26/27 (sweep.log, last '=== done 2026-07-27T04:04:41-05:00 (219s) ===', pushed 2ce02f6). ROOT CAUSE, mechanical and one line: bin/scheduler resolves every run-state path against $HOME -- PACED_LOG, REGISTRY_DIR, the expiry scan at line ~1742 ('for stamp in $HOME/.local/share/*/expires_at'), the stranded-clone scan at ~1769 and ~2012 ('for repo in $HOME/.local/share/*/repo'), and the per-job sweep.log read. schedule/aedile.conf and schedule/vkv-inventory.conf both already declare CRON_ACCOUNT="svc-vaporwave" and an absolute BATCH_SCRIPT under /home/svc-vaporwave -- the conf KNOWS the job runs elsewhere, and the status reader ignores it. WHY THIS IS THE WORST SHAPE, in the ecosystem's own terms: it is BUILD-DISCIPLINE pattern 14 exactly ('a sensor reports a negative it never checked for', fails toward alarm, alarm routed to the scarcest organ) and it is worse than the 2026-07-27 steward-survey instance, because a stale FAILED is not merely absent data -- a blank would be honest. It is also Conway's law biting: the sensor is $HOME-shaped because the organism was one-account-shaped, and the ecosystem grew a second account without the perception layer growing a channel to it. And it has been KNOWN and unfixed for 8 days: svc-vaporwave's own aedile wrapper header, written 2026-07-20, says 'Open question, not yet resolved: whether zach's scheduler glance command should also surface this account's reports. Flagged, not solved here.' PROPOSED FIX, yours to improve: when a project's conf sets CRON_ACCOUNT to something other than the invoking user, resolve that job's state paths under that account's home and read them via 'sudo -n -u <acct>' (zach already has '(svc-vaporwave) NOPASSWD: ALL' in sudoers, verified tonight via 'sudo -l'). NON-NEGOTIABLE per tonight's earlier drops: if the cross-account read is not possible, the status line must say BLIND/NOT-PROBEABLE naming the domain it could not read -- it must never fall back to reading the local $HOME path and printing that as the job's state, which is the exact defect. Same fix applies to 'scheduler sweep' expiry and stranded-clone scans, which today silently cover only half the ecosystem's jobs.

  - **PARTLY DONE 2026-07-28 (paced cycle) — `scheduler status`'s last-run
    block is fixed; `scheduler sweep`'s scans are NOT yet.** `bin/scheduler`
    gained four helpers (`state_account`/`state_home`/`state_run` +
    `state_exists`/`state_cat`/`state_readable`): a project whose conf sets
    `CRON_ACCOUNT` to another user has its run state resolved under THAT
    account's home and read via `sudo -n -u <acct>` (`-n`, so an unattended
    caller can never hang on a password prompt). If that read fails the line
    prints **BLIND**, naming the account and the path it could not read, and
    makes no claim about whether the job ran — it never falls back to
    `$HOME`'s path, which is the defect itself. Also fixed alongside, because
    without it aedile still read as never-run: the marker regexes now accept
    both dialects (`===+`), and `run.log` is read when `sweep.log` is absent
    (aedile's older wrapper writes the former).
    Verified by running it: `scheduler status aedile` now prints
    `==== done 2026-07-28T03:04:30-05:00 ====` instead of "no log yet", and
    `scheduler status vkv-inventory` prints its real current state instead of
    replaying 2026-07-20's FAILED. Local-account projects (chezz, scheduler)
    print byte-identical output to before. The BLIND path was exercised for
    real against a fabricated conf with `CRON_ACCOUNT="daemon"` (no sudo
    rule): it printed BLIND naming `/usr/sbin/.local/share/...` and did not
    substitute `$HOME`. Missing-log and empty-`BATCH_JOB_NAME` paths also
    exercised. `bash -n` clean (`shellcheck` is still not installed on this
    host — see the 2026-07-28 report).
    **Surfaced by the fix, needs a human:** vkv-inventory's dead-man switch
    tripped 2026-07-27T20:51 and its 2026-07-28 04:00 run was `skipped
    (expired)` — nothing had been able to see that from this account.
    Renew with `rm /home/svc-vaporwave/.local/share/vkv-inventory-nightly-batch/expires_at`.
    **Still open:** the same treatment for `cmd_sweep`'s expiry scan
    (`$HOME/.local/share/*/expires_at`) and both stranded-clone scans
    (`$HOME/.local/share/*/repo`), which still cover only this account's
    jobs. Those are glob scans rather than per-project lookups, so they need
    a different shape (enumerate confs with `CRON_ACCOUNT`, scan each such
    home too) — deliberately deferred to keep this cycle one verified change.

- **2026-07-28 (`/ideate`, human-directed): the four readability findings
  become MECHANISMS, not conventions. "Make mechanisms everywhere you can
  based on this lesson."**

  **Vision.** A document convention a human (or agent) has to *remember*
  is a latent bug, and this repo has now been bitten by that four ways in
  one file pair. The regulator is three rules, in this order: **generate,
  don't type** (structure the writer cannot get wrong); **lint, don't
  remind** (what can't be generated fails loud in `sweep`); **archive,
  don't delete** (a removal leaves a receipt AND a retrievable copy).
  What is DECIDED: all four items below get built as mechanism. What is
  NOT decided and must not be assumed: the entry-ID scheme's exact form,
  and whether bibliothecaire wants the archive as files-in-repo or as an
  ingest call — that's bibliothecaire's call, not scheduler's (see
  Blockers).

  **Milestone chain.**
  1. *(current)* **Generate the entry header.** Root cause of findings 1
     and 2 together: nothing generates a question's header line, so every
     writer retypes `- **<date> (<provenance>): <question>**` and puts the
     invariant part first. Build a front-door verb (`scheduler ask
     <project> "<question>"`, sibling of the existing `-i`/`_commit-file`
     exports) that takes ONLY the question text and emits the header
     itself: stable short ID, date, provenance derived from the caller,
     question in the bold span. Then "question first" is structurally
     true rather than asked-for, and the summary renderer's job becomes
     "print the bold span," which is the same fix as the render bug.
     Paired lint (`bin/questions-lint.sh`, wired into `scheduler sweep`):
     FLAG any entry whose header was hand-written — no ID, question not
     in the bold span, or header wrapping past one line.
     Includes the standalone render bug it subsumes: `bin/scheduler:2258`
     sets `buf=$0` at the bullet header and never appends, so
     `scheduler status` prints line 1 of each entry and nothing else —
     which on the pre-sweep file was the date and provenance for all ten
     open questions. Fix the accumulation regardless; the generated
     header is what makes line 1 worth printing.
  2. *(next)* **Resolve-and-delete, with the copy handed to
     bibliothecaire.** Decided 2026-07-28: resolved entries are DELETED
     from `QUESTIONS.md`/`BLOCKERS.md`, not left inline and not kept in a
     growing `## Recently resolved` — the backup goes to bibliothecaire,
     whose job is keeping things. This retires the current
     "don't silently rewrite history" convention in
     `.scheduler/QUESTIONS.md`'s header and the `## Recently resolved`
     section of `BLOCKERS.md` *as storage* (both stay only as long as it
     takes to drain them into the archive). Build `scheduler resolve
     <project> <id>`: extract entry, write it to bibliothecaire's archive
     (busy-checked), delete from the live file, append to the existing
     `~/.local/share/scheduler-glance/consumed-receipts.log`. This makes
     the already-queued receipt-grading sweep check DECIDABLE for the
     first time — a line removed with no receipt and no archive copy is
     unambiguously a hand-deletion, where today the same evidence is
     also what a legitimate `/ideate` sweep looks like.
  3. *(later, undecided)* **Cross-document link integrity.**
     `bin/doc-xref-check.sh`, run from `scheduler sweep` next to
     `blockers-freshness-check.sh`: resolve every
     `FOCUS.md`/`QUESTIONS.md`/`BLOCKERS.md`/`DESIGN-NOTES.md` reference
     of the form `<file> <date>` or `<file> <date> "<title>"` against the
     target file, and — once step 2 exists — against the archive too, so
     a pointer to an archived entry RESOLVES instead of dangling. Two
     live dangling references found 2026-07-27, both verified against
     `HEAD`, neither noticed by anything: `BLOCKERS.md` cited a
     "`_paced.conf` dirty-conf question already in `.scheduler/
     QUESTIONS.md` (2026-07-27)" and the stranded-`paced/<date>`-branch
     backlog item cited "`.scheduler/QUESTIONS.md` 2026-07-27 for the
     full incident writeup." Neither exists. Must exit 3 and say
     `check is BLIND` on a parse failure, per the lesson
     `blockers-freshness-check.sh` already learned the hard way — a
     xref checker that silently finds zero references reads as "no
     dangling links."
  4. *(not queued)* Generalising the regulator past these three files
     (reports, DESIGN-NOTES entries, conf comments). Real, but nothing
     has been bitten there yet; don't build ahead of evidence.

  **The two failure modes this session, named (2026-07-28, human-directed).**
  Naming them is the point — an unnamed failure mode recurs because
  nobody can say "that's the one again."
  - **"Layer not retired."** A defect gets a new layer while the old
    layer stays live and keeps producing it. Instance: the unreadable
    QUESTIONS.md was "fixed" on 2026-07-27 by adding a prose convention
    to the file header, without deleting anything. It lasted one day.
    Then `scheduler ask` was built on 2026-07-28 — and the FIRST version
    of that build committed the same sin, shipping the generator while
    leaving four separate documents still instructing agents to
    hand-append the retired format. Caught by Zach, not by any check.
  - **"I didn't check."** A claim about machine state is quoted from a
    document instead of re-probed, and acted on. Instance: three
    `~/.local/bin` scripts were asserted to be COPIES on 2026-07-26,
    read on 2026-07-27, put to Zach as a real decision, answered — and
    were already symlinks the whole time. `deploy-drift-check.sh` runs in
    `sweep` and knew. One `ls -l` would have shown it. Both filed to
    realisateur under these names.

  **Step 1 is DONE (2026-07-28, built in-session, `e8ccd4d`).**
  **What it retires — named explicitly, because the first cut of this
  build did not and that was the "layer not retired" failure in the act:**
  1. the "Shape rule" paragraph in `.scheduler/QUESTIONS.md` (deleted);
  2. `examples/QUESTIONS.md.template`'s taught format
     `- **YYYY-MM-DD (nightly|bug-sweep): <question>**` (replaced with
     the command);
  3. `examples/bug-sweep.md.template`'s identical hand-append
     instruction (replaced);
  4. `.claude/commands/nightly-batch.md`'s "append the question to
     `.scheduler/QUESTIONS.md`" instruction (replaced);
  5. keyword-sniffing for `resolved|acknowledged` as the way to tell a
     closed entry from an open one, for generated entries — the q-id and
     the section heading now decide it, because sniffing silently ate the
     first real question filed (its text contained the word "resolved").
  Nothing above is left standing beside its replacement.

  `scheduler ask` generates the entry; `bin/questions-lint.sh` FLAGs
  hand-written ones and unstamped state claims, wired into `sweep` in the
  same commit; the renderer prints the bold span instead of line 1. The
  retired prose paragraph was deleted, not left beside its replacement.

  **Step 1b is DONE (2026-07-28, paced cycle).** Built exactly as
  specified below: `lib/check-witness.sh` (the one source for the witness
  dir + `check_witness`, called as the first act of
  `blockers-freshness-check.sh`, `deploy-drift-check.sh`,
  `questions-lint.sh` and of the reader itself) and
  `bin/check-witness-lint.sh` (`NEVER RUN` / `STALE`, exit 0/1/3), wired
  into `scheduler sweep` as its **tenth and last** pass — last on purpose,
  so the passes that invoke the other checks have already refreshed their
  witnesses and a wired check cannot be reported stale by the sweep that
  just ran it. Grace period `CHECK_WITNESS_STALE_DAYS`, default 2 (sweep
  runs every 15 minutes; 2 days survives a machine being off for a
  weekend without crying wolf). **What it retires:** the interim `else`
  branch described at the end of this entry stays (it catches a *deleted*
  check, which a witness cannot), but the standing assumption that
  "grep for the script name" answers *is this wired* — it does not, and
  this entry said so. Doctrine written up in
  `docs/offline-first-checks.md`, new section, so other projects
  accumulating `bin/*-check.sh` inherit it.
  Verified here (no `--apply`, live crontab untouched): all three reader
  states (`NEVER RUN` on a fresh witness dir, clean after the checks
  actually run, `STALE` against witnesses backdated 5 and 9 days) plus
  every BLIND path (unreadable witness dir, absent `lib/`, no `bin/`,
  glob matching nothing) — each exiting 0/1/3 as documented; all four
  branches of the new sweep pass exercised by running the block's own
  bytes out of `bin/scheduler` against fabricated roots (findings,
  silent-when-clean, BLIND header, `a wired check vanished`); the three
  modified checks diffed **byte-for-byte** against their `HEAD` versions
  for identical output and exit code, so adding the witness changed
  nothing about what they report; re-run under a stripped
  `env -i`/`env -u SSH_AUTH_SOCK` cron-like environment (identical);
  `bash -n` clean on all six files. `shellcheck` is not installed on this
  host.

  **Step 1b as specified (kept for the record) — answers "how do we make
  a built-but-unwired check fail noisily?" — human question, 2026-07-28.** Static analysis cannot
  answer it: grepping for a script's name proves it is *mentioned*, and a
  call site inside a branch that never executes greps identically to a
  live one. What proves wiring is a RUNTIME WITNESS. Build: every check
  in `bin/` touches
  `~/.local/share/scheduler-checks/<name>.lastrun` as its first act, and
  a `sweep` pass FLAGs any `bin/*-check.sh`/`*-lint.sh` whose witness is
  missing or older than N days — "this exists, nothing has run it since
  <date>." That is the same dead-man-switch shape as `EXPIRY_DAYS`, which
  this repo already trusts for jobs, applied to checks. It catches both
  never-wired and silently-unwired-later (a `sweep` pass deleted in a
  refactor), which is the failure `blockers-freshness-check.sh` had for
  two days and nothing reported. Interim measure already in place:
  `sweep`'s new `questions-lint` pass has an `else` branch that prints
  `MISSING or not executable -- a wired check vanished` rather than
  silently skipping, so at least deletion is loud today.

  **Blockers on step 1 (the current step).**
  - None human-only. Step 1 is buildable now, entirely inside this repo.
  - Step 2 has one, and it is NOT scheduler's to decide: **bibliothecaire
    must say what shape it wants the archive in** (files committed into
    its own repo under a path it owns, vs. an ingest command it exports).
    Cross-write DEFERRED 2026-07-28 — `check-project-busy bibliothecaire`
    reported `BUSY: interactive session (pid 810045)`, so the question
    was not written into its `.scheduler/QUESTIONS.md` this pass. Carry
    it to the next one.

- **2026-07-27 (`/ideate`, human-directed): four standing questions
  ANSWERED — the four below are decisions, not proposals; build them.**
  This pass cleared `.scheduler/QUESTIONS.md` down to what is still
  genuinely open. Each item names the question it consumed.

  1. **~~Symlink all three installed wrappers~~ — ALREADY DONE; the
     question was stale and should never have been asked.**
     `ls -l` on 2026-07-28 shows all four counterparts
     (`usage-paced-runner.sh` 07-26 23:56, `scheduler-dev-cycle.sh` and
     `usage-gate.sh` 07-27 00:47, `scheduler` 07-20) are symlinks into
     the checkout. `installed_scripts()` in `bin/scheduler` says the same
     and records that `deployable_scripts()` + `scheduler pacing deploy`
     were retired 2026-07-27 for exactly this reason. So the 2026-07-26
     entry's claim was true when written and false by the time it was
     read, and a human decision was spent on a non-question. Nothing
     caught it although `deploy-drift-check.sh` runs in `sweep` and knew.
     Mechanism built in response, same day: `bin/questions-lint.sh` FLAGs
     any entry asserting machine state without a `verified <date> via
     <command>` stamp. Filed to realisateur as an ecosystem failure mode
     (detector output and prose claims never meet) and to senechal as a
     machine-state correction. Original text kept below for the record:
     **Symlink all three installed wrappers** (consumed: 2026-07-26
     "should the installed COPIES become symlinks?", option (a)).
     `ln -sfn "<checkout>/bin/<name>" ~/.local/bin/<name>` for
     `usage-paced-runner.sh`, `scheduler-dev-cycle.sh`, `usage-gate.sh`.
     What this fixes, verified before the decision, not assumed: the copy
     install resolves the runner's repo from its own path, gets
     `~/.local`, finds no git dir and skips the auto-pull entirely — 0
     `PULL` lines in 1633 lines of `run.log`, plus 11 `[legacy absolute
     path]` fallbacks. Rejected (b) "keep copies as a manual deploy
     gate": the gate Zach actually wants is the dirty-tree refusal below,
     not a stale-copy accident. **Sequencing (human-directed):** this is
     what makes the BLOCKERS.md "gate it" answer load-bearing —
     symlinking makes every commit live instantly, so the
     `usage-paced-runner.sh` dirty-tree refusal should land FIRST or in
     the same change. Machine-wide config: `notify-senechal` on flip.
  2. **`USAGE_CEILING=0.92` becomes the committed value** in
     `schedule/_usage.conf` (consumed: 2026-07-26 "the live ceiling is
     set somewhere I can't see or edit"). Intermediate, deliberately:
     0.99 was a hand-set push toward a quota deadline and leaves no
     headroom; 0.85 returns HOLD at the ~90% 7d utilisation observed when
     the question was written. Not per-host — no evidence dexter needs a
     different ceiling yet, mechanism exists if that changes. **Second
     half is human-only and NOT done by this pass:** the ambient
     `USAGE_CEILING=0.99` lives outside this repo (a `crontab -e` or a
     shell/wrapper export) and env still outranks the conf by design, so
     until Zach drops it the conf is decorative and live pacing is
     unchanged.
  3. **`EXPIRY_DAYS` keeps wall-clock; expired-without-ever-having-run
     becomes a distinct, louder state** (consumed: 2026-07-27
     "should EXPIRY_DAYS keep measuring wall-clock?", option (c)).
     Rejected (b) "pause the lease while the gate HOLDs": it makes a
     safety mechanism's clock depend on another subsystem's state.
     Rejected (a) "visibility only": true as far as it goes, but it does
     not distinguish the 07-19-cutoff case where `chezz-bug-sweep`,
     `vkv-inventory-bug-sweep` and `vkv-inventory-nightly-batch` burned
     an entire 7-day lease while BLOCKED FROM RUNNING, expired having
     produced nothing, and stayed dark 8 days. Build: track whether a
     lease saw any successful run; if not, expiry emits a separate state
     that survives in `scheduler` glance/blockers rather than only a
     transient `notify-send` + a manually-run `scheduler sweep` — the
     transience is why nobody noticed for 8 days.
  4. **The non-hardware-on-dexter test is RETIRED; pin-by-need stands**
     (consumed: 2026-07-25 wtul dexter deploy-key entry + its secondary
     question). Only hardware-pinned projects go to dexter. wtul stays on
     mandark (`wtul|1|2|` in `_paced.conf`, already restored). Drop
     wtul's block from `schedule/_paced.dexter.conf` and the deploy-key
     checklist with it; **no GitHub-UI step is needed** — the
     `dexter-wtul-deploy` key was generated on dexter but never added to
     GitHub, so nothing is authorized and nothing needs revoking, only
     the unused local keypair + `~/.ssh/config` block cleaned up on
     dexter. That cleanup is a dexter-side step, not mandark's.

- **2026-07-27 19:18 (via `scheduler -i`):** senechal QUESTIONS.md (2026-07-24) has an open Zach reply asking: is the still-unconfirmed 'roman-named for vaporwave' naming question actually a memory leak from svc-vaporwave's account encapsulation -- i.e. does scheduler know about its own cross-user (zach vs svc-vaporwave) and cross-host role, or is this a stale comment predating a move? Worth a check on scheduler's side; senechal has no mechanism to inspect scheduler's own account-model assumptions.

- **2026-07-27 14:56 (via `scheduler -i`):** had a merge conflict while editing blockers, presumably because it only holds scheduler busy not all projects which is correct. hopefully this gets addressed with the new front door

- **2026-07-27 14:45 (via `scheduler -i`):** failure mode is *zach distracted* meaning projects get stalled behind a hardware gate e.g. and spend calls navel gazing if blocked by milestone rules, or at best developing deep vision. meanwhile, serendipity is a logic by which these projects should always sleep with one eye open; sometimes another project uses the printer, or crt, unblocking afterall. bibliothecaire maybe has the philosophy or this is genuine zach novelty

- **2026-07-27 (live session, human-directed): `scheduler sweep` should grade the receipt log `collect-feedback.sh` now writes.** Built this session (`72f48c0`): every real `--consume` appends a line (timestamp, file, section, count) to `~/.local/share/scheduler-glance/consumed-receipts.log` instead of silently deleting entries with no trace. That's the answer key; nothing reads it yet. Next piece: a `sweep` check comparing a `QUESTIONS.md`/`BLOCKERS.md` git history (line removed between two commits) against the receipt log's timestamps for that file — a removal with no matching receipt in the surrounding window is a candidate hand-deletion of an answer nothing ever consumed, worth a loud flag, not a silent pass. Scope note: only meaningful for the *automated-consumption* pattern (most projects' `QUESTIONS.md`, consumed by their own `/nightly-batch`) — scheduler's own `.scheduler/QUESTIONS.md` is explicitly hand-maintained by its own header and hand-deletion there is correct, not a bug, so the check needs to know which convention a given file follows before flagging anything.

- **2026-07-27 (`/ideate`, human-directed): retry orphaned `paced/<date>` merges against current `main` instead of forking fresh each day.** `bin/scheduler-dev-cycle.sh` only merges a finished cycle into `main` when `main` is clean/checked-out; when it isn't (a human mid-edit, another sweep in flight), the cycle falls back to leaving the branch unmerged — safe, but nothing ever retries it, and the next day's `git worktree add -b paced/<newdate> ... main` forks from `main` again, permanently orphaning the stranded tail. Live damage: `paced/2026-07-25` (7 commits) and `paced/2026-07-26` (7 commits) both stranded, both now conflicting against `main` (need a real merge, not a fast-forward) — see `.scheduler/QUESTIONS.md` 2026-07-27 for the full incident writeup. **Decided:** don't statically fork the new day's branch from the last unmerged branch. Instead, each cycle should mechanically attempt to merge any still-unmerged prior `paced/<date>` branch(es) into current `main` first (retrying, not abandoning after one skipped attempt), since `main` is always the reconciled claude+human line and should be treated as the thing later work reconciles against — "attempt to reconcile [against current main] every time, mechanically... follow the leader." Full rationale: `DESIGN-NOTES.md` 2026-07-27. Immediate human-only prerequisite: the two already-stranded branches above still need a manual merge/cherry-pick/abandon call before this mechanism has anything live to prove itself against — that recovery call is not part of this backlog item.

- **2026-07-27 11:03 (via `scheduler -i`):** REQUEST: a `scheduler migrate-subdir <project>` verb, to finish the .claude -> .scheduler migration for the 8 projects still on the default. Filed by senechal 2026-07-27, which just did its own migration and hit every trap. WHY YOURS, not senechal or realisateur: you own SCHEDULER_SUBDIR and resolve_focus_path (bin/scheduler:505), AND you own the registry, so you are the only place that already knows every project repo path, conf file and symlink pair. senechal remedy is hardcoded to schedule/senechal.conf + focus/senechal.md + questions/senechal.md and CANNOT serve the other 8 without re-deriving your config -- the exact defect already filed against this ecosystem. Pairs with the lint row filed to realisateur (FLAG any project whose declared subdir does not match disk): detection plus remediation. Your own restamp-discipline.sh header says it -- "Detection is not propagation", hygiene-lint complained into a log for a day while three projects sat stale. REFERENCE IMPLEMENTATION, tested and working, 299 lines: senechal remedies/scheduler-subdir-migration.sh at senechal 6d0c266. Read it WITHOUT needing a senechal checkout -- the bare remote is on this host and this command is verified working: git --git-dir=/home/zach/git-remotes/senechal.git show 6d0c266:remedies/scheduler-subdir-migration.sh . Local checkout path if you have one: /home/zach/Documents/Projects/senechal/remedies/scheduler-subdir-migration.sh . WHAT IT COST TO GET RIGHT -- do not re-learn these four: (1) ATOMICITY. A partial move is a silent outage: chezz moved its own files 2026-07-24, correctly refused to edit your repo, and both symlinks dangled a day with `scheduler status chezz` reporting "no FOCUS.md found". The 5 steps -- conf, git mv, project doc refs, consumer path literals, sync-crontab.sh --apply -- must land in one pass or not at all. (2) A .claude/FOCUS.md SYMLINK BRIDGE DOES NOT WORK as a transition aid, because your own cmd_idea writes via `mv "$f.tmp" "$f"`, which replaces a symlink with a regular file and silently splits the two copies. (3) MY OWN BUG, the one worth copying the fix for: the enable helper ignored exit status, so when sync-crontab.sh --apply correctly refused a dirty schedule/ the script printed "Applied." and exited 0 on a half-finished migration -- an exit-0 no-op in the very script meant to prevent half-finished migrations. Make every step die loud; the verify pass is a backstop, not the primary guard. (4) VERIFY MUST STRIP COMMENTS before grepping for stale path literals -- mine FLAGged a file that was already correct because its header quoted the old path twice while explaining an unrelated bug. Also useful: preconditions refuse to start unless all touched trees are clean, targets are non-BUSY, and check-project-busy is actually on PATH; roots are env-overridable purely so the split-state branch can be tested against a fixture, since that state cannot be reached safely by hand. Suggested close check for the whole migration: `scheduler migrate-subdir <p>` then a verify that exits 0 for all 18 registered projects.

- **2026-07-27 10:33 (via `scheduler -i`):** Finding from senechal 2026-07-27 -- request is one exported command, not a convention. VERIFIED SURVEY of all 18 registered confs: 9 declare SCHEDULER_SUBDIR=".scheduler" (abletim, aedile, bibliothecaire, chezz, quatre-vingt-douze, realisateur, scheduler, secretaire, wtul), 9 still default to .claude (crt, gardien, groc-mangr, home-assistant, nine-speakers, senechal, sequestria, vim-arcade, vkv-inventory). Zero declared-vs-disk mismatches -- your config is single-sourced and CORRECT. The defect is downstream: consumers do not read it, they re-derive it by guessing. realisateur/bin/notify-senechal.sh:100 hardcodes .claude/FOCUS.md; closeout-lint.sh:45 hardcodes .scheduler/; incubation-audit.sh:85-88 ignores the conf and probes one then the other; milestone-audit.sh, weight-audit.sh and steward-survey.sh each re-implement the same conf read correctly -- three copies of one rule. That is BUILD-DISCIPLINE "config read from one source, not retyped per file" violated at ecosystem scale rather than inside one repo. WHY THIS IS YOURS: you own SCHEDULER_SUBDIR and resolve_focus_path (bin/scheduler:505), so you are the only place that can hand out the answer. REQUEST: export resolve_focus_path as `scheduler _focus-path <project>`, precedent being _commit-file which you already export for the vim auto-commit hook (bin/scheduler:2230). Without something callable, "stop re-deriving" is prose and prose cannot enforce -- every consumer keeps guessing and the half-finished migration stays load-bearing. Note the payoff is bigger than tidiness: with one resolver a straggler becomes HARMLESS and migrating any of the remaining 9 is a one-line conf flip; today it is a cross-repo atomic operation because five scripts guess independently. Suggested close check: grep the ecosystem for FOCUS.md path literals returns only bin/scheduler itself. Motivation for the 9 to move at all, from your own schedule/chezz.conf:28-32: FOCUS/QUESTIONS under .claude/ hit the unattended sensitive-file write gate, confirmed path-based by a controlled A/B test -- so the 9 unmigrated projects with unattended jobs that write their own scope file are impaired right now.

- **[DONE 2026-07-27, paced cycle 3 — both asks built and verified]**
  `bin/blockers-freshness-check.sh` now (1) matches the `## Recently
  resolved` stop heading and every `## <project>` heading as a WHOLE LINE
  and only outside fenced code blocks, and (2) exits **3** with a loud
  `PARSE FAILURE ... reports UNKNOWN` message when it finds zero project
  sections in a non-trivial file, instead of printing `0/0 ... flagged`
  and exiting 0. `bin/scheduler`'s sixth sweep pass distinguishes exit 3
  (`CANNOT READ BLOCKERS.md -- check is BLIND`) from a staleness finding,
  so the blind case can never be read as a statement about the blockers.
  `SCHED_ROOT` became env-overridable so the parse paths are testable
  offline. **Verified by reproducing the exact ec89b84 corruption shape in
  a fixture** — a line reading ``## Recently resolved` or deletes it.``
  ahead of the real heading: pre-fix code prints `== summary: 0/0 active
  project section(s) flagged ==` and exits 0, post-fix finds both sections
  and exits 1. Plus: a genuine early full-line stop heading → exit 3
  UNKNOWN; headings inside a fenced block correctly ignored; the real
  BLOCKERS.md still reports 3/9 flagged; `bash -n` on both files and a
  full `scheduler sweep` run end to end. (shellcheck is not installed on
  this host — `bash -n` only.) **What it retires:** the prefix-matching
  heading rules (both of them) and the silent zero-sections success path.
  Proposals 1 and 2 of the sibling entry below (the writer-side watcher
  refusal and machine-append anchoring) are still OPEN — this is only the
  reader-side guard.

- **2026-07-27 10:2x (interactive session, closed via `/cloture`):** a
  maintenance pass off `scheduler sweep` that turned into a lockout audit.
  Landed, all pushed to `origin/main`: `8a3450d` (QUESTIONS: two design
  calls), `dd086bb` (`reconcile_prior_cycles()` + `tests/reconcile-witness.sh`),
  `3f97df4`+`ab4dcb8` (recovered 14 stranded commits), `ca02931` (self-dev
  cycle joins the shared lockout; `lib/registry-lock.sh` +
  `tests/registry-lock-witness.sh`), `6fc2d4f` (activity-based deferral).
  Cross-project: `c49c70d` in realisateur, `606f07c` in bibliothecaire.

  THE THREAD, because the individual fixes matter less than what connected
  them. A paced cycle that declined to merge (dirty tree, or a failed push)
  left work nothing ever revisited — the next day's branch forks from
  `main`, so the tail was orphaned permanently: 14 commits across
  2026-07-25/26, verified file-by-file as NOT superseded. The fallback was
  correct in the moment and permanent by omission. Pulling that thread:
  the dirty-tree test was standing in for "is a human here", because
  `bin/scheduler-dev-cycle.sh` had NO registry participation at all — the
  scheduler enforced its lockout on ~20 projects and exempted the one job
  that edits the scheduler. And underneath that, the lockout was failing
  OPEN ecosystem-wide: `session-marker.sh` recorded `${PPID}`, which dies
  with the hook, so `check-project-busy` answered "free" for any repo with
  a live human in it. Three layers, one root: a guard that was never
  wired to the thing it guards.

  [batch] `bin/scheduler:2024` prints a `WARNING: local commit made but NOT
  pushed` line out of the last-run slice with no re-probe. For an EXPIRED
  job that slice is frozen forever, so `scheduler status vkv-inventory`
  still reports a 2026-07-20 warning whose commits reached `origin/main`
  days ago — it cost this session a wrong diagnosis before the claim was
  re-probed. The 2026-07-25 last-run-slice fix does not cover the dormant
  case, and the `CRITICAL` line below it IS status-gated while this one is
  not. Name proposed: STALE-BY-RESOLUTION (sibling to the sweep's
  STALE-BY-DRIFT). Fix shape: make the warning unquotable — reachable only
  via a re-probe returning resolved / unpushed / `unverifiable:<why>`,
  ref-agnostic (check ancestry against any `refs/remotes/*`; the warning
  named `drilldown-browse-redesign` while the commits landed on `main`,
  which is exactly what misled this session).

  [re-routed 2026-07-27 10:31 — NOT actionable from here, do not pick up]
  The row below was filed in the wrong backlog. Scheduler's own cycle is
  hard-barred from touching any file outside this repo
  (`bin/scheduler-dev-cycle.sh:282,284`) and realisateur's nightly is told
  not to act on other projects' FOCUS items unprompted — so it had no
  permitted reader here. Re-filed through the front door into
  realisateur's inbox: `bb542f0` (the doctrine proposal) and `f73e5c6`
  (a /cloture mechanism request — that filing must VERIFY the destination
  has a reader that is both permitted and alive, since this row is the
  live exhibit of it not being verified). Kept, struck, rather than
  deleted: the misfiling is the evidence.

  [batch] DEFERRED CROSS-WRITE, realisateur was BUSY: propose failure
  pattern 16 in `BUILD-DISCIPLINE.md` — *a correct refusal that nothing
  retries*. Distinct from pattern 8 (warn-then-continue proceeds; this one
  correctly STOPS, and the stopping is the loss) and from 13 (that is a
  decision with no dispatch path; this is finished WORK with none). Live
  exhibits from this session alone: the dirty-tree merge fallback, the
  failed-push path, and — the reason it deserves doctrine — every one of
  them logged loudly and was still lost, so "it failed loud" is not
  sufficient. Rule shape: a fallback that declines to act must name what
  retries it, or it is a dead end wearing a safe fallback's clothes.
  Second deferred write to the same repo: realisateur's own
  `.scheduler/FOCUS.md` has no record of `c49c70d`.

- **2026-07-27 01:49 (via `scheduler -i`):** (from realisateur /ideate 2026-07-27, follow-up to the two guards filed earlier tonight) THIRD proposal, and this one is the reason the other two matter: bin/blockers-freshness-check.sh was silently blinded for two days and reported a clean summary the entire time.

WHAT HAPPENED. ec89b84 (chezz's machine-append, 2026-07-25) inserted its "## chezz" section at the first "## " it found in BLOCKERS.md. That occurrence was inside the header's own explanatory sentence -- the one that tells the reader where resolved entries go, and does so by naming the heading: "...actually moves it down into `## Recently resolved` or deletes it."

The header got cut mid-clause and its tail was left wearing a heading it never had: a second "## Recently resolved" at line 91, 372 lines ahead of the real one at line 463.

blockers-freshness-check.sh scopes itself to the active section as "everything before the first ## Recently resolved" (its own comment, line 41; the awk stops on /^##[[:space:]]+[Rr]ecently [Rr]esolved/). From ec89b84 onward that was line 91. Every project's real blockers -- scheduler, aedile, wtul, crt, vkv-inventory, gardien, senechal, realisateur -- sat below it, in what the script understood to be already-resolved history.

MEASURED, NOT INFERRED. Same script, only the file differs:
  corrupt file:  == summary: 0/0 active project section(s) flagged ==
  repaired file: == summary: 4/9 active project section(s) flagged ==
                 (crt, realisateur, senechal, vkv-inventory all STALE-BY-DRIFT)

Zero out of zero. Not an error, not an empty result -- a clean bill of health, in the standard format, from a check that had been blinded. The corruption's first casualty was the only script watching for it.

ASKED FOR, two changes, both small:

1. A section-scoped reader that finds ZERO sections must report UNKNOWN or FATAL, never zero findings. A file known to have sections and suddenly having none is a parse failure wearing a passing summary. Concretely: if $projects is empty, or if the active section is empty while the file is non-trivially sized, exit nonzero with a loud message rather than printing "0/0 ... flagged". Same reasoning as realisateur BUILD-DISCIPLINE pattern 14's UNKNOWN rule, applied here to the script's own scoping rather than to its domain.

2. Anchor the stop-heading match at both ends -- /^##[[:space:]]+[Rr]ecently [Rr]esolved[[:space:]]*$/ -- and skip fenced code blocks. The current prefix match accepts the header's own sentence about the format. Same root cause as proposal 2 filed earlier tonight (machine-append anchoring on a "## " inside prose): a structural marker matched by a rule that the file's own documentation of that marker can satisfy. The writer and the reader made the identical mistake 24 hours apart without knowing about each other, which is better evidence that the matching rule is wrong than either implementation being at fault.

Worth noting for sequencing: proposal 1 (watcher refuses conflict markers / duplicate ## headings) would also have caught this one, since the duplicate "## Recently resolved" is exactly a duplicate heading. Proposals 1 and 3 are independent guards on the same failure -- a writer-side refusal and a reader-side honest UNKNOWN -- and both are worth having, because the reader-side one also covers damage that arrives by a route the watcher never sees.

Repaired by hand in 1a6bc0a (realisateur /ideate, Zach-directed). Recorded as realisateur BUILD-DISCIPLINE pattern 15, "a file's prose about its own structure gets parsed as its structure."

- **2026-07-27 01:42 (via `scheduler -i`):** (from realisateur /ideate 2026-07-27, Zach-directed) Two watcher/collector guards, both with a live exhibit in scheduler's own BLOCKERS.md today. Filed through the front door because both are scheduler engine, not realisateur's to edit.

PROPOSAL 1 -- the autocommit watcher must refuse a file it cannot safely adopt.

Live exhibit: 0e9b6a6, "Human edit via scheduler: BLOCKERS.md (2026-07-27T01:15)", 106 insertions and zero deletions. The ~:30 watcher caught BLOCKERS.md in the middle of a live vimdiff merge and committed it under Zach's name. What it adopted: two unresolved conflict blocks (<<<<<<< /tmp/vzTGDTh/5 ... >>>>>>>) fencing two of Zach's own answers, and a verbatim duplicate of the whole ## gardien / ## senechal / ## realisateur tail -- an answered copy plus a blank-slot copy.

The duplicate is the part that bites scheduler specifically: it put a SECOND "## realisateur" heading in the file, and collect-feedback.sh --section matches on that heading. That is the same shape as the 2026-07-26 empty-consume bug (fixed in bb5c762), arriving by a different route -- not a bare ">" being misread this time, but a whole duplicate section competing for the same anchor.

Asked for: before committing, the watcher refuses (and says so loudly, leaving the tree dirty for the human) if the file contains a conflict marker at line start (^<<<<<<< , ^=======$, ^>>>>>>> ), or contains a duplicate "## " heading. Both are cheap greps. A dirty tree the human comes back to is strictly better than a corrupt file committed under their name -- and this repo's own doctrine already says a dirty tree at exit is a failed run, not a handoff.

Note the asymmetry that makes this worth doing: the watcher exists so a human's uncommitted edits are never lost. Refusing on these two signatures does not lose anything -- the edits stay in the working tree, exactly where the human left them.

PROPOSAL 2 -- machine-append must not anchor on a "## " that lives inside prose.

Live exhibit: ec89b84, "BLOCKERS.md: machine-append a chezz section (chezz nightly 2026-07-25)". It inserted the ## chezz section INSIDE the header paragraph's own sentence, because that sentence contains the literal string `## Recently resolved` -- the header is explaining to the reader where resolved entries go. The append anchored on that occurrence.

Damage: the header sentence was truncated at line 12 and its tail wore a fake "## Recently resolved" heading at line 91 -- a second heading with that exact name, sitting AHEAD of the real one, for two full days. Anything that scans for the Recently-resolved boundary would have found the wrong one. Repaired by hand today in 1a6bc0a (realisateur /ideate, Zach-directed); the fix here is so it cannot recur.

Asked for: the heading matcher requires a line that is exactly "## <PROJECT_KEY>" -- start of line, nothing before it, and not inside a fenced code block or a backticked span. BLOCKERS.md's own header already states this contract in prose ("Each project's heading must be exactly ## <PROJECT_KEY>"); the request is to make the matcher agree with the file's own stated rule.

Both are small. Both have already been paid for once.

- **2026-07-26 22:30 (via `/nightly-batch`, paced cycle): the live
  dispatcher runs a hand-copied, one-commit-stale script, and being a copy
  silently disabled its own auto-pull. Detection BUILT this cycle; the
  one-line fix is human (see `.scheduler/QUESTIONS.md`, same date).**
  Found while looking for the next milestone item, verified live, not
  hypothetical: `~/.local/bin/usage-paced-runner.sh` — the file cron
  executes every 5 minutes — is a **copy**, not a symlink into the
  checkout, and matches `d431e8b` (2026-07-24) rather than `origin/main`.
  Two consequences, both silent until now: (1) commits to
  `bin/usage-paced-runner.sh` never go live (today's expiry-skip work
  included); (2) the auto-pull built 2026-07-24 — the mechanism that was
  supposed to make a commit on one host reach the other — derives its repo
  from `readlink -f "$0"/..`, which under a copy install is `~/.local`,
  not a git checkout, so the entire pull block is skipped. Witness: **0
  `PULL` lines in all 1633 lines** of that job's `run.log`, and 11
  `legacy absolute path` lines (the runner falling back to a hardcoded
  `_paced.conf` path because it can't find a repo — the same defect the
  2026-07-25 fable-review item names). `scheduler-dev-cycle.sh` and
  `usage-gate.sh` are copies too; they happen to match `origin/main`
  today and will rot the same way with nothing watching.
  **BUILT (2026-07-26 paced cycle):** `bin/deploy-drift-check.sh` —
  offline, read-only, zero-AI, same signals-not-verdicts convention as
  `blockers-freshness-check.sh` — compares every `~/.local/bin/<name>`
  against `bin/<name>` at a git ref (`DEPLOY_REF`, default `origin/main`
  → `main` → `HEAD`), reporting DRIFT (naming the commit the copy *does*
  match and how many later commits never went live), COPY (matches today,
  nothing keeps it in sync), or BROKEN (dangling symlink); symlinks pass
  by construction. Wired into `cmd_sweep` as an eighth pass, so it runs on
  sweep's own independent cron tick. Worktree-aware: `fix:` lines point at
  the main checkout, never at the throwaway paced worktree the cycle runs
  from. It never writes under `~/.local/bin` — converting the three copies
  to symlinks is a human step, and whether that's even wanted (auto-deploy
  on commit vs. a deliberate manual deploy gate) is the open question
  filed in QUESTIONS.md.

- **[shipped-inline] [iface: answer-session] 2026-07-26 (interactive,
  human-directed quickfix) — `scheduler -q` with no project now prints a
  questions overview instead of a bare project-name dump. Recorded as a
  STATED ACCRETION-FREEZE EXCEPTION, not silent accretion.** What
  shipped: every project with any open questions as `unanswered/total`,
  `*` where the file changed since you last opened it, unread sorted
  first, plus a one-line count and a "nothing open:" tail. Verified by
  running it (counts match the glance's QUESTIONS column exactly), and
  each branch exercised against a scratch `SCHED_ROOT` — unread-star,
  all-replied, and the no-questions-anywhere empty state.
  - **The freeze it crosses, named plainly.** The milestone declared
    earlier the same day says "no view gains a legend line or new verb —
    new needs go into the spec," and slates `questions` itself for
    retirement to a one-line redirect stub. This added a sub-view and two
    legend lines to exactly that surface. Human-directed and dated here so
    the redesign counts it as debt to fold in, not as an existing view to
    preserve. Revert with `git revert <sha>` if the freeze should hold
    strictly; the FOCUS entries are worth keeping either way.
  - **(re-arrival: 2026-07-20, 2026-07-26, 2026-07-26)** — shape stable
    across all three, per realisateur/PRECIPITATION.md signal 1: item 0's
    "one file I actually read" and the blockers-as-computed-view design
    (2026-07-20, which already concluded questions and blockers are one
    list filtered two ways), realisateur/PLAYBOOK.md Play 5 #2 (the
    ranked answer-session surface — the only play in that audit acting
    directly on the rate-limiting enzyme), and this ask. Promotion
    passes over nothing: it did not jump a queued item, it consumed
    interactive time the freeze had reserved for the redesign.
  - **Names what it retires:** `require_project`'s bare project-list dump
    for `-q` (gone, that path no longer runs), and the duplicated
    question-counting awk — `questions_counts()` / `questions_unopened()`
    are now one implementation shared with `cmd_glance`, so the two views
    cannot drift about what counts as an open question. At target state
    this view retires INTO the consolidated `blockers` view; it must not
    survive alongside it as a sixth surface.
  - **Not built, stays queued in the spec above:** ranking by released
    work, and standing-policy vocabulary so a `yes` is durable rather
    than per-question. 105 unanswered across 17 projects at the time of
    writing — the count is the argument for the ranking half.

- **[batch] [iface: sweep-attribution] 2026-07-26 (interactive /ideate,
  human-approved) — MERGED build item: the sweep-attribution regulator,
  one pass, four pieces.** Subsumes the 2026-07-26 21:22 and 21:56
  entries below (same-shape re-arrival per realisateur/PRECIPITATION.md
  signal 1; merged so they can't be built separately and half-fixed).
  **FIFTH OCCURRENCE, 2026-07-27 00:00, and it argues for the build order
  below rather than against it:** the `*/15` sweep tick adopted THIS
  session's in-flight FOCUS.md edit (the new Shared-host footprint
  section) and committed it as `Human edit via scheduler: FOCUS.md` under
  `hf7y <dangerpine@gmail.com>` — 51 lines an agent wrote, signed as the
  human's, and pushed. Notable because it happened ~20 minutes AFTER the
  human-presence marker guard shipped in this same session: no marker was
  held, because this session started before the SessionStart hook was
  installed and never opened a scheduler file through the front door. The
  guard behaved exactly as documented; the point is that item (1) is the
  only one of the four that needs to detect nothing at all. Do it first
  and unconditionally, as already written.
  Build order inside the pass: (1) honest default commit message +
  distinct committer identity at the one place the default is set
  (`bin/scheduler`, ~line 706) — first and unconditional; (2) mtime
  quiescence guard (`find -mmin +N`) — covers non-cooperative writers;
  (3) job-side `.interactive`-marker probe in `lib/sweep-loop-common.sh`
  (kill -0 on the pid field, never flock; MUST carry the starvation cap
  — after N deferrals proceed loudly); (4) `scheduler -i --agent <name>`
  provenance variant so precipitation-scan's HUMAN/INBOX classification
  stays exact. Full design detail stays in the two subsumed entries —
  this entry is the dispatch unit, those are the spec.

- **[batch] [iface: usage-ceiling-conf] 2026-07-26 (interactive /ideate,
  human-approved) — MERGED build item: the usage-ceiling work is ONE
  pass, not three.** Subsumes the 2026-07-26 22:15 two-ceilings split,
  the 2026-07-25 17:06 config-settable-ceiling scoping, and the
  2026-07-26 filed-separately pointer below. One `schedule/_usage.conf`
  with TWO keys (admission ceiling ~0.95 — derived-from-observed-batch-
  size as the named goal — and weekly target 0.99), env-wins precedence,
  per-host override, admission plausibly reading the 5h window, and the
  single-source cleanup naming what it retires (`usage-gate.sh:41`'s
  inline default, the `RUNNER_ENV` retyping). The subsumed entries hold
  the full scoping; this is the dispatch unit.

- **[batch] [iface: crash-durability] 2026-07-26 (interactive /ideate,
  human-approved) — MERGED build item: one guard for crash aftermath,
  both halves, same code site.** Subsumes the 2026-07-26 09:32 entry
  (bootstrap `reset --hard` destroys committed-but-unpushed commits —
  rescue ref `rescue/<JOB_NAME>-<date>` before reset when
  `rev-list origin/$BRANCH..HEAD > 0`) and the 2026-07-26 log-review
  crash-aftermath entry (STATUS=FAILED leaves a dirty worktree the next
  reset wipes — commit-or-stash onto `crashed/<project>/<date>`,
  untracked files included) below. Both live in
  `lib/sweep-loop-common.sh` around the existing stash guard (~line 288)
  and the FAILED path; building one without the other leaves a run's
  work destroyable by the half not built. Name both refs in the report.

- **[batch] 2026-07-26 (interactive /ideate, human-APPROVED — this is the
  `> ` answer to BLOCKERS.md ## realisateur call 4): the catabolic
  worklist from realisateur/PLAYBOOK.md Play 3 — retire ~1,000
  already-self-labeled-superseded lines.** One retirement per pass, each
  commit naming what retires it: `morning-report.sh` + `morning-report.md`;
  `build-services-view.sh` + `services/`; both `overnight-dev.sh` copies;
  the two 162-line loop-script forks (`scheduler-`/`aedile-nightly-batch-
  loop.sh` → 5-line shim; NOTE: gated behind the axis-1 (a) flip above
  for the scheduler one); `sync-crontab.sh`'s dead auto-stagger
  subsystem. (`incubation-audit.sh` is realisateur's own, not this
  repo's.)

- **[batch] 2026-07-26 (interactive /ideate, human-APPROVED — this is the
  `> ` answer to BLOCKERS.md ## realisateur call 3, subset a-c): import
  swaps from realisateur/PLAYBOOK.md Play 2.** (a) symlinks replace
  `scheduler pacing deploy`/`deployable_scripts()`/drift reporting —
  ALSO the safety-gate prerequisite for the axis-1 (a) flip, do first;
  (b) `ccusage` replaces `bin/token-usage.sh`'s 262-line parsing core,
  keeping the ~35-line conf→session-dir mapping; (c) `gitleaks` replaces
  `hygiene-lint.sh`'s hand secret regexes, staying inside the exit-0
  signals-not-verdicts harness. (d) restic/rsnapshot deferred until
  gardien unparks — not approved yet, per the same answer.

- *(subsumed by [iface: usage-ceiling-conf] above, 2026-07-26 /ideate — spec lives here, dispatch there)* **[batch] 2026-07-26 22:15 (human-directed, /ideate) — split the one
  ceiling into TWO numbers: a per-dispatch admission ceiling and a weekly
  target.** Today `USAGE_CEILING` is a single value doing two unrelated
  jobs, and raising it to 0.99 (a9bffa2) to chase the weekly target
  silently degraded the other job. The two intents:
  (1) **Admission ceiling (~0.95, or better: derived).** The question this
  answers is *"is there room for the batch I am about to start to
  FINISH?"* — a batch admitted at 0.98 gets cut off mid-turn when it hits
  the wall, and per the crash-aftermath item below that means a dirty
  worktree and discarded work. This should ideally not be a guessed
  constant but **the size a big batch actually needs** — the data to
  derive it exists (per-cycle utilisation deltas are observable in the
  paced runner log; the evening of 2026-07-26 ran ~2.7 pts/hour sustained
  on the 7d window). Ship a static ~0.95 if deriving is too much for one
  batch, but name the derived version as the goal.
  (2) **Weekly target = 0.99.** The question this answers is *"how much of
  the 7d budget should be spent before it resets?"* Unused weekly quota
  does not roll over, so the target is deliberately near the wall — same
  reasoning that motivated rush-before-reset.
  These are different numbers for different reasons and will diverge
  further (a bigger batch raises #1; #2 stays pinned at ~0.99). Note the
  interaction with **rush-before-reset**: in the final 120 min the
  admission ceiling is what should *still* apply — rush drops the
  even-burn pacing hold, but it must not admit a batch that cannot
  finish. Also note the 5h window: the admission check plausibly needs to
  read 5h headroom, not just 7d, since that is the window that actually
  cuts a running batch off mid-turn. **Build this together with the
  config-settable-ceiling item (2026-07-25 17:06, below)** — that item
  already specifies the conf file, env-wins precedence, per-host
  overrides, and the "name what it retires" cleanup; this one only says
  the conf needs two keys instead of one. Doing them separately means
  shipping a one-key conf and immediately re-cutting it.

- *(subsumed by [iface: sweep-attribution] above, 2026-07-26 /ideate — spec lives here, dispatch there)* **2026-07-26 21:56 (via `scheduler -i`):** ITEM 3 of the sweep-attribution regulator, JOB-SIDE HALF (realisateur built its half 2026-07-26, see below). Zach's framing: "just as likely I am interactively working with scheduler while its batch fires... a way to lock the repo while interacting seems prudent, a default way that requires no human discipline is the way to build." CORRECTION to how item 3 was originally filed: the ecosystem-wide per-project lock ALREADY EXISTS and needs no new infrastructure -- lib/sweep-loop-common.sh keys REGISTRY_LOCK by PROJECT_KEY (not JOB_NAME) in ~/.local/share/scheduler-registry/, and its own comment states that is precisely what makes every tier/job for one project contend for one slot. Every registered project's every job already takes it automatically through that one shared library. So the gap is NOT "build a lock"; it is that the lock is JOB-VS-JOB ONLY and nothing in the system represents a HUMAN. DONE ALREADY (realisateur side, no scheduler change needed): (a) bin/check-project-busy.sh promoted to probe the canonical registry lock first -- it previously scanned only per-job dirs and explicitly EXCLUDED scheduler-registry, re-deriving by directory-name guessing what the registry states canonically; the per-job scan is now a fallback for pre-registry jobs and is skipped when the registry already answered. (b) bin/session-marker.sh + global ~/.claude/settings.json SessionStart/SessionEnd hooks now write ~/.local/share/scheduler-registry/<PROJECT_KEY>.interactive whenever a Claude session starts anywhere under a registered PROJECT_REPO_PATH -- one config, every project, zero per-project scaffolding, zero human discipline, silent no-op for unrelated work on this machine. It lands in the SAME directory as the .active job marker so one place answers "is anything writing to this project right now". CRITICAL DESIGN CONSTRAINT, verified against the hooks reference and by test: SessionEnd is NOT guaranteed to fire on crash or SIGKILL, so the marker must NEVER be an flock held by a detached process -- that would orphan and wedge a project's batch permanently and silently, a silent-failure path introduced to fix a race. Liveness is therefore a PID probe (kill -0), release is only the fast path, and a crashed session's marker reads FREE by construction; negative-tested with a dead pid. WHAT SCHEDULER NEEDS TO BUILD: in lib/sweep-loop-common.sh, after the existing two flocks, probe <PROJECT_KEY>.interactive the same way (kill -0 on the pid field, NOT file existence) and if a live human session holds it, log and exit 0 -- deferring to the next tick. Because that library is the shared entrypoint for every registered project's every job, this is one edit that all projects inherit, matching the same one-place property the REGISTRY_LOCK already has. Deferral is cheap: the paced runner is a rotation, it comes back. MUST INCLUDE A STARVATION CAP: "defer whenever a human is present" means a long interactive session silently starves that project's batch forever, so after N consecutive deferrals proceed anyway and log LOUDLY (warn-then-continue is failure pattern 8, but silent indefinite deferral is pattern 1, which is worse -- the cap is the lesser evil and must be visible either way). ALSO STILL WANTED, and independent of the lock: item 2's mtime quiescence guard, because a lock only protects writers who take it and vim, a raw shell, and `scheduler sweep` itself never will -- lock for cooperative writers, mtime for everyone else, both not either. Live witness the same session: `check-project-busy.sh senechal` correctly reported BUSY from the registry lock while senechal-nightly-batch was mid-run (pid 96695, started 21:55:03), and realisateur DEFERRED a cross-write it was about to make into senechal's FOCUS.md as a result -- the guard working end to end, against a real job, before this was even finished.

  - **ADDED 2026-07-26 (interactive, human question: "is there something
    that locks a project while I have QUESTIONS.md open?"): the marker is
    keyed by SESSION CWD, so editing a project's questions THROUGH the
    scheduler's aggregation symlinks marks the wrong project.**
    `questions/<p>.md` and `focus/<p>.md` are symlinks into each project's
    own checkout; vim resolves them and the autocommit hook correctly
    commits into THAT project's repo — but a session (or plain vim) rooted
    in the scheduler repo writes `scheduler.interactive`, never
    `<p>.interactive`. So the one workflow the aggregation folders exist
    to enable — sit in scheduler, answer three projects' questions — is
    exactly the one the human-presence marker cannot see, and each of
    those three projects reads FREE while you are typing into it.
    Verified 2026-07-26 by reading both scripts plus an end-to-end
    acquire/probe/release against a live pid (the mechanism itself works;
    this is a keying gap, not a bug in it).

  - **CLOSED (front-door half) 2026-07-26, human-directed: "can't I lock a
    project when I open its .md file via scheduler?"** — yes, and the
    front door is the one writer that always knows which project's file it
    is about to open. `bin/scheduler` now stamps `<p>.interactive` from
    the FILE's project (`project_for_path()` resolves symlinks, so
    `questions/wtul.md` marks **wtul**, not scheduler) immediately before
    `exec "$EDITOR"` — and because `exec` REPLACES the process, the pid in
    the marker *becomes the editor's own pid*. The marker therefore dies
    exactly when your editor does: no trap, no cleanup, no SessionEnd
    equivalent to miss, and no way to leave a lock holding after a crash.
    That is the same self-healing property session-marker.sh chose, gotten
    for free rather than defended. Covers `-q`/`-f`/`-r`/`-p` and both
    jump paths; `-b` (BLOCKERS.md) is cross-project and holds nothing.
    Reader half shipped in the same pass: `cmd_sweep` now defers its
    auto-commit for any project with a live holder (item 3's "HONOR THE
    EXISTING LOCK", scheduler-side) and prints what it held. No starvation
    cap needed there — sweep only ever commits, so deferring leaves the
    file exactly as the human has it, and the next 15-minute tick picks it
    up once the editor exits. The vim hook's own commits are deliberately
    unaffected: that path has real provenance, sweep does not.
    - **Witnessed, not assumed** (isolated throwaway repo + scratch
      `SCHED_ROOT`, so no real project was risked): live marker → sweep
      printed `deferring auto-commit … (pid N)` and left the file dirty;
      pid killed → next sweep committed it. Cross-checked against the
      OTHER reader — `check-project-busy.sh testproj` reported `BUSY` off
      the same marker, so both halves of the ecosystem agree on one file.
      The first run of this test FAILED and caught a real bug: `local
      proj="$1" marker="…$proj…"` expands every word before assigning any,
      so `$proj` was unbound under `set -u`, the probe aborted, and sweep
      committed anyway — a guard that fails OPEN. Fixed and re-witnessed.
    - **BATCH SIDE CLOSED the same session (human-directed "yes"), which
      completes item 3 of the sweep-attribution regulator.**
      `lib/sweep-loop-common.sh` now probes `<PROJECT_KEY>.interactive`
      immediately after the two flocks — job-vs-job was already handled
      there, this is job-vs-human, in the one shared library every
      registered project's every job inherits (the same one-place property
      REGISTRY_LOCK has). A live holder makes the run stand down before
      any clone or claude spend. *(SUPERSEDED 2026-07-27 — the cap
      described below counted dispatch ATTEMPTS, which measured nothing a
      human does: four attempts inside ten seconds exhausted it, and it
      could not tell an actively-edited repo from an editor left open in
      the background. Replaced by an activity probe on the marker's own
      `cwd` — defer while the repo has been touched within
      `REGISTRY_ACTIVE_GRACE_MIN` (default 60), proceed quietly once it
      goes quiet, with a time-based `REGISTRY_MAX_DEFER_HOURS` (default
      24) backstop as the only loud path. See `lib/registry-lock.sh`.)*
      **Starvation cap: `INTERACTIVE_DEFER_MAX`
      (default 3, settable per job via RUNNER_ENV or `schedule/<key>.conf`)
      consecutive deferrals, then it runs anyway and says so LOUDLY** —
      log WARNING plus a critical `notify-send`, because silent indefinite
      deferral is a worse failure than warn-then-continue. The counter
      lives at `$STATE_DIR/interactive_deferrals` and is removed on any run
      that proceeds, so the cap counts CONSECUTIVE misses, not lifetime.
      A deferral writes a real ===-delimited `=== skipped (human editing,
      deferral N/M) ===` record, matching what the expiry block was
      changed to do earlier for exactly this reason: a bare prose line is
      invisible to `scheduler status`, which would then re-report the
      previous run as current and hide that the project has been standing
      down. Exit 4 — distinct from success (0), fatal (1), expired (3) —
      so `usage-paced-runner.sh`'s `rc=` line tells deferred from worked
      without parsing the log.
      - **Witnessed** with a throwaway JOB_NAME/PROJECT_KEY and a past
        expiry stamp as a backstop (so a probe that fell through would
        stop at expiry rather than clone or spend): live marker → rc 4 and
        `deferral 1 of 2`, again → `deferral 2 of 2`, third run → WARNING
        line + proceeded (rc 3, the backstop, proving it went past the
        probe) + counter reset; no marker at all → straight through, rc 3,
        counter removed. Stale marker (dead pid) reads as nobody editing.
      - **Still open and independent:** item 2's mtime quiescence guard. A
        marker only covers writers who take it — raw vim on a project's
        own checkout, not launched through the front door, still takes
        none. That guard needs no writer cooperation at all.

- **[batch] 2026-07-26 (human-directed log review) — `usage-gate.sh`
  swallows curl failures and never retries.** Observed, not hypothetical:
  **25 consecutive `HOLD (gate rc=2) verdict=ERROR reason=curl_failed`
  ticks on 2026-07-26, 18:05 → 19:40 — ~95 minutes of zero dispatch** —
  then it recovered on its own with no intervention. (33 such HOLDs
  lifetime; the rest are 1-3/day singles.) Two defects, both at
  `bin/usage-gate.sh:56-63`:
  (1) **The reason is thrown away.** `curl ... 2>/dev/null || emit_error
  curl_failed` collapses every possible curl exit code into one opaque
  token and discards stderr, so after the fact you cannot tell DNS from
  TLS from a 30s `--max-time` timeout from a dropped route. Wanted:
  capture curl's exit status and stderr, and log both (`reason=curl_failed
  rc=6 detail=<first line of stderr>`). This is the "fails loud" item in
  CLAUDE.md's build discipline — right now it fails *quietly and
  identically* for four different causes.
  (2) **No retry.** A single transient blip costs a whole 5-minute tick,
  and the ERROR→HOLD fail-safe (correct in itself) turns a network flap
  into a compounding dispatch stall. Wanted: retry the probe 2-3× with
  short backoff *inside one tick* before emitting ERROR. The probe is
  ~23 tokens, so retrying is nearly free; a 95-minute stall is not.
  Keep ERROR→HOLD as the terminal behaviour — this only stops one packet
  loss from being indistinguishable from "the API is down."

- *(subsumed by [iface: crash-durability] above, 2026-07-26 /ideate — spec lives here, dispatch there)* **[batch] 2026-07-26 (human-directed log review) — a batch that dies
  mid-turn leaves its worktree dirty, and the next run silently discards
  the work.** Today's three failures were all transient API drops, not
  project bugs: gardien 19:56 (`API Error: Unable to connect to API
  (ENOTIMP)`, 807s of work lost), wtul 21:10 (`Connection closed
  mid-response`, 161s), gardien 21:47 (same, 416s). Lifetime failure rate
  is low (~8/240, ~3%) and the older half is all spend/session-limit
  cutoffs from before the Max move — so **this item is about the crash
  *aftermath*, not about preventing the drops.** What the aftermath looks
  like right now, verified by hand:
  `~/.local/share/gardien-nightly-batch/repo` is sitting dirty — 7
  modified files (`gardien.py`, `test_gardien.py`, `.claude/QUESTIONS.md`,
  `README.md`, `gardien.json.example`, `systemd/install.sh`,
  `systemd/uninstall.sh`) plus 2 untracked new unit files
  (`systemd/gardien-check-stale.{service,timer}`) — none committed. The
  next dispatch's `reset --hard` will destroy all of it with no record
  that it existed, and the autonomy sweep already refused to run over it:
  `working tree not clean on main -- skipping this run`. So one dropped
  connection costs the work twice: once when the turn dies, again when the
  next run wipes it. Wanted: on `STATUS=FAILED` in
  `lib/sweep-loop-common.sh`, before anything resets, commit-or-stash the
  dirty tree onto a `crashed/<project>/<date>` ref (untracked files
  included — the two new unit files above are exactly what a plain `git
  stash` would miss) and name it in the report, so a killed run is
  recoverable instead of merely logged. Pairs with the existing `push
  reason:` diagnostic, which already explains *why* nothing was pushed but
  does nothing to save what was written.

- *(subsumed by [iface: sweep-attribution] above, 2026-07-26 /ideate — spec lives here, dispatch there)* **2026-07-26 21:22 (via `scheduler -i`):** REGULATOR for the sweep-attribution interface (4 items, one cause). Root cause traced 2026-07-26 by realisateur: `scheduler sweep` (crontab */15) walks every registered repo's PRIMARY WORKING TREE, finds any dirty *.md, and calls cmd_commit_file with NO message arg -- so it falls through to the default "Human edit via scheduler: <file>". Its assumption (dirty .md == a human left an edit in vim) was true when vim was the only writer of these files and is false now that agent sessions edit the same tree. Fourth occurrence 2026-07-26 21:00 (prior: 13:15 same day, and two earlier): it adopted a live interactive session's in-flight PRECIPITATION.md/UNIVERSE.md/ideate.md -- a 192-line file that had not existed 20 minutes before -- and signed Zach's name and email to all three. NOTE the scope is wider than FOCUS files: ANY dirty *.md in ANY registered repo is fair game on a 15-minute clock, including half-written drafts. Batch isolation is NOT the gap and needs no change -- scheduled jobs already run against dedicated clones that reset hard to origin (cmd_commit_file's own comment says so, and sweep already has a second pass over them). Nor is "interactive sessions branch" a fix: sweep would commit the branch under Zach's name just the same, treating divergence while leaving false authorship intact. (1) HONEST ATTRIBUTION, one-line change at the single place the default msg is set (~line 706), do this first and unconditionally: sweep has NO provenance -- unlike -i and the vim hook, where a human demonstrably acted, it merely found a dirty file. It should say what is true ("sweep: auto-commit uncommitted <file>") and commit under a distinct identity the way the nightly already does with hf7y. This alone ends the provenance laundering without needing to detect sessions at all. (2) QUIESCENCE GUARD: a file modified 40 seconds ago is work in flight; one modified 3 hours ago is an abandoned edit. Skip commit unless mtime is older than N minutes (find -mmin +N). Needs no knowledge of Claude or vim and would have prevented the 21:00 case outright. (3) HONOR THE EXISTING LOCK, the real end state: realisateur/bin/check-project-busy.sh already probes flock on job dirs and its header explicitly chose locks over "guessing from mtimes". An interactive session should take that same lock and sweep should skip locked projects -- reusing the one regulator rather than inventing a second. (4) AGENT-AUTHOR VARIANT FOR -i (Zach's call, 2026-07-26): cmd_idea writes one fixed marker, "(via scheduler -i)", identical whether Zach typed it or an agent filed it -- so intake provenance is lost at the source, not just at sweep time. Proposal: an explicit agent variant (e.g. "scheduler -i --agent <name> <project> TEXT") writing a distinguishable marker and committing under an agent identity. This is not cosmetic: realisateur/bin/precipitation-scan.sh classifies entries INBOX/HUMAN/LOG by parsing exactly that string to decide what counts as a promotion signal, and PRECIPITATION.md ranks re-arrival of a HUMAN-origin idea as the strongest signal in the ecosystem. With no agent variant, an agent-filed idea is indistinguishable from a human-filed one, so the system can manufacture its own promotion evidence and boost its own suggestions -- a closed feedback loop in the one place the doctrine is most load-bearing. The variant makes that classification exact instead of inferred. Filed via the front door per /ideate 5 (engine change, realisateur does not hand-edit scheduler). Full trace + the ranked-signal doctrine: realisateur/PRECIPITATION.md and UNIVERSE.md (Law 3 / the Ashby reading -- this is the multi-writer FOCUS-file interface, still the ecosystem's least-regulated).

- **[batch] [recurring theme — for realisateur] 2026-07-26 (human-directed
  session):** *Config changes land as uncommitted working-tree edits and
  half-deploy.* Today's exhibit: the usage-gate ceiling. A prior session
  was supposed to raise it 0.85 → 0.99; what was actually on disk was an
  **uncommitted** `schedule/_runner.conf` edit setting `0.95`, already
  synced into the live crontab. So the live value was wrong (0.95, not the
  intended 0.99), it disagreed with the committed repo (0.85 default), and
  one `git checkout`/`reset --hard` would have silently reverted the
  deployed behaviour with nothing flagging it. Fixed by hand this session
  (a9bffa2, ceiling now 0.99, crontab re-synced).
  **This is the recurring shape, not a one-off** — it is the same failure
  family as the 2026-07-26 09:32 entry below (`reset --hard` destroying
  committed-but-unpushed work) and the 2026-07-26 11:08 autocommit-watcher
  race: *state that the running system depends on lives in a working tree
  nobody proves is clean.* Flagged for realisateur to treat as an
  ecosystem theme (dirty-tree-as-deployed-config), not to fix one file.
  Wanted here, concretely: `bin/sync-crontab.sh --apply` should refuse (or
  loudly warn) when the `schedule/*.conf` it is generating from is dirty
  relative to HEAD — deploying from uncommitted config is exactly the
  "deploy verified against a git ref; drift fails loud" item in
  CLAUDE.md's build discipline, currently unenforced. A `scheduler sweep`
  check for "managed conf dirty / crontab disagrees with committed conf"
  is the passive half.

  **DONE (active half) 2026-07-27 paced cycle: `bin/sync-crontab.sh`
  committed-config gate.** `--apply` now exits 2 rather than installing
  cron lines generated from a `schedule/` that doesn't match HEAD (tracked
  modification, staged change, OR an untracked `schedule/*.conf` — a conf
  never committed at all is the worst case, not an exempt one). A tree
  that isn't inside a git repo counts as UNVERIFIABLE and refuses too:
  "can't check" is not "clean". Preview (no `--apply`) is deliberately
  unchanged except for a stderr warning — inspecting an in-progress edit
  before committing it is the normal workflow, and the preview's stdout is
  byte-identical to before. `--allow-dirty` is the on-the-record override;
  `--check-clean` runs only the gate (0 clean / 2 dirty, writes nothing,
  reads no crontab) so the passive half below can call it without
  duplicating the logic.

  **DONE (passive half) 2026-07-27, same cycle: `cmd_sweep` eighth pass.**
  `scheduler sweep` now calls `sync-crontab.sh --check-clean` and reports a
  `schedule/` that has been left sitting uncommitted — the state a human
  never sees until some later `--apply` ships or drops an edit nobody
  remembers making. It calls the gate rather than re-deriving the rule, so
  the two halves can't disagree. Reports only, never auto-commits: adopting
  someone's half-finished config edit is exactly the sweep-attribution
  mistake being unpicked elsewhere in this file. rc 2 (the gate's own
  dirty verdict) and any other nonzero rc are reported differently — an
  installed `sync-crontab.sh` predating `--check-clean` says
  "committed-ness UNKNOWN, not clean", not a false config finding. Note
  `SCHED_ROOT` is the primary checkout, so the pass reports on the real
  repo, not on whatever worktree a cycle runs from. Verified by exercising
  all four branches (clean / dirty / old-script rc=1 / script absent).
  **The backlog item above is now fully closed, both halves.**

  Original verification of the active half, without ever invoking `--apply`: all
  four gate branches (clean/dirty/override/non-git) exercised by sourcing
  the gate's own bytes out of the script with `APPLY=1`, plus
  `--check-clean` end-to-end against a real dirty tracked conf, a real
  untracked conf, and a clean tree (also under `env -u SSH_AUTH_SOCK`),
  `bash -n` clean, and a byte-for-byte preview diff against the HEAD
  version. **Still open: the passive half** — a `scheduler sweep` check
  for "managed conf dirty / crontab disagrees with committed conf".
  `--check-clean` is the hook it should call.

  **Sequencing note:** this is one of the two halves of the hard gate that
  QUESTIONS.md's answered axis-1 question (option (a), converge paced
  dispatch on `bin/scheduler-run`) says must land BEFORE any `_paced*.conf`
  command-column flip. The other half — the symlink-deploy import for
  `scheduler pacing deploy`/drift, so the paced runner dispatches from a
  committed copy — is untouched. Do NOT read this item's completion as
  clearance to start flipping command columns.

- *(subsumed by [iface: usage-ceiling-conf] above, 2026-07-26 /ideate)* **[batch] 2026-07-26 (human-directed session) — filed separately on
  purpose:** the **config-settable usage ceiling** (see the 2026-07-25
  17:06 entry further down for the full scoping: `schedule/_usage.conf`,
  env-wins precedence, per-host `_usage.<host>.conf`, and naming what it
  retires). Today's 0.99 change had to be made by editing `RUNNER_ENV` and
  re-running `sync-crontab.sh --apply`, and the value now exists in two
  places — the conf and `bin/usage-gate.sh:41`'s `0.85` default — which is
  precisely the single-source violation that entry describes. Keeping this
  as its own item rather than folding it into the dirty-tree theme above:
  one is *where the value lives*, the other is *whether what's deployed
  matches what's committed*. Both are real; fixing either alone leaves the
  other.

- **2026-07-26 13:14 (via `scheduler -i`): DONE (2026-07-26 paced cycle).** Templates still teach the gated .claude/ layout -- update examples/ to .scheduler/ (realisateur, 2026-07-26). `examples/FOCUS.md.template`, `QUESTIONS.md.template`, `CLAUDE.md.template`, `nightly-batch.md.template`, `bug-sweep.md.template`, `nightly-batch-loop.sh` (legacy reference), `schedule-entry.conf.template`, and `README.md` all instructed new projects to put FOCUS.md/QUESTIONS.md in `.claude/`, where the harness sensitive-file gate makes them unwritable by the very nightly runs they scope. Every FOCUS.md/QUESTIONS.md reference in those files now points at `.scheduler/` (each carrying a one-line rationale comment on why, not just the path swap); `.claude/commands/*.md` self-references were left alone since slash commands are required to live there by the harness. `schedule-entry.conf.template` gained an explicit `SCHEDULER_SUBDIR=".scheduler"` field (previously only real per-project confs like chezz/realisateur had it — the template itself still defaulted silently to `.claude`) with a comment naming the sensitive-file gate as the reason and pointing at a real example. Verified: `grep -rn '\.claude/FOCUS\|\.claude/QUESTIONS' examples/ README.md` now only matches the deliberate "NOT .claude/..." explanatory sentences, none are instructions to use it; `bash -n examples/nightly-batch-loop.sh` clean. Context: realisateur migrated its own files 2026-07-26 (fa222cb + scheduler 1284b58); ecosystem pass for the remaining `.claude/` projects stays queued in realisateur's own `.scheduler/FOCUS.md`, unaffected by this — this item was scoped to the templates only.

- **2026-07-26 11:08 (via `scheduler -i`):** FOCUS-file autocommit watcher: two fixes queued from realisateur's 2026-07-26 write-race incident (see realisateur .claude/FOCUS.md same date, race entry). At ~10:30 the watcher committed a LIVE interactive session's uncommitted .claude/FOCUS.md edits as 'Human edit via scheduler' — under Zach's own name in realisateur (93ad456, published, cannot be reattributed) and as hf7y on crt's stale checkout — and its push moved origin under the session's feet. Proposed: (a) honest attribution — an adopted working-tree edit is 'autocommit-watcher', never 'Human edit'/a human's name; or refuse to adopt .claude/-gated files entirely; (b) before committing/pushing from a working tree it does not own, probe for a live interactive session (flock probe, same shape as realisateur's bin/check-project-busy.sh, pointed the other direction) and skip that tick if one is live. Second live exhibit of UNIVERSE.md's multi-writer FOCUS-file gap; realisateur is building its own half (atomic focus-commit.sh helper) separately.
  **Part (a) DONE (2026-07-26 paced cycle).** `cmd_sweep`'s auto-commit
  call (`bin/scheduler`, the one call site that adopts a dirty `.md` with
  no explicit message, hitting `cmd_commit_file`'s "Human edit via
  scheduler" fallback) now passes its own honest message: `scheduler
  sweep: adopted dirty <file> (reactive backstop -- author unknown,
  possibly a live session not yet auto-committed) (<timestamp>)`. The
  vim auto-commit hook's own call (`~/.vimrc`, outside this repo) already
  said "Human edit via scheduler vim hook" correctly — a live human did
  make that edit — so it needed no change; only the sweep backstop, which
  cannot know who wrote the file, was misattributing authorship. Verified:
  `bash -n bin/scheduler` clean; ran `cmd_commit_file` directly against a
  throwaway repo with the new message and confirmed the exact string lands
  in `git log`. Part (b) — probing for a live interactive session before
  sweep commits/pushes — is real design/build work (a new flock convention
  the editing session would also need to hold) and stays open, not
  attempted this cycle.

- *(subsumed by [iface: crash-durability] above, 2026-07-26 /ideate — spec lives here, dispatch there)* **2026-07-26 09:32 (via `scheduler -i`):** sweep-loop-common.sh: bootstrap reset --hard origin/$BRANCH silently DESTROYS committed-but-unpushed work from a prior run. Bit chezz 2026-07-25: the 20:10 nightly hit the monthly spend limit, died before its push step, left 3 real commits (0880f3d tip: 4 shipped features + size-policy + scaffold work, tracker already marked resolved against those hashes); the engine even logged 'WARNING: local commit made but NOT pushed' -- then the next cycle's reset erased them anyway. Chezz's 2026-07-26 run recovered them from the reflog (luck-dependent, gc window) and pushed. Fix where the uncommitted-work stash guard already lives (~line 288): before reset --hard, if git rev-list --count origin/$BRANCH..HEAD > 0, create a rescue ref (e.g. branch rescue/<JOB_NAME>-<date>) or retry the push, and log loudly. The stash guard protects uncommitted work; committed-ahead work has no equivalent today.
  **DONE (2026-07-26 paced cycle).** Same shape as the existing stash
  guard, right before it hands off to `git reset --hard origin/$BRANCH`:
  computes `git rev-list --count origin/$BRANCH..HEAD`, and if nonzero,
  creates `rescue/<JOB_NAME>-<timestamp>` pointing at the current HEAD,
  logs a `WARNING:` naming the ref and the recovery command, and fires a
  `notify-send -u critical`, before the reset runs. Verified with a
  throwaway bare-origin + clone: committed one commit ahead of origin
  (simulating a died-before-push prior run), ran the exact
  rescue-then-reset sequence, confirmed the branch tip lands back on
  origin's commit while `git log --oneline --all` still shows the
  stranded commit reachable via the new `rescue/...` ref -- no more
  reflog-window luck required. `bash -n lib/sweep-loop-common.sh` clean.

- **2026-07-25 20:33 (via `scheduler -i`):** from chezz fable-review triage 2026-07-25: make the staleness/freshness checks exit nonzero on failure so a stale run fails loud (fable-review item 3, staleness-check exit-nonzero + sweep-tier ownership) -- scheduler/realisateur-side, chezz can't do this from its own repo; routed here per the never-quietly-decline rule

- *(ADOPTED as the Current stability milestone, 2026-07-26 interactive /ideate — this entry is now the milestone's spec, no longer a queued proposal)* **2026-07-25 19:51 (via `scheduler -i`):** Front-door consolidation -- promote parked item 0 to the NEXT stability milestone (adopt when the current zero-silent-failure bar closes; 4/5 checked, last box routed to realisateur). Override stated per realisateur ideate 4.5: re-derivation convergence -- the 2026-07-20 target UX (item 0) was re-derived independently by Zach 2026-07-25 near line-for-line, the strongest ready-to-build signal this ecosystem produces (doctrine: realisateur/UNIVERSE.md, written same session). Bar: the entire human surface is three stable PRINTABLE views -- `scheduler` noargs (now/next + one-line gate/dials footer), `scheduler <project>` (detail, inline reply, reorder/reweight from there), `scheduler blockers` (the one blocked-on-you place) -- each view footer printing its own mutation one-liners. Decisions locked 2026-07-25 (Zach, via realisateur /ideate): HARD FOLD + RETIRE (glance/status/overview/next/explain/focus/questions/report/pacing-show as separate surfaces retire to one-line redirect stubs; usage() <= ~20 lines); STATIC + VERBS, no TUI (printable doctrine holds); DIALS = one-line noargs footer, full pacing/drift/deploy detail stays under pacing. ACCRETION FREEZE effective now: no view gains a legend line or new verb before the redesign -- new needs go into this spec. Weights raised same session to get here soon (scheduler 3->4, realisateur 1->3, exit stated in _paced.conf: both drop back when this milestone is reached).

  - **SPEC REQUIREMENT filed into this entry 2026-07-26 (per the freeze's
    own "new needs go into this spec" clause): the `blockers` view must
    answer "which projects owe me an answer, and which of those have I
    not looked at" without opening a file per project.** Per-project
    `unanswered/total` plus an unread marker, unread sorted first — the
    `n/m` + `*` vocabulary the glance already uses, so the consolidated
    view inherits it rather than inventing a third. Source: a
    human-directed quickfix shipped the same day as a stopgap on `-q`
    (see the dated entry at the top of this Backlog), which is a
    *prefix* of this requirement, not a substitute — the ranking half
    (order by how much queued work each answer releases) and the
    standing-policy vocabulary are the part that still needs building,
    and they belong here, in the one obligation view, not on `-q`.

- **2026-07-25 19:28 (via `scheduler -i`):** check Chezz's questions.md. Add the scheduler_subdir to be .scheduler for chezz's repo

- **2026-07-25 17:11 (human-directed session):** `scheduler -b --claude`'s
  "press Enter to open BLOCKERS.md" pause is **invisible** — bash's
  `read -p` writes its prompt to **stderr**, and `bin/scheduler:1896`
  redirects it away (`read -rp "press Enter..." _ 2>/dev/null || true`).
  Diagnosed live 2026-07-25: after the tidy pass's digest + commit line,
  the script sat waiting on a prompt the user couldn't see; it looked
  like the command had exited without opening vim (arrow keys echoed
  literally as `^[[A^[[B`, confirming a bare `read` was consuming input,
  not the shell). Ctrl-C there is the by-design "stop at the digest"
  path, so the mechanism works — only the prompt text is swallowed. Fix:
  print the prompt explicitly on stdout (`printf 'press Enter to open
  BLOCKERS.md (Ctrl-C to stop at the digest) '`) then a plain
  `read -r _ 2>/dev/null || true` — keeps the non-tty guard the
  redirect was there for while making the pause visible. Witness: next
  interactive `scheduler -b --claude` run visibly shows the pause prompt
  after the digest.
  **DONE (2026-07-26 paced cycle):** exactly the prescribed fix —
  `printf` the prompt to stdout, then a plain `read -r _ 2>/dev/null ||
  true` keeping the non-tty guard on the read alone. Verified with
  stdout captured + stderr dropped + non-tty stdin: prompt renders,
  read falls through cleanly at EOF. The human witness (a live
  interactive `-b --claude` run) is still worth a glance next time one
  happens, but the mechanism is confirmed.

- *(subsumed by [iface: usage-ceiling-conf] above, 2026-07-26 /ideate — the conf-file scoping here is the spec)* **2026-07-25 17:06 (human-directed session):** Make the usage-gate
  **ceiling settable from a config file**, not only env. Today the 0.85
  cap lives solely in `bin/usage-gate.sh:41`
  (`CEILING="${USAGE_CEILING:-0.85}"`); the only persistent override path
  is editing `RUNNER_ENV` in `schedule/_runner.conf` and re-running
  `bin/sync-crontab.sh --apply` — two steps, and the value ends up
  retyped on a crontab line instead of read from one source (build
  discipline violation). Wanted: a single conf the gate itself sources
  (e.g. `schedule/_usage.conf` with `USAGE_CEILING=` / `USAGE_MIN_SLACK=`),
  explicit env still winning over the file so one-off
  `USAGE_CEILING=x bin/usage-gate.sh` tests keep working. Scoping notes
  from today: (a) the deployed gate at `~/.local/bin/usage-gate.sh` is a
  **copy, not a symlink**, so the conf lookup can't assume a repo-relative
  path — either resolve via a `SCHEDULER_*` env the runner already
  forwards, or use a fixed per-user path; (b) `schedule/_paced.dexter.conf`
  establishes the host-scoped-conf convention, and DESIGN-NOTES.md:807
  already anticipates wanting **per-host** ceilings once two hosts share
  one account budget — support `_usage.<host>.conf` overriding the base
  file from day one; (c) whatever ships must name what it retires: update
  the `RUNNER_ENV` guidance in `_runner.conf`/docs so the ceiling isn't
  settable in two competing places.
  **DONE (2026-07-26 paced cycle)** — all three scoping notes honoured.
  `bin/usage-gate.sh` now resolves `USAGE_CEILING`, `USAGE_MIN_SLACK`,
  `USAGE_RUSH_BEFORE_RESET_MIN` and `USAGE_PROBE_MODEL` **per field** from:
  explicit env → `schedule/_usage.<host>.conf` → `schedule/_usage.conf` →
  its own built-in defaults. (a) the conf dir is resolved the way
  `usage-paced-runner.sh` already does it (`readlink -f` on `$0`, then the
  same legacy absolute-path fallback constant) so the copy-not-symlink
  install at `~/.local/bin/usage-gate.sh` still finds the repo's
  `schedule/`; `USAGE_CONF_DIR` overrides it for tests. (b) host-scoped
  `_usage.<host>.conf` supported from day one, same convention as
  `_paced.<host>.conf`. (c) `schedule/_runner.conf` now says in-file that
  the gate's pacing knobs do NOT belong in `RUNNER_ENV` and why (env wins,
  so a stale crontab-line value would silently outrank the conf a human
  just edited) — the retired path named at the enforcement point, not only
  in docs. Shipped `_usage.conf` has every knob **commented out** on
  purpose: the script stays the single definition of each default (a
  repo-less copy install has to fall back to them regardless), and the file
  is purely the override layer — so this landed with **zero** change to
  live pacing. Parsed rather than sourced (the gate holds a live OAuth token
  and its own `CEILING`/`QUIET` vars at that point); an unparseable or
  out-of-range value is a loud `ERROR` exit 2 — which every caller already
  treats as HOLD — naming file+key+value, chosen over warn-and-default
  because pacing against a typo is the failure you can't see. The verdict
  line gained one field, `knobs=ceiling:<src>,min_slack:<src>,rush_min:<src>`,
  so "is my edit live?" is answerable; no new output lines, per the
  accretion freeze. Fixed in passing: `USAGE_RUSH_BEFORE_RESET_MIN` was read
  from `os.environ` inside the python core but never passed there, so a
  conf/shell-var value would have been silently ignored — now passed
  explicitly. Verified offline with a fake-`curl` harness feeding fabricated
  rate-limit headers: defaults-when-no-conf, base conf, host conf overriding
  the base **for that field only** while the base still supplies the others,
  host conf correctly ignored for a different host, env beating both, a conf
  ceiling actually flipping the verdict to HOLD (0.20 vs 0.30 util), exit
  codes 0/1/2, `USAGE_GATE_QUIET=1` still one word, comment-only conf → not
  an error, an invalid value in the host conf naming the host file, and a
  bad base value repaired by a valid host override. Plus a real live probe
  (correct verdict against real headers), a copy-install run from a dir with
  no sibling `schedule/` (confirmed it takes the legacy absolute path and
  falls through to defaults cleanly), and both downstream consumers re-run
  against the new line: `bin/scheduler`'s `pacing_show_human` and
  `usage-paced-runner.sh`'s log-summary grep. Live evidence the retired path
  was a real hazard: this cycle's own environment carries a hand-set
  `USAGE_CEILING=0.99` that appears in no conf at all (`_runner.conf` sets
  only `PACED_MAX_PER_TICK=16`) — env still wins, so that stays in force
  until a human drops it or uncomments a value; see DESIGN-NOTES.md
  2026-07-26 for the full writeup.

- **2026-07-25 11:51 (via `scheduler -i`):** Investigate 'a door': remote idea-intake for 'scheduler -i' so drops don't require originating on mandark, raised via realisateur's 2026-07-25 nightly-batch pass (senechal session origin). PARKED against current milestone (zero-silent-failure unattended dispatch) -- this is a new intake surface, not required to reach it. Scoping done, not built: intake options are (a) SSH-only -- push a signed .idea/text file to a dedicated bare repo over the same SSH path dexter already uses for crt (git-shell-only key, no shell access), a post-receive hook calls cmd_idea/writes FOCUS.md, no new network service; (b) a tiny authenticated HTTP endpoint (webhook-style) that shells out to the same insertion logic -- more reachable from a phone but is a genuinely new internet-facing surface needing its own hardening; (c) email/SMS relay -- adds a third-party dependency and parsing surface for little benefit over (a). Recommend (a) as the only option that reuses the existing SSH-key/git-shell pattern with no new listening service; senechal's own secret-guarding charter makes an internet-reachable file-editing endpoint (b) the one to threat-model hardest if ever chosen. Revisit once scheduler's current milestone is reached.

- **2026-07-25 10:43 (realisateur session, routed from `scheduler status
  chezz`):** The `EXPIRY_DAYS` dead-man switch is a **silent kill switch
  with a remedy that does not work.** Four findings, all verified today by
  reading the code and the live state — these belong to the stability
  milestone above ("a run that … has its assumed external dependency
  quietly stop being true is always flagged loudly"), not to the parked
  reservoir:
  1. **The documented renewal is a no-op.** Three user-facing messages say
     "bump `EXPIRY_DAYS` and re-run `bin/sync-crontab.sh` to renew"
     (`bin/scheduler:1689`, `bin/sync-crontab.sh:381` and `:405`, plus
     `lib/sweep-loop-common.sh:199`). Nothing in `bin/` or `lib/` ever
     writes `expires_at` — verified with `grep -rn expires_at bin/ lib/`:
     `sync-crontab.sh:224-229` only *reads* it, and
     `lib/sweep-loop-common.sh:192-194` writes it **only when the file is
     missing**. So bumping `EXPIRY_DAYS` on an already-expired job changes
     nothing; the real renewal is `rm ~/.local/share/<job>/expires_at`
     (next run re-stamps `now + EXPIRY_DAYS`). Fix: either correct all four
     messages to name the action that actually renews, or make
     `sync-crontab.sh --apply` genuinely re-stamp `expires_at` when a job's
     `EXPIRY_DAYS` changed. Same failure class as the 2026-07-25
     svc-vaporwave incident — a written remedy nobody re-ran against the
     code.
  2. **Expiry is a clean `exit 0`, so the paced dispatcher can't see it.**
     `lib/sweep-loop-common.sh:198-204` clones the repo, then `exit 0` with
     only a `notify-send` and a log line. `bin/usage-paced-runner.sh` has
     no `expires_at` awareness at all (`grep` finds none), so an expired
     project still consumes a paced slot and records as a normal dispatch.
     Live witness: `chezz-nightly-batch` no-op'd at 2026-07-25T01:21:51 and
     T08:55:02, `home-assistant-nightly-batch` at T08:55:04 — both in their
     own `sweep.log`, nowhere else. Fix: exit non-zero (or a distinct
     status the runner logs as skipped-expired), and teach the paced runner
     to skip an expired job before it burns a slot and a clone.
  3. **Expiry is invisible outside per-project `scheduler status
     <project>`.** It is not in `scheduler` glance and not in `scheduler
     sweep`. **5 of 14 jobs are expired right now** — found only by
     hand-scanning `~/.local/share/*/expires_at`:
     `chezz-nightly-batch` (2026-07-25T01:00), `chezz-bug-sweep`
     (2026-07-23T22:44), `home-assistant-nightly-batch` (2026-07-25T01:30),
     `vkv-inventory-bug-sweep` (2026-07-24T13:30),
     `vkv-inventory-nightly-batch` (2026-07-25T02:32). Surface EXPIRED per
     project in both views; this is the same signal-sitting-unread shape as
     the "bidirectional liveness" item queued below.
  4. **`schedule/chezz.conf` still needs `SCHEDULER_SUBDIR=".scheduler"`** —
     the cross-repo follow-up chezz's own 2026-07-24 batch correctly refused
     to make from its side (see chezz's `.scheduler/FOCUS.md`). Today
     `focus/chezz.md` and `questions/chezz.md` are **dangling symlinks** into
     `chezz/.claude/`, which is why `scheduler status chezz` reports "no
     FOCUS.md found" while `chezz/.scheduler/FOCUS.md` is a real 271-line
     file. Also fix `chezz.conf`'s `BATCH_PROMPT`, which still says "Read
     .claude/FOCUS.md FIRST". NOTE the live wrapper
     `~/.local/bin/chezz-nightly-batch-loop.sh` says the same thing and is
     still authoritative (`BATCH_SCRIPT` set) — so chezz's batch has been
     pointed at a nonexistent scope file since 2026-07-24 and would run
     unscoped. Editing that wrapper is out of scope for a batch (see
     roadmap item 1's "editing it is not"), so it is filed as a human step
     in `BLOCKERS.md` → `## scheduler` instead. The general fix is the
     already-queued "one resolver for per-project path + ref" item — do
     chezz's one-line conf fix now regardless, don't wait for it.
  *(Not routed as a stranded-commit report: the "local commit NOT pushed
  local=7ee1262" warning in chezz's last-run log is STALE — re-probed today,
  `git -C ~/.local/share/chezz-nightly-batch/repo fetch && rev-list --count
  origin/main..HEAD` = 0, and `7ee1262` is in `origin/main`'s history.)*

  **UPDATE 2026-07-25 11:00, same session, human-directed ("lets knock this
  out now") — items 1-3's mechanism work is still OPEN, but the live
  breakage is fixed by hand. Do not redo these:**
  - **Item 4 is DONE, don't repeat it.** `schedule/chezz.conf` now sets
    `SCHEDULER_SUBDIR=".scheduler"` and its `BATCH_PROMPT` says
    `.scheduler/FOCUS.md`; `focus/chezz.md` and `questions/chezz.md` were
    re-pointed with the same `ln -sfn` calls `sync-crontab.sh --apply` makes
    (lines 530/558) and now resolve to the real 271-line/118-line files.
    `~/.local/bin/chezz-nightly-batch-loop.sh`'s two `.claude/FOCUS.md`
    references were fixed too (human-authorized this session; that wrapper
    stays off-limits to a batch). Verified: `scheduler status chezz` reads
    real focus items + open questions instead of "no FOCUS.md found"; conf
    `BATCH_PROMPT` and wrapper `PROMPT` diffed **byte-identical** so the
    `BATCH_SCRIPT`-authoritative invariant still holds. `--apply` was
    deliberately NOT run: its zach-account output was already byte-identical
    to the live crontab, and running it would also have written
    svc-vaporwave's crontab over sudo — a cross-account write with no
    reason to happen today.
  - **`chezz-nightly-batch` and `home-assistant-nightly-batch` expiries were
    renewed by the human** (`rm ~/.local/share/<job>/expires_at`; old values
    backed up first). Both now re-stamp `now + 7d` on their next dispatch —
    verified by running `lib/sweep-loop-common.sh`'s create-if-missing +
    compare block in isolation against a temp file (result: PROCEED,
    re-stamped 2026-08-01). Still expired ON PURPOSE, left alone:
    `chezz-bug-sweep` (its tier is parked — `SWEEP_JOB_NAME=""`) and both
    `vkv-inventory` jobs (now dispatched under svc-vaporwave's own crontab).
  - **NEW finding 5, from re-checking the two "stranded commit" warnings:
    `build_status_report` greps the WHOLE `sweep.log`, so
    `scheduler status` reports warnings from OLD runs under the heading
    "-- last scheduled run --".** Both cases today were stale by two or more
    runs: chezz's last `WARNING: local commit made but NOT pushed` is at
    `sweep.log:282` with run boundaries at `:315`/`:325`/`:339`;
    home-assistant's is at `:356` with boundaries at `:384`/`:404`/`:419`.
    Home-assistant's is worse than stale — it reads "could not read
    origin/main … SSH/auth/network failure", but that repo's only branch is
    `master` (the wrapper sets `BRANCH="master"`, `ls-remote` works, and the
    clone is **0 ahead of `origin/master`**), so the surfaced line both
    predates the fix and names a diagnosis that was never true. Fix: scope
    the `WARNING:`/`push reason:`/`pushed:` greps to the slice after the
    second-to-last run marker, so a resolved warning stops being re-reported
    forever. This one cost real time twice today — it is why chezz looked
    like it had a stranded commit at the top of this entry.
    **Finding 5 is DONE (2026-07-26 paced cycle).** `build_status_report`
    now extracts the LAST run's slice (everything from the final
    `=== <timestamp> ===` start marker onward) and scopes ALL five per-run
    greps to it — status line, `pushed:`, `WARNING:`, `push reason:`, and
    the FAILED-gated `CRITICAL:` auth line. A slice with a start marker but
    no completion line (still running, or cut off before its EXIT trap
    fired) is named explicitly ("no completion line yet ... see scheduler
    sweep") instead of silently falling back to an older run's lines.
    Verified against fabricated multi-run logs (stale-warning suppression,
    in-flight naming, current-auth-failure full display) AND the real chezz
    `sweep.log`, where the old whole-log grep was actively lying: it showed
    `pushed: yes` from a previous run directly above the last run's
    `WARNING: ... NOT pushed` — two contradictory lines from different runs
    rendered as one story.
    **Items 1–3 are DONE (2026-07-26 paced cycle, three commits on
    `paced/2026-07-26`).** Item 1: all four "bump EXPIRY_DAYS and re-run
    sync-crontab" messages now name the action that actually renews
    (`rm ~/.local/share/<job>/expires_at` — next run re-stamps
    now+EXPIRY_DAYS) and say explicitly that bumping EXPIRY_DAYS alone
    does not renew; the alternative (make `--apply` genuinely re-stamp on
    an EXPIRY_DAYS change) needs an `--apply` run to verify, so it's
    filed as a proposal in the 2026-07-26 report, not built blind. Item
    2: `lib/sweep-loop-common.sh` checks expiry BEFORE the clone/secrets
    work, writes a real `===`-delimited run record ending in
    `=== skipped (expired <ts>)` (a completion status
    `build_status_report` already recognizes, so expiry now SHOWS as the
    last run), and exits 3 (distinct from success/fatal; nothing keyed on
    the old exit 0); `bin/usage-paced-runner.sh` skips an expired
    participant pre-dispatch with a SKIP-EXPIRED log line naming the
    renewal (state dir derived from the `<job>-loop.sh` wrapper naming
    convention; non-matching commands fail open and dispatch as before).
    Item 3: `cmd_sweep` gained a seventh pass flagging every tripped
    `*/expires_at` stamp (with an explicit all-clear line when none are),
    and `cmd_glance` a matching footer block, keyed by JOB_NAME since
    state dirs are per-job. Verified with isolated-HOME harnesses (fake
    claude/notify-send shims, throwaway bare repo, SCHED_ROOT sed'd to a
    tmp root — 27 checks total across expired/fresh/clean-run/runner-skip
    /both-views scenarios). Two latent glance bugs found by the fixture
    and fixed in the same pass: `projects()` emitted a bogus `*` project
    on an unmatched glob, and a project with no `focus/<proj>.md` either
    crashed glance under `set -u` or silently inherited the previous
    project's backlog count for its ETA.

- **2026-07-25 00:47 (via `scheduler -i`):** look into crt and update your references to the VM which are deprecated

- **2026-07-25 (paced cycle, routing note):** the `**Headline:**` report
  convention (see "Current focus" item 3's cross-project note above) now
  has a source-of-truth template (`examples/nightly-batch.md.template`)
  but hasn't been propagated to any already-running project's real
  `.claude/commands/nightly-batch.md` — scheduler can't edit outside this
  repo. Routing to realisateur's intake, same pattern used for every
  other cross-project fix filed in this backlog: propagate to chezz,
  wtul, home-assistant, vkv-inventory (and any other registered project
  with its own nightly-batch command) one at a time, verifying each
  project's `LATEST.md` actually starts with the new line before moving
  to the next.

- **2026-07-24 22:33 (via `scheduler -i`):** pinning crt on dexter is not right. that's based on old role of dexter as part of the actual crt build. current crt work can happen on either machine

- **2026-07-24 21:10 (realisateur session, BLOCKERS.md sweep):** Root
  cause found for tonight's stale-BLOCKERS.md entries (wtul Discogs/
  fpcalc, crt MIDI/Benchy/DAC, crt Gallery architecture — all folded in
  or resolved this session): the header's own sweep contract ("moving a
  resolved entry to Recently resolved is `/ideate`'s job") is real but
  has no trigger — it only fires when a human notices or an `/ideate`
  pass happens to touch that exact project, so entries rot silently
  otherwise (wtul's fpcalc/token work landed and was marked done in its
  own `.claude/FOCUS.md` days before BLOCKERS.md caught up). **Cheap win
  shipped tonight:** `bin/blockers-freshness-check.sh` (zero-AI-cost,
  same offline-first-checks.md discipline as `collect-feedback.sh`) —
  flags any active BLOCKERS.md bullet whose newest mentioned date is
  >`STALE_DAYS` (default 14) old, AND cross-checks each flagged
  project's own FOCUS.md git-commit date against that bullet's newest
  date (catches exactly the wtul shape: FOCUS.md moved on, BLOCKERS.md
  didn't). Findings are signals, not verdicts — same convention as
  milestone-audit.sh/hygiene-lint.sh/ecosystem-survey.sh. **(1) DONE
  2026-07-24 (paced cycle): wired into `cmd_sweep` in `bin/scheduler`**
  (not `morning-report.sh`, which is deprecated in favor of `scheduler` —
  see its own header) as a sixth pass, same "print a WARN block only when
  something's actually flagged" shape as the fifth (migration-check) pass
  right above it: runs `bin/blockers-freshness-check.sh`, and on nonzero
  exit prints its full output under an `== [blockers-freshness] ... ==`
  heading; silent on a clean sweep. Verified: `bash -n bin/scheduler`
  clean; ran the check script directly (`0/3` flagged today, real
  BLOCKERS.md is current); forced the failure path with
  `STALE_DAYS=-1 bash bin/scheduler sweep` and confirmed the WARN block
  renders correctly (crt/wtul both correctly flagged at 0 days old with
  a negative threshold). **(2) A genuine semantic cross-file consistency check
  (does this BLOCKERS.md bullet's *claim* still match reality, not just
  "did a date pass") needs real judgment, not grep — that's the existing
  "`BLOCKERS.md`-as-computed-view redesign" backlog item above, this
  script is a cheap partial step toward it, not a replacement for it.
  (3) A real, separate, currently-open blocker surfaced by this same
  sweep: wtul's `.claude/QUESTIONS.md`/`FOCUS.md` are harness-gated as
  "sensitive files," refusing writes from 3 consecutive unattended
  `/wtul-batch` runs (2026-07-24) — needs a human call (grant a
  permission rule for those two files, or move them out of `.claude/`)
  before `/wtul-batch` can file its own backlog again; see BLOCKERS.md's
  `## wtul` section for the full writeup, not resolved by this pass.

- **2026-07-24 20:22 (via `scheduler -i`):** Heads up from realisateur's /ideate (2026-07-24): schedule/aedile.conf and schedule/vkv-inventory.conf both set PROJECT_REPO_PATH to a zach@mandark local working copy (/home/zach/Documents/vkv/wavebucks/aedile, /home/zach/Documents/vkv/inv/inventory-app) that Zach says is scheduled to be sunset/closed. Once that happens, sync-crontab.sh's focus/<project>.md and questions/<project>.md symlinks (and 'scheduler status aedile'/'vkv-inventory') will point at a dead path. Both projects' actual dispatch already runs under svc-vaporwave's own fresh-clone checkout, independent of this path -- it's only used for the FOCUS.md/QUESTIONS.md symlink convention. Realisateur has separately decided (see its own FOCUS.md) to stop direct-cross-writing these two once mandark closes and route via this same -i front door instead. Suggest: when the mandark copies actually close, either point PROJECT_REPO_PATH at nothing (accepting no symlink for these two) or at a small dedicated clone -- scheduler's call, not decided here.

- **2026-07-24 12:52 (via `scheduler -i`):** develop integration with google keep, crt, phomemo printer, home assistant, to manage zach's domestic tasks, blockers, etc. google keep maintains a list of curated todos of registered programs and other, phomemo prints out todo list, has omr scanner hooks, omr scanner reads printed form and checks off items.

- **2026-07-24 03:40 (via `scheduler -i`):** Two real bugs found 2026-07-24 while setting up realisateur's milestone convention, both stemming from the same wrong assumption: aedile has NO git repo, treated as migrated/defunct. That was wrong -- verified directly (should have done this before writing it down, per tonight's earlier credential-gap lesson): aedile IS a real, actively-committed project (5 recent commits, e.g. 'aedile: DM-tier bump/triage tuning'), just tracked as a subdirectory of the wavebucks monorepo at /home/zach/Documents/vkv/wavebucks (its own .git lives at the parent, not at aedile/ itself). Bug 1: bin/scheduler's git-health check (~line 622) uses [ -d "$repo_path/.git" ], a literal directory check that fails for any PROJECT_REPO_PATH pointing at a subdirectory of a repo rather than a repo root -- same failure mode would hit any future monorepo-subdirectory project, not just aedile. Fix: use 'git -C "$repo_path" rev-parse --is-inside-work-tree' (or similar) instead of the literal .git-dir check. Bug 2: aedile already uses the .scheduler/ subdirectory layout in practice (aedile/.scheduler/FOCUS.md is real, git-tracked, actively updated) but schedule/aedile.conf never declares SCHEDULER_SUBDIR=".scheduler" -- so any tool reading that field (realisateur's milestone-audit.sh, sync-crontab.sh's own symlink logic) misses it. Fix: add SCHEDULER_SUBDIR=".scheduler" to schedule/aedile.conf to match its real layout. Routing both here per realisateur's ideate.md step 5 front door (engine detection logic + registration conf) rather than hand-editing scheduler's own files from realisateur.
  **Both DONE.** Bug 2 was already fixed by a prior pass (`schedule/aedile.conf`
  already carries `SCHEDULER_SUBDIR=".scheduler"`, confirmed by reading it).
  Bug 1 fixed this paced cycle (2026-07-24): added a shared `is_git_repo()`
  helper to `bin/scheduler` (`git -C "$path" rev-parse --is-inside-work-tree`)
  and swapped it in at the two call sites that matter -- `cmd_sweep`'s
  first pass over every registered project's `PROJECT_REPO_PATH`, and
  `build_status_report`'s git-health check (used by `scheduler status
  <project>`). The two dedicated-clone globs (`~/.local/share/*/repo`)
  were left on the old `[ -d "$path/.git" ]` check on purpose -- those are
  always scheduler-managed fresh clones at a repo root, never a
  subdirectory, so the bug can't occur there. Verified live against the
  real aedile path: the old check silently returned false (skipped aedile
  entirely, the exact bug reported), the new `is_git_repo` correctly
  returns true; `scheduler status aedile` now shows real git-health output
  ("clean, up to date with origin") instead of the old false "not a git
  repo" line; `scheduler sweep` ran clean end to end, read-only, no state
  changed. `bash -n bin/scheduler` clean.

- **2026-07-24 01:33 (via `scheduler -i`):** Root cause found 2026-07-24 for the 'stranded local commit' pattern seen on chezz and wtul nightly-batch runs (previously misdiagnosed by realisateur's /ideate as a dedicated-clone-vs-working-checkout push race): it's a credential gap, not a race. The dispatch environment can push to local bare remotes (crt, realisateur, gardien, senechal) fine, but has no SSH credentials for GitHub-hosted remotes (chezz + wtul both use git@github.com:hf7y/...). Their nightly-batch runs commit successfully but the push step silently fails/is skipped, leaving commits local-only until a human or interactive Claude Code session (which does have working credentials) pushes them by hand -- confirmed tonight by manually pushing wtul's 51e2545 and chezz's 0189195, both landed cleanly. Proposal: either (a) give the dispatch environment's SSH agent/keys access to the github.com host (deploy keys or agent forwarding, scoped read+write to just these two repos), or (b) if that's intentionally not wanted (e.g. credential-scope hygiene), make the failure LOUD in scheduler status / sweep.log instead of the current silent 'pushed: no' with no reason given, so it reads as 'needs a human push' rather than looking like a generic failed run. Either is scheduler's call -- routing here per realisateur's ideate.md step 5 front door rather than hand-fixing dispatch config from realisateur.
  **Partial progress, option (b), 2026-07-24 paced cycle:** (a) is human-only
  (deploy-key generation/install, decided + queued in DESIGN-NOTES.md's
  2026-07-24 "chezz/wtul push-gap fix" entry -- not agent-executable). For
  (b): `lib/sweep-loop-common.sh` and `scheduler status <proj>` already
  surfaced a distinct `WARNING: local commit made but NOT pushed` line
  per-run and `cmd_sweep`'s dedicated-clone pass already flagged any
  registered project sitting ahead-of-origin unpushed -- but both required
  opening a specific project or running `sweep` separately to notice.
  `cmd_glance` (bare `scheduler`, the view actually opened daily) now also
  checks each project's own dedicated clone and prints a
  "stranded local commits" hint line naming every affected project, not
  just chezz/wtul. Verified live: fabricated an empty test commit in
  chezz's real dedicated clone, confirmed the hint fired with the right
  project/count, `git reset --hard` back to the original SHA (repo left
  clean, `git status` confirmed). `bash -n bin/scheduler` clean, no
  shellcheck available in this environment to run additionally.

- **2026-07-23 23:55 (via `scheduler -i`):** Unify a status/admission taxonomy across the ecosystem: 'active vs parked vs waiting' for vision/idea items is the SAME underlying need as the BLOCKERS.md blocking/waiting/fyi taxonomy (the parked 'Spec-out-a-more-principled-eco' idea). Proposal: one shared status vocabulary + convention that serves both vision-backlog items (FOCUS.md) and blockers (BLOCKERS.md), so counts reflect real commitments, not the free-growing reservoir. Surfaced by realisateur /ideate 2026-07-23 vision-debt strategy pass (see realisateur FOCUS.md) — this is the mechanism that makes milestone-gated parking legible in glance/status views. Realisateur owns the vision-item half; this -i note is for scheduler's convention/engine half.

- **2026-07-23 12:50 (via `scheduler -i`):** eventually during high season, we'll need google calendar integration. a way to invite small teams to their meetings, input deadlines, etc

- **2026-07-23 09:24 (via `scheduler -i`):** add a column in scheduler noargs view to show last run as well as next up. last run timestamp, next run timestamp. specific next up task text can be moved to projects individual status view to save space, though open jobs can stay.
  **Partial progress, 2026-07-24 paced cycle:** `cmd_glance` (bare `scheduler`)
  now has a `LAST RUN` column — age of that project's own
  `~/reports/<project>/LATEST.md` (Xm/Xh/Xd ago), the same file `scheduler
  report <project>` opens, so it's a proxy for "last completed run" rather
  than a new tracked timestamp. Verified live: ran `scheduler` and confirmed
  every registered project shows a plausible age (crosschecked wtul's "1h
  ago" against `stat` on its actual `LATEST.md`), `bash -n bin/scheduler`
  clean. **NEXT-run timestamp deliberately deferred, not built this cycle:**
  a real ETA needs expanding `schedule/_paced.conf`'s weighted participant
  list against the live `rotation.idx` pointer (for paced projects) plus
  parsing each `schedule/<proj>.conf`'s cron fields (for fixed-time ones) --
  two different mental models to reconcile correctly, not a one-line add
  like LAST RUN was, and getting it subtly wrong (a false "next in 5 min")
  seemed worse than leaving NEXT UP as the existing non-ETA backlog-position
  label. Left as open backlog, not attempted half-verified.

- **2026-07-22 (diagnosed via wtul questions-pane investigation):** audit
  every project's nightly-batch/questions convention for the same gap just
  fixed in wtul and here: `services/vkv-inventory/command-nightly-batch.md`
  never runs `collect-feedback.sh --consume` against its own
  `.claude/QUESTIONS.md` either (chezz already has it; home-assistant
  doesn't use QUESTIONS.md at all, so N/A). Propagate the same Orient-step
  fix wtul-batch.md and this file's own nightly-batch.md just got, or flag
  vkv-inventory's owner (realisateur, per the FOCUS/ROADMAP reconciliation
  it's already doing for wtul) to add it. Root cause was: QUESTIONS.md is
  append-only by convention, and nothing consumed a user's inline `> `
  reply unless a project's batch command explicitly ran collect-feedback
  against it — an easy step to drop when adapting the template for a
  no-tracker project (as wtul did).
  **CONFIRMED 2026-07-24 paced cycle** (was "unconfirmed" — this cycle
  read-only-verified, did not edit): checked vkv-inventory's own dedicated
  clone at `~/.local/share/vkv-inventory-nightly-batch/repo/.claude/commands/nightly-batch.md`
  directly (reading outside this repo is fine, editing isn't — same rule
  already used for `~/.local/bin/*-loop.sh` wrappers elsewhere in this
  file) — no `collect-feedback.sh --consume` call anywhere in it, gap is
  real, not stale. Scheduler can't fix it directly (outside this repo);
  routing stays as described above — this line is scheduler's front-door
  record for realisateur to pick up, per the same pattern the "stranded
  local commit" backlog item below already uses.

- **2026-07-22 15:54 (via `scheduler -i`):** the push of new ideas to archives has a little lag after ideas submit. can that happen after the command sends, and push a notification via kde or similar, perhaps waiting in case a batch of ideas comes in worth pushing all at once. clones should be aware of uncommited work, or should check for them, in case a race condition emerges. but that's an unecessary ui friction point for when I'm looking to drop several ideas in a row

- **2026-07-22 15:52 (via `scheduler -i`):** wtul's 7-18 note about NEEDS HANDS-ON HARDWARE VERIFICATION is properly a blocker, not a question. figure out if scheduler is responsible for enforcing this, or wtul needs a note on what counts as what.

- **2026-07-22 15:49 (via `scheduler -i`):** propagate to other projects the next up convention of a short (<10 char) summary of each action. that way actions are ready with a readable title, short description that scheduler can easily grab.

- **2026-07-22 15:48 (via `scheduler -i`):**   (* = changed since you last opened it here. QUESTIONS is unopened/total --
  total includes ones you've already replied to inline but whose project run
  hasn't processed yet; see 'scheduler questions <project>' or the man-page-ish
  notes in scheduler — 2026-07-22 15:48 (paced rotation, dispatched whenever usage-gate.sh has spare quota)

  PROJECT          QUESTIONS  BLOCKERS  NEXT UP
  (* = changed since you last opened it here. QUESTIONS is unopened/total --
  total includes ones you've already replied to inline but whose project run
  hasn't processed yet; see 'scheduler questions <project>' or the man-page-ish
  notes in `scheduler` usage/docs/feedback-tags.md for what 'total' counts.
  NEXT UP is 1/<FOCUS.md backlog size>: <top item's title> -- NOT an ETA,
  just what the next run reads first; paced projects run whenever
  usage-gate.sh has spare quota, not on a fixed clock.)
  crt              0/1        4         1/9: Check crt-vm's own `.claude…
  wtul             *3/3       1         -
  vkv-inventory    *3/5       -         1/3: End every nightly run with …
  aedile           -          2         1/5: Only touch `aedile/`.
  chezz            *1/3       -         -
  gardien          1/1        -         1/4: RAID mount guard rail
  home-assistant   *1/3       -         -
  senechal         *1/1       -         1/4: Broaden the default watch l…
  groc-mangr       -          -         -
  nine-speakers    -          -         -
  realisateur      -          -         1/3: Idea-incubation "steward"/"…
  scheduler        -          -         1/36: What actually pulled toward…
  sequestria       -          -         -
  vim-arcade       -          -         1/4: vim

-> scheduler blockers   (or: scheduler -b)
-> scheduler focus/questions/report <project> to jump straight in usage/docs/feedback-tags.md for what 'total' counts.
  NEXT UP is 1/<FOCUS.md backlog size>: <top item's title> -- NOT an ETA,
  just what the next run reads first; paced projects run whenever
  usage-gate.sh has spare quota, not on a fixed clock.)
 move all this text to a man page, reduce to a single line summary above the column headers. formatting should leave blank spaces so asterisks don't nudge fractions over. try to get all the / to line up in a column if that's easy. same for next up. aim to have the / line up and the : line up, pad with whitespace if necessay
  **DONE 2026-07-25 (paced cycle), all three asks:** (1) the 13-line
  in-glance explanation block collapsed to one legend line above the
  column headers, full text moved to a real maintained man page —
  `docs/scheduler-cli.md`, opened by a new `scheduler man` (`-m`)
  subcommand (this also starts the "man page for scheduler" half of the
  13:59 entry below; the terse command list deliberately stays ONLY in
  `scheduler --help` so the two can't drift). (2) QUESTIONS/BLOCKERS
  now render with a reserved 1-char `*` slot + right-aligned numerator,
  so a star never nudges the fraction and every `/` lands in the same
  column. (3) NEXT UP's total is right-aligned (`1/ 7:` vs `1/28:`) so
  the `/` and `:` both line up. The man page also documents the `*`
  convention plainly (the 19:56 entry's ask — its `+1✓` complaint
  refers to notation that no longer exists in the current script, and
  the proposed `?` marker is still not built, deliberately not
  documented as if it were). Verified live: before/after runs of
  `scheduler` (real data), a scratch-`$HOME` run to force starred rows
  (slash column holds), `PAGER=cat scheduler man` renders the doc, a
  copy run from a docs-less directory fails loud with a clear error
  (the deployed-symlink fallback path), `scheduler notaproject` still
  errors, `bash -n` clean.

- **2026-07-22 15:44 (via `scheduler -i`):** separate vaporwave and zach jobs which are running on different accounts visually since they have different quotas. print current quota information at the top of each section for context as well as an estimate for when the next job would run based on current quota info. non-ai call. generally scheduler bin interaction should be non-ai unless explicitly requested via flag

- **2026-07-22 (folded from questions/scheduler.md, originally raised
  2026-07-20 by crt's own session building a voice-console morning-report
  presenter): two findings, human-answered, filed here as the answers
  directed.**
  1. **`bin/morning-report.sh` hangs (120s timeout, reproduced twice,
     standalone, unrelated to crt).** Not traced yet — likely a slow/
     unreachable per-project `DEPLOY_FRESH_CMD` probe (home-assistant's
     own report already documents an unreachable-Pi/network-mismatch
     scenario matching this shape). **Human direction: fold tracing this
     into the next batch pass, BUT note explicitly that scheduler's
     report shape is mid-redesign (FOCUS item 0, the merged
     report+questions file) — morning-report.sh itself may end up
     superseded rather than worth deep-fixing.** Whoever picks this up
     should check item 0's status first; a quick trace-and-patch is
     still worth doing regardless (a hanging script is a real problem
     even mid-redesign), just don't over-invest in it.
     **RESOLVED 2026-07-25 (paced cycle) — trace found the hang was
     ALREADY fixed, plus one residual vector patched.** The hang this
     entry reports was traced+fixed 2026-07-20 in `a224b41` (the
     deploy-freshness loop sourced `_paced.conf` as if it were a project
     conf, executing its pipe-delimited participant lines as shell and
     invoking a live wrapper — same class as `build-services-view.sh`'s
     `61f7dbd`); the crt session's two reproductions predate that fix
     landing. Confirmed today: repeated full runs complete in ~0.4s. The
     deprecation header's "known unresolved hang bug" line (written
     hours AFTER the fix, `ab075da`) was stale on arrival — corrected in
     place. The suspected-but-not-actual cause this entry names (an
     unreachable `DEPLOY_FRESH_CMD` probe) IS still a real future hang
     vector though — patched same cycle: probes now run under
     `timeout` (`DEPLOY_PROBE_TIMEOUT`, default 15s), with a timed-out
     probe reported as its own distinct "could NOT verify" line rather
     than mislabeled "deploy pending". Verified with a fabricated
     4-conf harness (fresh/stale/hanging/conf-var-referencing probes:
     3.05s total with a `sleep 300` probe present, correct message per
     state) and a before/after diff of the real repo's output
     (byte-identical, crt's real pending-deploy line unchanged). Kept
     deliberately shallow per the direction above — no deeper
     investment in a deprecated script.
  2. **Standardize a machine-parseable per-project headline field in
     report templates — human-approved ("yes there should be
     standardization of report formats like that").** Concrete ask: every
     project's `LATEST.md` template emits a literal `**Headline:** ...`
     line near the top, so any downstream consumer (crt's voice console
     presenter, or anything else aggregating across projects) gets a
     reliable one-line summary instead of guessing from the first
     non-empty line (today's heuristic, which reads poorly for reports
     that open with prose instead of a title). Cross-project change —
     touches the shared report template every project's nightly-batch
     writes into, not just scheduler's own files.
     **Source-of-truth half DONE 2026-07-25 (paced cycle):**
     `examples/nightly-batch.md.template` step 6 now requires the
     report's first line to be exactly `**Headline:** <one sentence>`,
     matching `bug-sweep.md.template`'s existing `## Summary` convention
     in spirit. Tried to also update this project's own
     `.claude/commands/nightly-batch.md` to dogfood it — confirmed live
     that `.claude/**` writes are still hard-refused in this unattended
     run (the same permission-gate finding item 2/3 above already
     documents), so that specific file needs a human or interactive
     session to touch. **Not yet propagated to any other already-running
     project's real `.claude/commands/nightly-batch.md`** (chezz, wtul,
     home-assistant, vkv-inventory, …) — same "scheduler can't edit
     outside this repo" boundary used everywhere else in this file;
     routing to realisateur's `-i` front door is the right next step for
     that half, not something to hand-fix from here.

- **2026-07-22 15:19 (via `scheduler -i`):** should the idea intake in scheduler actually file things to realisateur first so it can triage/prioritize? or actually file in both locations. should realisateur properly run before other jobs within a certain window? or should those ideas await implementation until realisateur analyses them? wondering how ideas intake should evolve based on the evolving scheduler/realisateur split. drop questions to me about this if appropriate but also pick off low hanging fruit if an obvious principled first step or steps is available right now

- **2026-07-22 14:17 (via `scheduler -i`):** committed locally in /home/zach/Documents/Project Archive/scheduler -- run 'git -C /home/zach/Documents/Project

- **2026-07-22 14:13 (via `scheduler -i`):** fix the graphical display of the no args schduler view. columns don't really make sense. implement the merger of questions and blockers into one view (at least inside this bin utility ahead of formal merge). drop a line explaining + and ✓ convention. introduce estimated run time, estimated usage, and also number of tasks open. number of tasks expected to run

- **2026-07-22 (Zach, via chat): shipped the cheap slice of priority
  ordering — `bin/scheduler`'s no-arg glance now sorts rows by
  `q_unanswered + blocker count` descending instead of conf/registration
  order** (see [[scheduler-usage-pacing]]-adjacent 13:59 backlog entry
  above for the fuller quota/ETA-aware target this is a stand-in for).
  Two related pieces scoped but deliberately NOT built this pass:
  - **DONE 2026-07-24 (paced cycle): tab-completion for `scheduler
    <project>`/subcommands.** `bin/scheduler-completion.bash` — a
    `complete -F` function completing the subcommand list on word 1, and
    project names (re-globbing `schedule/*.conf` the same way `bin/
    scheduler`'s own `projects()` does, so it can't drift) on word 2 for
    every subcommand that takes a project arg. Not auto-sourced anywhere
    (this repo doesn't touch shell rc files) — README now documents the
    one `source` line to add. Verified by sourcing it and driving
    `_scheduler_completion` directly against fabricated `COMP_WORDS`/
    `COMP_CWORD` (word-1 prefix `foc` → `focus`; word-2 after `focus` →
    full project list; word-2 after `-q` with prefix `cr` → `crt`);
    `bash -n bin/scheduler-completion.bash` clean.
  - **DONE 2026-07-25 (paced cycle): `scheduler <project>` direct
    shorthand.** A bare registered project name (no verb) now dispatches
    to `cmd_status` — `scheduler crt` == `scheduler status crt` — since
    `build_status_report` already covers focus/questions/blockers/last-run
    in one screen; the only missing piece was the entry point, not a new
    truncated view (that fuller "merged report" shape stays item 0's
    scope, not duplicated here). Anything not a registered project name
    still hits the existing "unknown command" error. Found and fixed a
    real bug while verifying: the first implementation piped `projects |
    grep -qx`, which under this script's `set -o pipefail` reports the
    whole pipeline as failed whenever `grep -q` exits early on a match
    (SIGPIPE hits `projects`' still-writing `echo`) — silently took the
    "unknown command" branch even for real project names. Fixed by
    capturing `projects`' output into a variable first, then matching
    against it with a herestring — same SIGPIPE-guard class of bug this
    file's own build-discipline checklist calls out. Verified: `bash -n
    bin/scheduler` clean; ran `scheduler crt` and confirmed it printed the
    real status report; ran `scheduler notaproject` and confirmed the
    original "unknown command" error still fires. README's `bin/scheduler`
    row updated to mention the shorthand in the same commit.
  **Priority-adjustment (a `scheduler priority <project> <n>`-style
  command) and bug/feature tagging on backlog items stay vision-level,
  not scoped further here** — Zach's own framing this session was
  explicitly "later," and both need a real schema decision (where does a
  priority/tag live — a conf field? an inline prefix agents must honor
  when writing `-i` entries?) before either is buildable, not just an
  implementation pass.

- **2026-07-22 14:02 (via `scheduler -i`):** revisit integration with realisateur. realisateur should not promote ideas to scheduler until out of an incubation period. this prevents the scheduler status from getting crowded with nacent ideas. potential automated flag whereby scheduler suggests projects migrate to realisateur if they're underdeveloped (few files, nothing pending). eventual symmetrical structure to move projects to archive once out of development

- **2026-07-22 13:59 (via `scheduler -i`):** streamline the cli flow. scheduler no args should produce what's scheduled, in order of priority, with information about next run, time/cost etc. scheduler <project> should tab-complete. should show more detail about project including next tasks/requests in order of priority. flag design can remain for backwards compatibility. focus questions blockers should all be called out in the project view (truncated with suggested command to expand if too many lines). should have an easy way to promote a project's urgency in both the main scheduler view and it's individual project. start developing and maintaining a man page for scheduler that explains its use.
  **Man-page half DONE 2026-07-25 (paced cycle):** `docs/scheduler-cli.md`
  + `scheduler man` (`-m`) — see the 15:48 entry's DONE note above for
  scope + verification. The rest of this entry (priority-ordered rows
  landed 2026-07-22; ETA/next-run/cost columns, urgency promotion) stays
  open as already tracked elsewhere in this backlog.

- **2026-07-22 (Zach, via chat): `bin/scheduler` no-args glance should be
  priority-ordered, not registration-ordered.** Top row = whatever's next
  scheduled to actually run (soonest dispatch under the pacing governor),
  not just the first project alphabetically/by conf order. Each row
  should show: cached quota state (reuse the last `usage-gate.sh` verdict
  from `usage-paced-runner.sh`'s log — do NOT spend a fresh `claude`
  call just to render the glance), an estimated next-run time (derived
  from the burn-line trend in that log), a rough estimated usage cost for
  that run if known, and open-job count. Motivating moment: today's
  glance (see `bin/scheduler` no-args output) shows question/blocker
  counts per project but nothing about scheduling order or quota, so a
  "why hasn't anything run" question requires manually reading
  `~/.local/share/scheduler-paced-runner/run.log` by hand.

- **2026-07-22 (Zach, via chat): fixed a real bug in `bin/scheduler`'s
  `usage()` — the heredoc at line 17 (`cat <<EOF`) was unquoted, so bash
  tried to expand the literal backticks in the help text itself
  (`` `-i` `` at line 42, `` `> ` `` at line 48) as command substitutions,
  producing `-i: command not found` and a syntax error on `` `> ` ``.
  Fixed by quoting the delimiter (`cat <<'EOF'`) since that heredoc has
  no variables to interpolate. Also confirmed the "scheduler doesn't
  have anything pending" symptom from the same report is NOT a bug: the
  paced runner is correctly HOLDing because usage is running ahead of
  the burn-line (43% used vs 25% target as of 13:30) — working as
  designed, see [[scheduler-usage-pacing]]. One transient
  `verdict=ERROR reason=no_headers http_code=401` at 10:45:59 self-
  recovered next tick; consistent with the known OAuth-token-expiry
  pattern, not worth chasing further.

- **2026-07-22 (Zach, via chat): move toward auto-push with revert-on-
  review, for changes that are cheaply and safely reversible — not
  built yet, flagging for a future cycle to design/scope.** Motivating
  moment: after `bin/scheduler status` shipped (commit `bc88ec8` here,
  `4399728` in realisateur), Zach pushed both by hand and named the
  friction directly — every commit in this repo today is exactly the
  kind of change (docs, a new CLI subcommand additive to existing ones,
  a FOCUS.md note) that's trivially `git revert`-able, so requiring a
  human push for each one is pure latency, not a real safety gate.
  Candidate shape (needs real design, not assumed as final): auto-push
  by default for changes below some risk bar (e.g. commits that only
  touch docs/`.md` files, or commits from a review-gated worktree cycle
  that already passed whatever gate that cycle has), paired with a fast,
  reliable revert path (`git revert` + re-push, not `reset --hard`
  against a shared branch) if a human review afterward says no. Needs to
  answer, explicitly, before landing: which projects/branches this
  applies to (this repo's own self-hosting model — see "This project
  dogfoods its own system" below — currently never auto-pushes at all,
  on purpose); what counts as "safely revertible" (a docs/config change
  is not the same risk class as anything touching real credentials,
  external side effects, or another human's shared branch); and whether
  the bar is a hard rule or something `bin/scheduler` itself surfaces as
  a suggestion per commit rather than auto-deciding. **Do not build the
  auto-push mechanism itself without that design pass — this entry is
  the flag, not the go-ahead.**

  **DONE, narrower scope, 2026-07-22 (Zach, via chat, direct go-ahead
  this time):** the risk bar this entry asked for turned out to be
  simple for the one path that actually mattered today —
  `cmd_commit_file()` (shared by `scheduler -i` and `scheduler sweep`)
  only EVER commits one markdown file at a time, already exactly the
  "trivially revertible" class described above. It now auto-pushes right
  after committing, skipped (falls back to the old local-only message)
  if the repo is behind origin or the push itself fails — never forces,
  never touches anything but that one file. Verified end-to-end against
  the scheduler repo itself. **Still explicitly NOT covered by this
  change: this repo's own self-hosting nightly-batch/paced-dev-cycle
  push policy** (see "This project dogfoods its own system" /
  "Push policy" above) — that's a different code path with its own
  separate, already-documented rules; this entry is only about the
  `scheduler -i`/`sweep` idea-and-doc-edit path. A broader auto-push
  policy for other kinds of commits (code changes, non-.md files) is
  still not designed and still needs the fuller pass this entry
  originally asked for.

- **⚠️ FLAGGED, NOT BUILT (2026-07-21, human's own idea, self-caught as
  "ideating mid-execution" — genuinely worth revisiting later, not
  acted on now):** `.gitignore`-ing `.claude/` (used by wavebucks and
  presumably other projects to keep Claude Code's local state out of a
  shared repo) is the wrong TOOL for that goal, because it also silently
  breaks automation that needs those files to survive a clone/worktree
  (exactly what just happened to aedile's `FOCUS.md`/`QUESTIONS.md` —
  see tonight's fix, moved to `.scheduler/` instead). **Better shape: a
  GitHub-level display/visibility mechanism** (e.g. `.gitattributes`
  `linguist-generated`/`linguist-vendored` to hide from stats/diffs, or
  simply accepting that a PRIVATE repo's collaborators seeing automation
  files isn't actually the risk "public" implies) instead of excluding
  the files from git tracking altogether on the local machine. Worth a
  real look at whether any OTHER registered project also blanket-
  `.gitignore`s `.claude/` and has the same latent bug, not just
  wavebucks/aedile.
  **SURVEYED 2026-07-25 (paced cycle) — read-only, confirms the bug is
  real and still live for aedile specifically, nobody else.** Checked
  every registered project's repo-root `.gitignore` for a `.claude/`
  pattern: `crt` and `wtul` only ignore specific per-developer state
  files (`settings.local.json`, a lock file) — narrow, intentional,
  not the bug this entry describes. Only `wavebucks` (aedile's parent
  monorepo) blanket-ignores the whole `.claude/` directory
  (`/home/zach/Documents/vkv/wavebucks/.gitignore:10`). Confirmed live
  with `git ls-files aedile/.claude` (empty — zero tracked files) and
  `git status --ignored` (`!! aedile/.claude/`, the entire tree
  ignored). This is NOT just the historical FOCUS.md/QUESTIONS.md case
  already fixed by moving to `.scheduler/` — **aedile currently has two
  real, undated-in-git files sitting only in this ignored directory**
  (`aedile/.claude/QUESTIONS.md`, `aedile/.claude/NEXT-STEPS.md`, both
  with real content as of this survey) that would silently vanish on
  any re-clone or worktree reset, with no git history to recover them
  from — the exact live risk this entry warned about, not a closed
  case. Scheduler can't edit aedile's repo or `.gitignore` (outside
  this repo); routing to realisateur's intake per this file's usual
  cross-project pattern: either move those two files' real content into
  aedile's already-adopted `.scheduler/` convention, or narrow
  wavebucks' `.gitignore` the way crt/wtul already do. No other
  registered project needs this fix.

- **2026-07-20 22:20 (via chat): full revisit of the svc-vaporwave split
  needed — bigger than the observability-only fix queued just above.**
  Two more pieces, not yet scoped:
  1. **svc-vaporwave's job runs should surface in zach's normal
     workflow** (`bin/scheduler` glance, not just raw log-diving) — not
     just the stranded-run detection queued above, but real first-class
     visibility: next-run time, last-run status, open questions, same as
     every zach-side project gets today.
  2. **Eventually move `usage-gate.sh` pacing onto svc-vaporwave too** —
     right now aedile/vkv-inventory run on fixed cron times with no
     burn-rate pacing at all (unlike zach's paced projects), which was
     an acceptable simplification to get the migration done tonight, not
     a permanent design choice.
  Deliberately NOT designed further here — real design work for a future
  session, and should incorporate/complete the scoped observability fix
  above rather than duplicate it.
  **Amended 2026-07-21 (via chat): the goal is now real CONTROL, not just
  observability** — give scheduler eventual actual authority over
  svc-vaporwave's jobs (scheduling/dispatch), not only visibility into
  their state. Still explicitly NOT a green light to jump straight to a
  cross-account daemon (see the rejection reasoning in the item just
  above) — this raises the eventual ceiling of the design, it doesn't
  change tonight's "scoped fix first" sequencing.

- **2026-07-20 22:15 (via chat, queued for later): extend cross-account
  observability to svc-vaporwave, WITHOUT promoting scheduler to a
  machine-wide/daemon service.** Context: aedile and vkv-inventory's Tier
  2 batch jobs migrated to a separate headless account (`svc-vaporwave`,
  its own Claude subscription, own independent crontab -- entirely
  outside `schedule/*.conf`/`sync-crontab.sh`'s control now, by design,
  to distribute usage) same session. Real gap this created:
  `scheduler sweep`'s stranded-run/`.active`-marker detection and
  `morning-report.sh` only ever read `$HOME/.local/share/...` -- i.e.
  zach's own home -- so a hung or crashed cycle on `svc-vaporwave` is
  currently invisible to any of zach's own monitoring (reports themselves
  ARE already visible, via the `/srv/vaporwave-reports` shared-group
  symlink trick built same session -- this is specifically about
  mid-run/stranded-run detection, not reports).
  **Explicitly rejected as overkill for this gap: promoting scheduler to
  a root-owned/machine-wide service.** Would directly contradict this
  same file's own "keep cron, not a daemon" decision, reaffirmed twice
  this same day -- the named revisit trigger was `usage-paced-runner.sh`
  growing genuinely complex, not account count, and a second Claude
  account is not that trigger. Jumping to a cross-account daemon now
  would be exactly the "vision debt" pattern already called out
  elsewhere in this file.
  **Scoped fix instead:** extend the existing `vaporwave-reports` shared
  group (group `vaporwave-reports`, members `zach`+`svc-vaporwave`,
  setgid dirs under `/srv/vaporwave-reports/`) to also cover
  `svc-vaporwave`'s `~/.local/share/scheduler-registry` dir -- same
  group-readable pattern, no root needed, no new daemon. `scheduler
  sweep` on zach's side additionally globs that path for stale
  `.active` markers alongside its own. Purely additive observability,
  doesn't touch orchestration/timing on either account.

- **DONE 2026-07-24 (paced cycle):** `lib/sweep-loop-common.sh`'s
  `notify-send` calls (queued 2026-07-20, no `2>/dev/null || true` guard,
  unlike aedile's bespoke wrapper) hung on a headless account with no
  D-Bus/desktop session (confirmed on `svc-vaporwave`: `Error calling
  StartServiceByName for org.freedesktop.Notifications: Timeout was
  reached`) instead of failing fast. Guard added to all 3 calls in
  `lib/sweep-loop-common.sh`, plus 3 more of the same unguarded shape
  found in `bin/scheduler-dev-cycle.sh` and `bin/overnight-dev.sh` (this
  repo's own self-hosting cycle scripts, same headless-notify-send risk).
  Verified: `bash -n` on all three files, plus `env -u
  DBUS_SESSION_BUS_ADDRESS -u DISPLAY notify-send ... 2>/dev/null || true`
  returns immediately (exit 0) instead of hanging on the D-Bus timeout.

- **2026-07-20 20:27 (via chat, queued for next nightly cycle):** propagate
  the "no long/multi-line copy-paste commands for the user" preference
  (currently a per-project feedback memory scoped to this project's memory
  dir at `~/.claude/projects/-home-zach-Documents-Project-Archive-scheduler/memory/feedback-no-multiline-paste.md`)
  to a GLOBAL scope so every session across every project respects it, not
  just sessions in this repo. Rule as refined: keep commands under ~80
  chars — the constraint is chat-rendered line wrap, not literal newline
  count (a `printf '...\n...'` one-liner can still wrap and read like a
  heredoc). Concrete options to evaluate: (a) a global `~/.claude/CLAUDE.md`
  (doesn't exist yet — would need creating) that's loaded in every project's
  context, vs (b) whatever native global-memory/global-settings mechanism
  the harness actually supports (check before assuming CLAUDE.md is the
  only lever). Whichever lands, keep the existing per-project memory file
  in sync or retire it in favor of the global one — don't leave two copies
  that can drift.

- **2026-07-20 19:56 (via `scheduler -i`):** the convention for scheduler on open questions/blockers: use * to indicate new items that haven't been touched by Zach. open blockers that zach has seen are counted but have no freshness flag. ? indicates that the file has been edited and the sweeper hasn't run yet (maybe blockers and questions have been addressed that aren't accounted for. running sweep should clear the questionmarks). The current check off notation is opaque and undocumented +1✓ is unclear to me.
  **Documentation half DONE 2026-07-25 (paced cycle):** the `*`
  convention is now documented in `docs/scheduler-cli.md` (`scheduler
  man`); the `+1✓` notation complained about here no longer exists in
  the current `bin/scheduler` (predates a rewrite — grep-confirmed).
  The proposed `?`-means-edited-but-unswept marker is NOT built and
  stays the open half of this entry.

- **DONE 2026-07-25 (paced cycle): `scheduler -i <project>` with no text
  argument now opens `$EDITOR`** instead of failing with a usage message.
  For a normal project, a scratch copy of its real FOCUS.md is opened
  with a blank templated placeholder bullet already inserted at the same
  backlog/feature-request (or new "Ideas" section) insertion point the
  text-argument path uses — existing/older ideas stay visible right there
  for context, no separate "show parked ideas" feature needed. For
  realisateur, a fresh scratch file opens with a comment-only placeholder,
  matching its own `.idea`-file convention. After the editor closes: if
  the placeholder line/comment-only state is gone (real content was
  typed), the result is saved over the real file and pushed through
  `cmd_commit_file` same as the text-argument path; if it's untouched,
  the scratch file is discarded with no commit. Deliberately did NOT build
  a richer "surface my parked ideas for me" UX here — that's explicitly
  realisateur's future abstract-visioning scope (see its own FOCUS.md),
  not something to guess at from scheduler's side. Verified against a
  disposable scratch `SCHED_ROOT` (never the real one) with a scripted
  `$EDITOR` standing in for a human: new-file cancel (no file created),
  new-file real-content (single correct "## Ideas" heading, no
  duplication), existing-file cancel (byte-identical file, confirmed via
  `diff`), existing-file real-content, and both the realisateur
  cancel/real-content branches. `bash -n bin/scheduler` clean.
- **RESOLVED 2026-07-20: home-assistant's real divergence, found by the
  first-ever `scheduler sweep` run, reconciled with human direction.**
  Worth keeping the root-cause shape on file since it's a real pattern,
  not a one-off: (1) a live-tested fix deployed straight to a device via
  its REST API can get git-synced correctly, while a SEPARATE git-only
  decision made in the same session (no live deploy) is invisible to the
  next "reconcile with live instance" pass, which trusts live over git
  by design and can silently overwrite the git-only intent; (2) a human's
  real local checkout has no forcing function to fetch/reconcile against
  *origin* the way an automated job's dedicated clone does (always
  `reset --hard` before running) — so a checkout can drift for hours
  before anyone notices, previously only surfacing when a push happened
  to be attempted. `scheduler sweep`'s 15-minute tick directly addresses
  (2); (1) is project-specific (home-assistant's own reconcile-with-live
  step already exists for exactly this reason) and not something to
  generalize into the engine speculatively.
- **2026-07-20 17:05 (via `scheduler -i`):** when I touch a file like questions, it should move the number of questions outstanding from what's listed. This can either be determined immediately by analysing what's been edited inline or left as a ? in ambiguous cases when later agent confirmation is needed. That way I can use this bin utility to address questions systematically while seeing by progress. perhaps a simple * and ? convention next to the number can communicate this

- **2026-07-20 16:08 (via `scheduler -i`):** New third standing mode, built and proven out in chezz this session: /ideate (interactive-only, sibling to /bug-sweep and /nightly-batch). Where those two implement, /ideate explicitly does NOT -- it pulls live tracker+scheduler state, asks direct AskUserQuestion-style design-fork questions instead of guessing, and records decisions+rationale into a new DESIGN-NOTES.md (durable vision doc, repo root, outside .claude/) then queues them into FOCUS.md's priority list for /nightly-batch to actually build. Paired with a new CLAUDE.md that tells interactive sessions to proactively suggest /ideate when a request looks like open-ended vision/prioritization work rather than a concrete ask (suggestion, not a gate -- an explicit 'just fix X' still gets done inline). Worth generalizing into examples/ideate.md.template + a CLAUDE.md.template snippet alongside the existing bug-sweep/nightly-batch templates so other projects can adopt the same three-mode split. Reference implementation: chezz's .claude/commands/ideate.md, CLAUDE.md, and DESIGN-NOTES.md, commit history 2026-07-20.

- **2026-07-20 16:41 (via `scheduler -i realisateur`, refines the 16:08
  entry above) — OPEN DESIGN FORK, explicitly NOT decided, parked per
  today's "hardening first" priority.** User's own framing: realisateur
  (not scheduler) should own wiring an `/ideate`-shaped capacity into
  projects across the ecosystem — not just generalizing chezz's template
  mechanically, but realisateur actually *learning the principle* and
  applying it with judgment per-project. This reopens whether
  `scheduler -i`'s current design is right: maybe `-i` should narrow to
  "just append a next-action item" (its current, simple, working
  behavior), with an explicit HOOK letting realisateur decide, per idea,
  whether it's immediately actionable (stays a plain backlog line) or
  needs real incubation (realisateur's job — both fresh ideas AND bigger
  visions spawned in other projects' contexts, like this one). The idea
  itself is already durably parked correctly: dropped via `scheduler -i
  realisateur "..."`, committed into realisateur's own repo, will be
  processed by its next dispatch. Nothing about `scheduler -i`'s actual
  behavior changes until this fork is deliberately resolved — do not
  half-implement a hook speculatively.

- **2026-07-20 14:27 (via `scheduler -i`):** find a way to make scheduler [project] alias to report. also find a way to introduce tab completion on project names so I don't need to remember.

- **Avoid stranded state when a run gets cut off mid-way by hitting the
  usage limit (raised 2026-07-20, human-directed).** Two asks, and both
  build on infrastructure that ALREADY exists rather than needing new
  architecture:
  1. **Predictive: don't start a run predicted not to finish.**
     `usage-gate.sh`'s burn-rate check already gates dispatch on spare
     weekly quota BEFORE a cycle starts — the gap is that a long-running
     job can still exhaust quota mid-run (a burst, or concurrent
     interactive use eating the same account-wide budget), which
     `usage-gate.sh`'s pre-check can't see coming. Worth a stronger
     pre-check (e.g. require enough headroom for the job's typical/max
     `MAX_TURNS` cost, not just "any spare capacity right now"), but this
     can only ever be a probabilistic improvement, not a guarantee — #2
     below is the part that actually matters when prediction is wrong.
  2. **Reactive: lightweight start/stop "punch clock" so a cutoff is
     visible, not silent.** `lib/sweep-loop-common.sh` ALREADY writes a
     start-of-run marker per project
     (`~/.local/share/scheduler-registry/<PROJECT_KEY>.active`, with
     job/tier/started_at/pid) and removes it via a bash `EXIT` trap when
     the run finishes — this is already an implicit punch-clock. What's
     actually missing:
     - The marker doesn't record WHAT the run was attempting (just that
       one was running) — add a one-line "what I'm about to do" field,
       written once at the top of the run, so a stranded marker is
       informative, not just "something happened."
     - **Nothing surfaces a marker that never got cleaned up.** An `EXIT`
       trap doesn't fire on `SIGKILL`/OOM/a hard crash, so a truly
       stranded run leaves its `.active` marker sitting forever with
       nobody looking at it. `bin/scheduler`/`morning-report.sh` should
       check for `.active` markers older than some threshold (job's own
       typical max runtime, a generous multiple of it) with no matching
       completion, and flag them — "this looked like it was still running
       3 hours ago, probably got cut off, check `sweep.log`."
     - **The commit-level risk is already partially covered, not
       unaddressed:** `sweep-loop-common.sh`'s existing before/after/
       remote-SHA push-verification already distinguishes "pushed: yes" /
       "no new commits" / "WARNING: local commit made but NOT pushed" —
       a run cut off after committing but before pushing already shows up
       as that WARNING line in the log today. The real gap is entirely in
       visibility (nobody's watching `sweep.log` proactively), not in the
       underlying git safety (a git commit itself is always atomic — there
       is no such thing as a half-made commit to worry about).
  Sequencing: cheap to build once axis 1's migration touches
  `lib/sweep-loop-common.sh`-adjacent code anyway — natural pairing, not
  urgent enough to jump the queue on its own.

  **CONFIRMED LIVE, same day, and priority raised (2026-07-20, from an
  interactive chezz session, not a hypothetical anymore).** Chezz's
  2026-07-20T01:38 nightly-batch run hit the account's monthly spend
  limit after committing locally (`152e803`) but before pushing — exactly
  the predicted failure mode, exact `WARNING: local commit made but NOT
  pushed` signature, found sitting unpushed in
  `~/.local/share/chezz-nightly-batch/repo` and pushed by hand. **The same
  spend-limit message + WARNING pattern also appears in crt/realisateur/
  home-assistant/vkv-inventory/wtul's `sweep.log`s**, clustered around
  2026-07-19 ~22:34 and 2026-07-20 ~01:30-05:00 (matching a run of HTTP
  429s in `scheduler-paced-runner/run.log` over the same window) — an
  account-wide event, not chezz-specific.

  **Followed up same session: fetched fresh from every registered
  project's dedicated clone origin and checked ahead/behind.** Only
  chezz showed `ahead` (the incident above, already resolved by the time
  of checking); every other clone with a dedicated repo
  (chezz-bug-sweep, crt, home-assistant, realisateur, vkv-inventory ×2,
  wtul) is `ahead=0` — no other stranded commits exist right now.
  aedile/groc-mangr/nine-speakers/sequestria/vim-arcade have no dedicated
  clone yet (not yet dispatched under the paced governor), so nothing to
  check there. This was a one-time real incident during a genuine
  account-wide spend-limit event, not an ongoing silent leak — but the
  underlying visibility gap (#2 above) is exactly what let it sit
  unnoticed until a human happened to check by hand, and that's the part
  worth prioritizing ahead of other backlog items given this confirmed
  real-world recurrence.

- **Real bug, confirmed 2026-07-20: report filenames are date-only under
  a no-longer-nightly rhythm — data loss risk, not hypothetical.** Every
  real wrapper's `PROMPT` (`chezz`, `wtul`, `home-assistant`,
  `vkv-inventory`, `scheduler`'s own — grepped and confirmed directly,
  same pattern in all five) tells the agent to write to
  `~/reports/<project>/$(date +%Y-%m-%d).md`. Under the usage-paced
  governor, a project is no longer guaranteed exactly one dispatch per
  calendar day — a second same-day run silently overwrites the first
  dated file, permanently losing that run's dated record (`LATEST.md`
  still reflects the latest state, but the per-run history does not).
  **Fix: change the format string to `$(date +%Y-%m-%dT%H%M)` (no colons —
  stays filesystem-safe) in every wrapper's `PROMPT`.** Purely a filename
  format change, no behavior/git-operation change, low risk — but these
  are LIVE installed scripts under `~/.local/bin/*-loop.sh` actively
  driving other projects' automation, not files in this repo, so this
  needs an explicit human go-ahead before being touched (asked
  2026-07-20, awaiting your answer — see chat). `examples/
  nightly-batch-loop.sh` (this repo's own template) should get the same
  fix regardless, so newly-registered projects don't inherit the bug.
  Natural pairing: could ride along with axis 1's per-project migration
  pass above, since that's already opening each project's wrapper/conf.
  explicitly a LATER feature — parked, not designed yet).** Today's
  coordination is per-project only (the `PROJECT_KEY` registry mutex stops
  a project's own Tier 1/Tier 2 from racing each other; the paced governor
  round-robins independently of any cross-project relationship). Nothing
  today expresses "project B's work depends on project A finishing
  something" or gives the dispatcher any notion of priority/dependency
  across projects. Don't design this yet — noted here so it isn't lost,
  revisit once the more foundational roadmap items (registration
  contract, `AUTONOMY_TIER`, consolidation axes 1-3) have landed and an
  actual cross-project dependency has been felt as a real pain point, not
  a hypothetical one.

- **Branch awareness in reports (decided 2026-07-19, human-directed).**
  Fixes the push-verification blind spot above (option 2): have each run
  self-report which branch(es) it touched (write branch name(s) to a small
  marker file rather than trying to infer purely from git state after the
  fact), and have `morning-report.sh`/the services view surface it — a
  per-project line naming any branch(es) beyond `main` that exist right
  now, flagging when there's a live/dev split. Also look into rendering an
  ASCII tree diagram of each project's branch structure (e.g. `git log
  --graph --oneline --all` shaped) in the report/dashboard so branch state
  is visible at a glance, not just named. General principle: keep the human
  informed about what branches exist, don't let them pile up silently.
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
  - **2026-07-19 (human direction, extends the above):** `usage-gate.sh`'s
    burn-rate governor should be TIME-OF-DAY-AWARE, not flat across the
    day — spend more of the weekly budget during hours the user is
    typically inactive (night), hold more back during hours they're
    typically active (day), so paced cycles don't compete with the user's
    own interactive usage right when they're most likely to be using
    Claude Code themselves. Needs an actual activity profile, not a guess
    at fixed hours — see next point.
  - **2026-07-19 (human direction): track usage-exhaustion history for
    dynamic budgeting.** Log every time the account actually runs out of
    weekly/daily quota (timestamp + which window), so the pacing curve
    above can be DATA-DRIVEN instead of hand-tuned: if exhaustion keeps
    happening at a particular time of day or day of week, that's a signal
    to pull back the daytime allowance further; if quota is consistently
    left unused, the night allowance can grow. This is the input the
    time-of-day curve should be tuned against, not a one-time guess.
    Needs a design pass: where the exhaustion log lives, what counts as
    "ran out" (a 429/rate-limit response vs. `usage-gate.sh` itself
    declining to dispatch), and how far back history should weight into
    the current curve.
- **crt registered 2026-07-19** — since resolved (superseding the 2026-07-18
  note above): now a git repo pushed to a local bare remote
  (`~/git-remotes/crt.git`, no GitHub/credentials needed), `schedule/crt.conf`
  wired in as a Tier-2-only paced participant (`schedule/_paced.conf`),
  `.claude/{FOCUS,QUESTIONS}.md` + `commands/nightly-batch.md` in place,
  `focus/crt.md`+`questions/crt.md` symlinks applied. First run
  (2026-07-19T18:33) got a stale clone (`de7ae87`, one commit behind
  `origin/main`'s `249deff` which is what actually added
  `.claude/commands/nightly-batch.md`) so it hit "Unknown command:
  `/nightly-batch`" and did nothing — a one-time ordering issue from
  registering before that commit was pushed, not a bug in the engine. The
  dedicated clone does a fresh `reset --hard` each run, so this should
  self-heal on tonight's next paced cycle since `origin/main` now has the
  command file — **worth confirming in tomorrow's report that it actually
  did**, since this is the first project exercising a raw `BATCH_PROMPT`
  (`/nightly-batch`) through the new generic `scheduler-run` engine rather
  than a legacy `*_SCRIPT` wrapper, so a real failure here would be worth
  distinguishing from the known stale-clone explanation.
- **Deploy-pending awareness in `morning-report.sh`.** Projects with a
  deploy step the nightly can't run (vkv-inventory: the batch commits +
  pushes but has no interactive `clasp` auth, so the live `/exec` silently
  falls behind `origin`) need the morning report to SAY "live is behind
  origin — run the deploy." Today the only cue is an ad-hoc QUESTIONS.md
  entry, which a code-shipping night that files no question won't produce —
  that's how vkv drifted 5 commits + a stale live site before a human
  noticed (2026-07-18). Add a per-project, opt-in deploy-freshness check: a
  conf field (e.g. `LIVE_URL` + a `DEPLOY_FRESH_CMD` probe, sibling to
  `PRECHECK_CMD`) that `morning-report.sh` runs and, if the live build is
  stale, prints a "DEPLOY PENDING" line with the exact deploy command.
  vkv-inventory's probe already exists and is cheap: `GET
  ?scope=sweep-status` returns HTML when stale, JSON when fresh (see that
  repo's `tools/deploy.sh`). Opt-in, so projects with no deploy step are
  unaffected and the report stays byte-identical for them.
- **Right-size per-tier model choice — AUDITED 2026-07-25 (paced cycle),
  no downgrade needed anywhere.** Checked every `<TIER>_MODEL`-shaped
  field across all real config, not just this repo's: `grep -i model`
  over every `schedule/*.conf` here (only comment-text false positives,
  e.g. aedile's "safety model" prose, no project actually sets any
  `*_MODEL` field), plus every live installed `~/.local/bin/*-loop.sh`
  wrapper (reading outside this repo is fine, same rule used elsewhere in
  this file) — only `chezz-bug-sweep-loop.sh` sets `MODEL` at all, and
  it's already `claude-sonnet-5` (its own comment: "runs the mechanical
  triage/fix on Sonnet instead of the CLI default"). Confirmed from
  `lib/sweep-loop-common.sh`'s own header + dispatch line (`${MODEL:+
  --model "$MODEL"}`) that an unset `MODEL` means no `--model` flag at
  all, i.e. every other project's nightly/batch/sweep tier already runs
  on the plain CLI default, never Opus. So there is no live Opus-on-
  mechanical-work cost to fix — this item's premise (find Opus tiers,
  propose Sonnet) doesn't apply to anything actually configured today.
  Revisit only if a project's conf or wrapper is ever changed to set
  `*_MODEL=claude-opus-*` for routine work.

- **DONE 2026-07-19: inline `%%TAG` feedback in reports.** The human
  reviews a report/tracker file directly in vim (mappings in `~/.vimrc`,
  scoped to `~/reports/**/*.md` and this repo's `focus/`/`questions/`
  symlinks: `<leader>a/b/q/n/y/r` for ACTION/BLOCKER/QUESTION/NOTE/APPROVE/
  REJECT), leaves tagged comments inline, and the NEXT run for that project
  picks them up automatically and acts on them first — see
  `docs/feedback-tags.md` for the format and `bin/collect-feedback.sh` for
  the collector. Wired into `lib/sweep-loop-common.sh` (covers every
  project on the shared engine, including ones using `bin/scheduler-run`)
  and into the scheduler's own two bespoke wrappers
  (`scheduler-nightly-batch-loop.sh`, `scheduler-dev-cycle.sh`).
  Deliberately NOT wired into a chat interface — the point was to stop
  needing one for routine report feedback. Verified: `collect-feedback.sh`
  unit-tested against a hand-built sample file; the `%%TAG` → nnoremap →
  buffer-local-mapping chain verified in headless vim (`:nmap <buffer>`
  showed all six mappings with correct RHS); `bash -n` clean on all three
  edited scripts; a live dry-run (`SCHED_DRYRUN=1
  scheduler-dev-cycle.sh`) with a real `%%APPROVE` tag appended to
  `~/reports/scheduler/LATEST.md` confirmed the collector fires and would
  have prepended the block (removed the test tag after). **Not yet
  verified against a real (non-dry-run) `claude -p` invocation** — that
  needs an actual paced/nightly cycle to run for real confirmation the
  prepended prompt text lands as intended.
  - Not yet extended to crt/realisateur's actual report format (crt uses
    `crt-report.sh`, a different convention per the 2026-07-19 report
    section above) — only the standard `~/reports/<project>/LATEST.md`
    shape is covered so far.

- **RESOLVED 2026-07-20: permission gate on `.claude/**` writes in
  unattended runs.** Root-caused with a real controlled test, not a web
  lookup: a scratch git repo with two identical files, `.claude/scheduler/
  QUESTIONS.md` and `.scheduler/QUESTIONS.md` (top-level, no `.claude/`
  prefix). Ran `claude -p` twice, byte-identical prompt and
  `--allowedTools "Edit,Write"`, only the target path differed. Result:
  the `.claude/**` path was refused every time with the literal error
  `Claude requested permissions to edit <path> which is a sensitive
  file.`; the `.scheduler/**` path succeeded every time. **Confirmed
  path-based, confirmed real, confirmed fixable by moving off `.claude/`
  entirely** — not a classifier judgment call, not permission-mode
  dependent within what we tested. (The earlier "chezz wrote
  `.claude/QUESTIONS.md` fine the same night" observation is *not*
  explained by this test and is still unresolved as a loose thread — worth
  someone checking whether that run used a different permission mode or
  `ALLOWED_TOOLS` shape than the ones that got blocked, but it doesn't
  change the fix below.)

  **Fix applied to scheduler itself, same run:** `.claude/scheduler/` →
  moved to top-level `.scheduler/` (git mv, preserves history). Updated:
  `.scheduler/schedule.conf`'s `SCHEDULER_SUBDIR` value (`.claude/scheduler`
  → `.scheduler`), the `focus/scheduler.md`/`questions/scheduler.md`/
  `schedule/scheduler.conf` symlinks, `.claude/commands/nightly-batch.md`,
  `bin/overnight-dev.sh`, `bin/scheduler-dev-cycle.sh` (prompt text paths),
  and `bin/sync-crontab.sh`'s comments. `sync-crontab.sh` preview confirmed
  clean afterward (symlinks resolve to the new path, crontab output
  unchanged). This is now scheduler's own reference implementation of the
  fix.

  **Not yet done — every other project still has `FOCUS.md`/`QUESTIONS.md`
  directly under `.claude/`,** which means chezz, vkv-inventory,
  home-assistant, wtul, crt, and the rest are all still exposed to this
  exact gate on every unattended write. This is now **Phase 3** of the
  consolidation roadmap below — same `SCHEDULER_SUBDIR=".scheduler"` move,
  one project at a time, each project's own repo/PR (not edited from here
  directly, per the usual cross-project boundary).

## Multi-machine parallelism -- dexter comes up as a peer (2026-07-24, /ideate, human-directed)

Full decision + rationale + accepted risk in DESIGN-NOTES.md 2026-07-24
"multi-machine parallelism" -- this section is the short pointer + queued
MVP steps, not the reasoning. Trigger: dexter (previously known here only
as crt's OctoPrint-reachable VM, BLOCKERS.md 2026-07-20) now has its own
WSL/Ubuntu -- first second real machine capable of running Claude Code.
Today's dispatcher is strictly single-host (`usage-paced-runner.sh`'s
global flock, see "Architecture: cron, not a daemon" above); this is
that section's own named revisit trigger showing up, as a second
laptop-class peer rather than a server.

**Decided (all four asked directly):** dexter runs Claude Code locally as
a full peer (not a jump box) -- real parallelism, not remote triggering.
Projects pin to a machine only where hardware/network need is actually
evidenced (`crt` -> dexter, confirmed reachable at `192.168.0.43`;
`gardien`/`senechal` NOT pinned -- their gate is permission-scope, not
network-locality, real open question, see QUESTIONS.md); everything else
stays on mandark for the MVP. Topology is two independent schedulers (own
`_paced.conf` subset + rotation pointer each, no distributed lock) --
simpler than a shared rotation, at the cost of a real accepted risk:
`usage-gate.sh` is a point-in-time probe of account-wide headers, and two
independent probers can both see slack and both dispatch, overshooting
between probes (the single-flock model today prevents this by
construction; two hosts reintroduce it). Not solved this pass -- watched
empirically once dexter is live.

**REVERSED, same session, minutes later (see DESIGN-NOTES.md follow-up
entry): sprint scope is realisateur self-build, not the small MVP.**
Asked directly whether to actually proceed with the small MVP below or
let realisateur build dexter's own registration/rotation once login is
set up -- answer was self-build. The steps below are now the STARTING
POINT handed to that self-build session, not a human checklist. The
accepted quota-race risk above is now MORE live, not less, since it
arrives sooner and less manually sequenced -- watch `run.log` on both
boxes closely once dexter's own paced runner starts.

**SELF-BUILD EXECUTED 2026-07-24, on dexter.** The steps below were the
starting point; here is what actually landed vs. what is still open. Full
reasoning in DESIGN-NOTES.md "dexter registers itself as a second host".

**BUILT (all verified on dexter, not just written):**
- **Host-scoped participant config.** `schedule/_paced.<short-hostname>.conf`,
  auto-selected by hostname, falling back to the shared `_paced.conf` for
  any host without its own file. Chose separate files over a HOST column in
  the shared file because `_paced.conf` already has an *automated* writer
  (`weight-audit.sh` commits reweights), so a shared file would mean two
  machines — one editing on a timer — competing for the same lines. Each
  host writes only its own path, so the conflict is impossible rather than
  merely rare. `bin/usage-paced-runner.sh` now resolves its repo root
  through `readlink -f` (the old `dirname` broke when invoked via the
  `~/.local/bin` symlink), logs a `ROTATION` line whenever the resolved
  rotation changes, and exits non-zero with `FATAL` on a missing conf.
  **No-op on mandark by construction** — no `_paced.mandark.conf` exists, so
  mandark still reads `_paced.conf`; tested in both symlink and copied-install
  shapes.
- **`schedule/_paced.dexter.conf` created, `crt` pinned to it** — with
  `enabled=0`, see still-open item 1 below.
- **Crontab tick installed and confirmed firing** — `*/5`, derived from
  `schedule/_runner.conf` rather than retyped. Verified end to end: cron is
  `active`/`enabled` in this WSL2 container, and the tick fired on schedule
  and logged the expected host-scoped-conf line.
- **crt's OctoPrint re-verified from WSL2** (was step 3) — `192.168.0.43`
  answers with 0% ICMP loss, TCP 80 open, and an OctoPrint-identifying HTTP
  302 (`x-clacks-overhead` header), so it is the real service and not just an
  open port. The 2026-07-20 full-VM confirmation does carry over to WSL2.
- **`bin/scheduler-dev-cycle.sh` made host-agnostic** rather than cloned into
  a dexter-specific wrapper — it no longer hardcodes mandark's repo path.
  `scheduler` is deliberately NOT in dexter's rotation: see still-open item 3.
- **Bug found and fixed en route:** `lib/sweep-loop-common.sh` ran `git clone`
  and the following `cd` unchecked, so an unreachable `REPO_URL` fell through
  to `git reset --hard` and a `claude -p` call with write tools in cron's
  working directory — then exited **0**. Reproduced against the pre-fix code
  with a tripwire, not merely reasoned about. Both steps now abort loudly.
  Latent since the library was written; dexter is just the first host with a
  genuinely unreachable `REPO_URL`.

**STILL OPEN:**
1. **crt cannot actually run on dexter — repo access, not network.**
   `schedule/crt.conf` points at `REPO_URL="/home/zach/git-remotes/crt.git"`,
   a bare repo on *mandark's* filesystem (local on purpose — crt's VM
   password must not leave that machine). dexter has no such path and crt has
   no mirror. Confirmed by running it. **The transport is now decided** by
   `28a1617` (realisateur, same evening): non-GitHub projects reach dexter
   via a local bare remote over LAN/SSH, which rules out the GitHub mirror
   option. What is left is the concrete setup step — expose mandark's bare
   repo over SSH, or move crt's bare repo to dexter (arguably better, since
   crt is hardware-pinned here and that variant keeps dexter independent
   rather than newly dependent on mandark). See QUESTIONS.md. Note
   `28a1617` states crt "already uses this exact pattern" — it uses a local
   bare remote, but a filesystem path, *not* LAN/SSH; crt is the policy's
   first unbuilt instance, not proof of it working. Until then dexter's
   rotation is empty, which the runner logs explicitly.
2. **Dropping `crt` from mandark's `_paced.conf` is prepared but NOT merged**,
   on branch `dexter/drop-crt-from-mandark-paced`. Merging it today would
   create a gap rather than prevent a double-dispatch: crt would stop running
   *anywhere*, and it is the highest-weight participant (weight 3). Land it in
   the SAME change that flips crt to `enabled=1` on dexter, once item 1 is
   resolved.
3. **Whether dexter should self-develop `scheduler` too.** The wrapper is now
   host-agnostic so it *could*, but two hosts committing to one scheduler git
   history — each auto-merging to its own local `main` — is a stronger version
   of the divergence that bit this repo earlier the same day. That entry was
   cleared by `558c1c1` mid-session, but by *fast-forward*, which works only
   while one side hasn't independently advanced — exactly the condition two
   pushing hosts remove. Not enabled pending a human call; see QUESTIONS.md.
4. **`bin/sync-crontab.sh` is not host-scoped.** Previewed on dexter, `--apply`
   would install fixed-cron lines for four mandark-only projects plus a sweep
   tick, and symlink `focus/`/`questions/` into mandark-only paths. The
   `_paced.<host>.conf` split covers participant *rotation*; project
   *registration* is the larger unsolved half. dexter's tick was hand-installed
   meanwhile (documented in its crontab block so nobody "fixes" it by running
   `--apply` here). Natural next item, deliberately not bundled into this pass.
5. **Does mandark pull?** dexter pushes to the same `origin/main` mandark runs
   from, and mandark executes `usage-paced-runner.sh` / `sweep-loop-common.sh`
   out of a checkout of this history — so commits here are shared *running
   code*, not just shared config. Nothing found in this repo pulls
   `origin/main` on mandark automatically, which means (a) the fixes above may
   not have reached it yet and (b) the crt-drop in item 2 will not take effect
   there until it does. See QUESTIONS.md.
6. **Watch `run.log` on both boxes** (was step 4) — still the live question:
   does the account-wide ceiling get hit harder than single-host operation
   hits it today (the accepted probe race)? **Not yet observable**: dexter's
   rotation is empty, so its tick currently costs nothing at all — it exits
   before probing the gate. Real data starts only once item 1 unblocks.

Step 1 of the original list (human login + clone) is DONE — this session ran
on dexter, `usage-gate.sh` works here against the shared account (7d window
read live), and push access to `origin` is confirmed.

**2026-07-24 (realisateur, via `/ideate`): vision promoted from "parked
dream" to "dexter-as-primary-host, partial" — asked directly, not
guessed.** The dexter self-build session above is now live (running on
dexter itself, per Zach). Zach was asked directly whether gardien's
2026-07-24 QUESTIONS.md item ("dexter becomes the always-on server for
the whole ecosystem, mandark stops running overnight jobs") should stay
parked, promote fully, or land as a partial commitment. **Decided:
partial.** "Dexter becomes the primary host where unattended jobs run"
is now a real, active direction — not a dream — but "cloud VMs / remote
GitHub-agent triggers / retiring mandark entirely" stays a separate,
genuinely undecided later phase, not bundled into tonight's scope.
Concretely this means: the dexter self-build in progress (crt-pinned
MVP, two independent schedulers) is validated groundwork for a real
target, not just an experiment to observe and possibly discard. It does
NOT mean committing yet to cloud VMs, GitHub Actions/remote-agent
triggers, or a hard mandark-sunset date — those remain open.

**Explicitly declined, same session: naming "many parallel jobs on
dexter via VMs/WSL" as the next milestone-after-next.** Asked directly;
Zach's call was "too far ahead" — don't design the multi-VM/parallel-job
layer until the current single-peer MVP (crt pin, one dexter scheduler,
the accepted quota-race risk) is actually proven stable. Not recorded as
a queued milestone; if it comes up again, treat it as still fully open,
not something already scoped.

**No-GitHub-remote projects' path to dexter: DECIDED — local bare
remote over LAN/SSH, same pattern as existing local-only projects.** No
new credential mechanism; a project without a GitHub repo gets (or
already has) a bare git remote reachable over the LAN/SSH, and dexter's
scheduler clones/pushes to that exactly like crt's
`REPO_URL="/home/zach/git-remotes/crt.git"` today. This generalizes the
existing "prefer local bare remote unless GitHub is clearly right" rule
to the multi-host case rather than inventing a new transport. Nothing to
build yet — no non-GitHub project is pinned to dexter today (only crt
is, and it already uses this exact pattern) — but the policy is settled
for whenever one is.

## Consolidation roadmap (2026-07-20, human-directed session)

**RE-SEQUENCED AGAIN (2026-07-20, later still): item 0 is now PARKED (see
"SEQUENCING" note at the top of "Current focus"), so this axis-0-3
consolidation work and the "hardening + explainer" priority above are
what's actually active — not item 0.** Everything below is still exactly
as valid and still queued for eventually, just genuinely not urgent
right now either; the real current work is hardening/documentation per
"Current focus" items 1-2.

**Axis 0 (prerequisite, do first once item 0 above is underway): build
`REGISTRATION.md` + conf schema
v1 + the soft validator + `bin/scheduler-register`** — see "Registration —
the Claude-native contract" under Vision above for the full design. This
has to land before axis 1 below can stamp a meaningful
`SCHEDULER_CONF_VERSION` on any project's conf.

Then three axes of registration/layout sprawl that grew independently and
now need converging, in this order:

1. **Registration mechanism** — every `schedule/<project>.conf` still sets
   a legacy `*_SCRIPT` line (chezz, vkv-inventory, home-assistant, wtul),
   even though `bin/scheduler-run` + the conf runtime fields have existed
   since 2026-07-18 and MIGRATION.md already documents the exact safe,
   one-tier-at-a-time move.

   **CORRECTED 2026-07-25 (paced cycle) — MIGRATION.md's flip (steps 2-4:
   drop `*_SCRIPT`, verify `sync-crontab.sh` preview, `--apply`) is a
   no-op for home-assistant and wtul specifically, and would have looked
   done without actually moving anything.** Both are now **paced
   participants**, not fixed-cron ones — confirmed live via
   `bin/sync-crontab.sh` preview (`note [home-assistant/BATCH]: paced
   participant -- fixed cron suppressed, dispatched by
   scheduler-paced-runner`, same for wtul) and by reading
   `bin/usage-paced-runner.sh`: for a paced participant, dispatch comes
   entirely from the literal command string in `schedule/_paced*.conf`'s
   third column (e.g. `home-assistant|1|2|/home/zach/.local/bin/
   home-assistant-nightly-batch-loop.sh`), executed directly — it never
   consults `schedule/<project>.conf`'s `BATCH_SCRIPT`/runtime fields or
   goes through `sync-crontab.sh`'s generated crontab at all (that's
   exactly why the preview says the fixed cron line is "suppressed" for
   these two). So dropping `BATCH_SCRIPT` in `home-assistant.conf`/
   `wtul.conf` would change nothing about what actually runs; the real
   switch for a paced participant would have to change its `_paced*.conf`
   command column to invoke `scheduler-run` instead of the wrapper path
   directly — a materially different, riskier edit (touches the line two
   hosts' cron ticks read and act on immediately once pulled, with no
   `--apply`-style gate the way the crontab flip has) than what this item
   describes. Left as an open judgment call in `QUESTIONS.md` rather than
   decided here. **Step-1 config-copying is still genuinely done** for
   both (2026-07-24 paced cycle, see below) — only the flip-the-switch
   steps are affected by this correction.

   **Checked, not assumed — this actually affects all four projects
   named in this item, not just home-assistant/wtul.** `sync-crontab.sh`
   preview also flags `chezz/BATCH` as a paced participant (same
   suppression note), and `chezz` appears directly in `schedule/
   _paced.conf`'s command column the identical way (`chezz|1|/home/
   zach/.local/bin/chezz-nightly-batch-loop.sh`) — so chezz's `BATCH_SCRIPT`
   flip would be an identical no-op. `vkv-inventory` is disabled
   (`vkv-inventory|0|...`) in `_paced.conf` — its batch tier isn't
   dispatched from here at all right now (see that line's own comment:
   moved to svc-vaporwave's crontab, migration unverified), so
   MIGRATION.md doesn't apply to it either, for an unrelated reason.
   **Net: MIGRATION.md's steps 2-4, as written, currently apply to ZERO
   of the four projects this item names.** Whether/how to extend axis-1
   to cover paced participants (edit `_paced*.conf`'s command column
   instead) is the open judgment call filed in `QUESTIONS.md` — don't
   pick a project and "execute MIGRATION.md" here again until that's
   answered, it'll just repeat this same no-op.

   **DECIDED 2026-07-26 (interactive /ideate, Zach): option (a) — converge
   paced dispatch on `bin/scheduler-run`.** The `_paced*.conf` command
   column becomes `scheduler-run <project> nightly-batch`, which is also
   what lets PLAYBOOK Play 3 retire the two 162-line loop-script forks
   cleanly (5-line shim shape). **Hard sequencing gate, not optional:**
   the live-edit risk that made this the "riskier" option must be closed
   FIRST — the paced runner dispatches from a committed/validated copy of
   `_paced*.conf` (the approved symlink-deploy import for `scheduler
   pacing deploy`/drift plus the "refuse dirty confs" backlog item are
   the two halves of that gate). Do the gate, verify drift fails loud,
   THEN flip one project's command column at a time, chezz first, watching
   one full dispatch before the next. Rationale: DESIGN-NOTES.md
   2026-07-26 /ideate pass; the matching QUESTIONS.md entry carries the
   `> ` answer.

   **1.5. `AUTONOMY_TIER` (see Vision section above) — bundle into the same
   pass.** While a project's conf is already open for the axis-1 migration,
   add its `AUTONOMY_TIER` field (`low`/`medium`/`high`) reflecting that
   project's *actual current* de facto policy (read its FOCUS.md's own
   push/merge/irreversibility language to infer it — don't invent a new
   policy, just formalize the existing one). Do NOT build the
   engine-enforcement side yet (no code should change behavior based on
   this field this pass) — this step is only "declare the field and set it
   correctly per project," so the mechanics can be built against real,
   already-populated data next. If a project's actual policy is unclear or
   contested, leave `AUTONOMY_TIER` unset and flag it as a QUESTIONS.md
   entry rather than guessing.

   **DONE, ahead of the axis-1 migration this bundles into, 2026-07-24
   (paced cycle):** declared `AUTONOMY_TIER` in 12 of 14 registered
   projects' `schedule/*.conf` (unused by any code today, declare-only per
   this item's own scope) — `chezz`/`vkv-inventory`/`crt`="medium",
   `home-assistant`/`wtul`/`aedile`="low", `scheduler`/`realisateur`/
   `groc-mangr`/`nine-speakers`/`sequestria`/`vim-arcade`="high" — read
   straight off the already-decided FOCUS.md "Target UX" mockup (2026-07-20)
   plus each project's own conf/FOCUS.md push-policy language (e.g.
   aedile's conf explicitly states "REVIEW-GATED, never auto-push/
   auto-merge" → low), not invented fresh. `gardien`/`senechal` left
   UNSET and flagged to `.scheduler/QUESTIONS.md` — their own docs only
   state a physical-effect *scope* gate (no unattended RAID/home-directory
   access yet), silent on push/merge autonomy specifically, so guessing
   `high` off the bare-remote precedent alone would be exactly the kind of
   unilateral judgment call this item warns against. Verified: `bin/
   sync-crontab.sh` preview output is byte-identical before/after (new
   field is a `source`d no-op, confirmed by reading the loop in
   `bin/sync-crontab.sh` — it only reads `PROJECT`/`SWEEP_*`/`BATCH_*`/
   `REPO_URL`/`SCHEDULER_SUBDIR` by name), `bash -n` clean on every edited
   conf.

2. **Sweep pacing — chezz DONE 2026-07-25 (paced cycle); vkv-inventory
   deliberately deferred.** Tier 1 bug-sweeps (chezz, vkv-inventory) had
   been sitting paused (`SWEEP_JOB_NAME=""`) since the usage-paced governor
   migration orphaned them. **Decision made 2026-07-20: fold sweeps into
   the main `_paced.conf` rotation** as ordinary participants alongside
   the Tier 2 batches (not a separate faster rotation) — accept the
   cadence drop (once per full rotation lap instead of every ~15min) as
   the tradeoff for one dispatcher instead of two.

   **Real gap found while implementing this, fixed first:**
   `bin/sync-crontab.sh` only suppressed a paced participant's fixed cron
   line for the BATCH tier (`is_paced "$PROJECT"` check), never for SWEEP
   — so literally following this item's own instructions (restore
   `SWEEP_JOB_NAME`/`SWEEP_CRON`, add the wrapper to `_paced.conf`) would
   have double-dispatched chezz's bug-sweep: once on a real fixed cron
   line, once from the paced rotation. Added the same `is_paced` check to
   the SWEEP tier, mirroring BATCH exactly. Verified as a true no-op today
   (byte-identical `sync-crontab.sh` stdout/stderr before/after, since no
   project currently trips the new branch) before relying on it.

   **Then, with that fixed:** added `chezz-sweep` as a new participant in
   `schedule/_paced.conf` (`chezz-bug-sweep-loop.sh`, enabled, weight 1 —
   a distinct line from the existing `chezz` BATCH participant, same
   project) and un-paused `SWEEP_JOB_NAME="chezz-bug-sweep"`/
   `SWEEP_SCRIPT=".../chezz-bug-sweep-loop.sh"` in `schedule/chezz.conf`
   (no `SWEEP_CRON` — that's what tells `sync-crontab.sh` to suppress the
   fixed-cron line now that `is_paced("chezz")` is true). Verified: `bash
   -n` clean on `sync-crontab.sh`/`scheduler`/`usage-paced-runner.sh`; a
   `sync-crontab.sh` preview now prints `note [chezz/SWEEP]: paced
   participant -- fixed cron suppressed` and its stdout (the actual
   generated crontab) stays byte-identical to before this whole change
   (the sweep was never in the fixed crontab and still isn't — it's
   dispatched by the paced runner instead); `scheduler status chezz`,
   `scheduler` (glance), and `scheduler sweep` all ran clean end to end
   with the new `chezz-sweep` line present, no confusion between it and
   the registered `chezz` project. **`vkv-inventory`'s bug-sweep is NOT
   folded in** — `vkv-inventory` itself is still `enabled=0` in
   `_paced.conf` pending the separate, already-flagged svc-vaporwave
   migration judgment call; adding its sweep to the rotation while the
   project itself is paused would just be more surface on something
   already blocked. Revisit once that call is made.

3. **File layout — `SCHEDULER_SUBDIR=".scheduler"` propagation.** Was
   blocked on the permission-gate investigation above; that's now
   resolved and scheduler has the reference implementation. Roll out to
   one project at a time: move that project's `.claude/FOCUS.md`/
   `.claude/QUESTIONS.md` to `.scheduler/FOCUS.md`/`.scheduler/
   QUESTIONS.md` in *that project's own repo*, set
   `SCHEDULER_SUBDIR=".scheduler"` in its `schedule/<project>.conf` here,
   re-point that project's own `/nightly-batch` and `/bug-sweep` command
   files at the new path, verify `sync-crontab.sh --apply` re-links
   `focus/<project>.md`/`questions/<project>.md` correctly. **Propose this
   per-project rather than editing another repo directly from here** —
   same boundary as always. Natural pairing: do a project's axis-1 and
   axis-3 migration in the same cycle if it's getting touched anyway.

   **chezz is first mover, in progress (2026-07-20, from chezz's own
   interactive session) — TRACKED DEPENDENCY, not yet actionable here.**
   Chezz's own `.claude/FOCUS.md` now has an explicit next-batch task to
   move its `FOCUS.md`/`QUESTIONS.md` off `.claude/` into a top-level
   `.scheduler/` dir, matching this repo's reference implementation.
   That session deliberately did NOT set `SCHEDULER_SUBDIR` in
   `schedule/chezz.conf` here (correct — cross-project boundary, chezz's
   migration hasn't actually happened yet, only been queued). **Whatever
   run does chezz's axis-1 migration should check first whether this
   axis-3 move already landed in chezz's repo, and set
   `SCHEDULER_SUBDIR=".scheduler"` in `schedule/chezz.conf` at the same
   time if so** — avoids a second, separate touch of the same conf file
   for something that's already been done on the chezz side.

**Deferred — parked, not forgotten, revisit after the three axes above
converge:**
- FOCUS item 0 (collapse report + `QUESTIONS.md` into one file the human
  answers inline in) — still real, still wanted, but layering a fourth
  file-shape change on top of an already-in-flight layout migration
  (axis 3) would make both harder to verify independently. Do this once
  every project is settled on `.scheduler/`.
- FOCUS item 3's remaining pieces (b/c/d: the `scheduler` glance
  subcommand reading the merged file, blocker approve/clear via `git log`,
  per-project rollout) — same reasoning, depends on item 0.
- **Reframed 2026-07-20 (see Vision above) — this is now an infrastructure
  check, not an "audit the output" task.** Self-spawning is the intended
  use case, not a risk to contain, so the deferred question isn't "were
  groc-mangr/nine-speakers/sequestria/vim-arcade's commits good" — it's
  "does the containment the pattern depends on actually hold": confirm
  each spawned project really is on a local bare remote (no GitHub
  credentials reachable), has a real cost cap, and gets a sensible
  `AUTONOMY_TIER` once that field exists (item 1.5 above) rather than
  drifting to whatever a scaffolding session happened to set. Do this
  once axis 1 / item 1.5 give every project (including these four) a real
  `AUTONOMY_TIER` value to check against.

## Out of scope for an unattended run

- Anything that can only be tested by waiting for a live cron fire.
- Editing installed wrappers under `~/.local/bin`, the live crontab, or any
  other project's files.

- I manually pushed 6 changes to github, I think. Need to find a way to give this autonomy to the agent which said auto mode gates it

## Cross-project blocking relationships (2026-07-22, human-directed session)

**Standing principle: scheduler is responsible for knowing which steps
reasonably block on other steps across projects, even when it isn't the
one making the judgment call.** Concrete case that surfaced this
2026-07-22: `scheduler status <project>`'s new "next up" section (see
`extract_next_items()` in `bin/scheduler`) needs a structured FOCUS.md to
parse at all — chezz's is prose/HTML-comment-only (no bullet list) and
wtul has no FOCUS.md (uses `ROADMAP.md` instead), so both come up empty.
Reformatting/reconciling those is realisateur's job, not scheduler's (see
`docs/priority-weight.md`'s same division of labor: scheduler stays
mechanism, realisateur owns interpreting vision/format judgment) — filed
as an `.idea` there 2026-07-22
(`FOCUS-md-formatting-compliance-20260722-145750.idea`), with a short
defer-flag dropped into chezz's and wtul's own FOCUS.md via `scheduler -i`
so their own nightly-batch/bug-sweep don't try to self-solve the format
question in the meantime.

**What scheduler itself still needs to build, not done yet:** a real way
to *know and display* that chezz/wtul's next scheduled dispatch is
sitting behind a pending realisateur judgment call — right now that
relationship exists only as prose in three FOCUS.md files, invisible to
`bin/scheduler`'s own views. Needs, as real design work for a future
session:
- A data model for "project X's next dispatch depends on action Y in
  project Z" — candidate shapes: a conf field (`BLOCKED_ON=realisateur`),
  a convention both sides read/write (a `## Blocking` note realisateur is
  expected to clear once it acts), or scheduler inferring it from
  `.idea`/QUESTIONS.md cross-references — not decided, needs a real pass.
- Surfaced in **both** places: a per-row marker on the no-arg glance
  (e.g. `chezz ... BLOCKED: pending realisateur reformat`) and a
  dedicated line in that project's own `scheduler status <project>`
  output, not just buried in FOCUS.md prose.
- First real test case once built: this exact chezz/wtul reformat —
  whether their next dispatch should actually be HELD until realisateur's
  pass lands, or run regardless against today's format, is realisateur's
  call to make explicit (asked of it in the `.idea` filed above); once it
  states that decision in a machine-readable way, this feature has real
  data to render instead of a hypothetical.

**Item 5 (BLOCKERS.md mixing urgent vs. informational entries) is
explicitly waiting on this same realisateur-owns-judgment pattern, not
scoped further today.** Found while investigating: realisateur already
has a working precedent for exactly this shape — `schedule/_paced.conf`'s
`weight` field (mechanical knob scheduler enforces) paired with
`docs/priority-weight.md`'s explicit "scheduler is pure mechanism,
realisateur interprets vision and expresses it through the knob" framing.
Once realisateur produces an analogous urgency/priority annotation
convention for BLOCKERS.md-shaped items (not built yet — nothing to pull
in today beyond this precedent), `bin/scheduler blockers`/`cmd_glance`
should read and render THAT rather than scheduler inventing its own
urgency heuristic — same boundary, applied to a second knob.

## Fable review (2026-07-25)

<!-- Appended by realisateur/fable-like/inject-suggestions.sh. Full context: fable-like/FABLE_REPORT.md. Triage these like any dated entries; delete freely. -->

- **2026-07-25 (fable-review):** build + cron-wire a liveness audit: every enabled/externally-dispatched project must have a report younger than 2 days or the morning glance shouts. The aedile/vkv-inventory 4-day silent orphaning is the class this closes. Example: realisateur/fable-like/projects/scheduler/bin/liveness-audit.sh
- **2026-07-25 (fable-review):** finish MIGRATION.md — retire the ~20 legacy `*-loop.sh` wrappers still referenced by `_paced.conf` in favor of `scheduler-run`; layer-not-replace is live in the engine's own backyard
- **2026-07-25 (fable-review):** delete (or regenerate-and-own) `services/` — stale since 2026-07-18, describes the pre-pacing world; healthy-looking stale output is the silent-failure smell
- **2026-07-25 (fable-review):** investigate the rc=1 dispatch at 2026-07-25 00:19 (scheduler batch); an uninvestigated nonzero exit is a timestamped silent failure. Also fix the `[legacy absolute path]` defect on every ROTATION log line
- **2026-07-25 (fable-review):** compaction convention for DIGEST.md (256KB) / DESIGN-NOTES.md (88KB): monthly roll-up into docs/history/YYYY-MM.md + one-page index; append-only stays, unbounded single files go
## Propagation findings (2026-07-25, from the fable injection pass)

<!-- Not from FABLE_REPORT.md's body: the first was its postscript (written after
     inject-suggestions.sh had already run, so it reached no project's FOCUS.md);
     the rest surfaced while actually pushing the injection. -->

- **2026-07-25:** sweep autocommit mislabels and commits mid-session. At 02:00 it committed ~38 half-written files from a live interactive session as "Human edit via scheduler" — provenance record now lies (these were agent writes), and it is "dirty tree is a stop" pointed backwards: the engine edited history out from under a live session. Fix: skip a repo whose session lock / recent mtime says someone is working, and label what it knows ("sweep autocommit: uncommitted changes found"), not what it guesses.
- **2026-07-25:** **real working copies never pull, so every local edit lands on a stale base.** Measured today: crt 51 commits behind origin, groc-mangr 26, chezz 18, sequestria 15, nine-speakers 12, vim-arcade 11, home-assistant/gardien/senechal 3. Dispatch clones push to origin; nothing pulls the human-facing clones back. Every one of the 9 fable-review commits was rejected non-fast-forward on first push. Fix: a pull/freshness step (sweep tick could `git fetch` + report behind-counts in the glance), or make the working copies genuinely disposable.
- **2026-07-25:** that staleness already strands work silently. `bin/scheduler:686-692` warns "N commits behind — committing anyway", commits, and its push then fails; the message scrolls past in cron output. vim-arcade carried an unpushed `Idea added via 'scheduler -i'` commit that had been invisible to every dispatch since (rebased and pushed today). The freshness check is a warning where it needs to be a stop or a fix — same class as the aedile/vkv orphaning, different mechanism.
  **DONE (2026-07-26 paced cycle) — it is now a fix where one is safe, and
  a loud stop where it isn't.** `cmd_commit_file` (the ONE implementation
  behind `scheduler -i`, the vim auto-commit hook, `sweep`'s .md backstop,
  `pacing tick`, `weight`, and `-b --claude`'s tidy) now splits the
  behind-origin case three ways instead of printing one NOTE and
  committing onto the stale base regardless: **behind only, fast-forward
  clean** → `git merge --ff-only origin/$branch` first, so the edit lands
  on origin's current state and pushes normally (this is the common case —
  the same fetch+`--ff-only` move `usage-paced-runner.sh` already makes
  every tick, so no new policy); **behind, FF refused** (origin touched the
  same file) → commit locally, skip the push, and say so as a `WARNING:`
  naming git's own reason and the recovery command; **genuinely diverged**
  (ahead AND behind) → never fast-forwarded, never auto-merged, same rule
  `report_divergence` already states. Second half of the same defect,
  fixed with it: the push was `push --quiet 2>/dev/null` and the failure
  message then GUESSED the cause ("check credentials/network"). It now
  captures git's output and prints a real `push reason:` line — same
  convention `lib/sweep-loop-common.sh` already uses. Live witness for why
  the guess wasn't good enough: wtul's working copy is carrying
  `Human edit via scheduler: QUESTIONS.md (2026-07-26T23:30)` unpushed
  right now, and because the old code discarded stderr, *why* is
  unknowable after the fact — a read-only `git push --dry-run` today says
  the push would succeed. Verified with an 8-case offline harness over
  throwaway bare-origin+clone repos (in-sync, behind-FF, FF-blocked-by-
  untracked, diverged, push-fails-for-a-real-reason, no-op, tracked-file-
  dirty-FF-clean, tracked-file-dirty-FF-refused): every "should land" case
  ends with HEAD on origin and **zero merge commits created**, every
  "should stop" case leaves the local edit byte-intact and prints the
  reason + recovery line. `bash -n bin/scheduler` clean. Not covered, on
  purpose: the parallel finding above it (working copies never pull at
  all) — this fixes the write path that strands ideas, not the general
  behind-origin audit, which stays queued below.
- **2026-07-25:** a project's FOCUS.md path is not discoverable — inject-suggestions.sh hardcoded 14 paths and broke the day chezz moved `.claude/`→`.scheduler/`. `SCHEDULER_SUBDIR` already exists in the confs; anything that wants a project's FOCUS.md should resolve it through one shared helper, not retype the path (config-read-from-one-source).
- **2026-07-25:** `lib/sweep-loop-common.sh:229-231` — `git checkout "$BRANCH"`, `git fetch`, and `git reset --hard "origin/$BRANCH"` are all unchecked (no `set -e`). The 2026-07-24 dexter fix guarded the clone and explicitly noted these "silently failed too", but only the clone got the check. Live consequence: home-assistant's wrapper sets no BRANCH, so it defaults to `main` while baudin only has `master` — every pass logs `error: pathspec 'main' did not match` + `fatal: ambiguous argument 'origin/main'`, the reset-to-origin guarantee silently does not apply, the push check reports "could not read origin/main ... looks like an SSH/auth/network failure" (wrong diagnosis), and the run's own summary claimed "Everything's committed, pushed, and reports are in sync" while a real commit sat unpushed. Fix: check all three, and default BRANCH to the remote's actual HEAD (`git ls-remote --symref origin HEAD`) rather than the literal string `main`.
- **2026-07-25:** BRANCH is per-wrapper and invisible from the conf, so a FOCUS.md edit can land on a branch dispatch never reads. wtul's working copy sits on `label-printer-integration` while `wtul-batch-loop.sh` reads `main` — anything committed in the working copy without switching branches is invisible to the job. Same shape as the SCHEDULER_SUBDIR miss: a per-project path/ref that a survey can't see and nothing asserts.

## svc-vaporwave: the blocker was never permissions (2026-07-25)

- **2026-07-25:** `zach` already holds `(svc-vaporwave) NOPASSWD: ALL` in sudoers — checked with `sudo -n -l`. The "human-only 15-minute step" that has cost aedile and vkv-inventory five days of zero dispatch needed no permission grant at any point. Nobody re-checked whether the step was actually blocked; it was recorded as blocking and then believed. Same shape as the credential-gap retraction: a plausible explanation that fits the symptom, never tested.
- **2026-07-25:** svc-vaporwave is **not a headless service account**. It has a logged-in desktop session up 1d12h (`systemd --user`, pipewire, dbus, jackdbus), and Claude ran under it at **04:01 today** (`.claude/` + `.claude.json` mtimes, `sessions/` at 04:05). So "no crontab exists there" and "nothing runs there" are different claims, and only the first was ever checked. What dispatched at 04:01 is UNVERIFIED — reading that account's crontab and logs was refused by the tool sandbox this pass. Verify before re-enabling anything.
- **2026-07-25:** `/home/svc-vaporwave/bin/` holds four wrappers: `aedile-`, `vkv-inventory-`, plus **`crt-`** and **`nine-speakers-`**. crt is supposed to dispatch from dexter and nine-speakers is parked at weight 0. This is a live candidate explanation for the FABLE_REPORT finding nobody could explain — mandark's log showing crt dispatches after crt moved to dexter. Check this before assuming double-dispatch is hypothetical.
- **2026-07-25 (security):** `/home/svc-vaporwave` is mode **0777 recursively**, including `.claude/`, `.claude.json` (Claude credentials), `.gitconfig`, and `bin/` itself. Any local user can read that account's credentials and rewrite the scripts it runs unattended with its deploy keys into the shared media-arts-collective org. The separate account was adopted for usage isolation; at 0777 it provides no isolation, only an extra identity. Fix the modes (0700 home, 0600 creds) or drop the account.
- **2026-07-25 (decision still open):** re-admission of aedile/vkv-inventory was NOT done this pass, deliberately. Both confs warn that re-enabling locally without first removing the svc-vaporwave job runs them twice — and the 04:01 activity means that hazard is now evidence-backed rather than theoretical. Settle by verifying what runs under that account FIRST, then either (a) pull both back to zach's account and delete the svc-vaporwave path (retire, don't layer — the usage-paced governor now solves the quota problem the split was adopted for), or (b) keep the split and have `sync-crontab.sh` own a managed block in that account's crontab, since the sudo rights to do so already exist.
- **2026-07-25 — CORRECTION, the svc-vaporwave migration completed; aedile and vkv-inventory are NOT orphaned.** Read directly with `sudo -u svc-vaporwave crontab -l` (zach holds `(svc-vaporwave) NOPASSWD: ALL`, so this was always checkable): the crontab exists and has run both jobs. Evidence from today: vkv-inventory 04:00→04:05, "pushed: yes ... c2f7d9d" on `drilldown-browse-redesign`; aedile 03:00→03:06, pushed `aedile-nightly/2026-07-25` (c33eaeb) and opened PR #3 on media-arts-collective/wavebucks. The "confirmed 2026-07-24: no crontab exists there" claim propagated into `_paced.conf` (both lines), DESIGN-NOTES' silently-orphaned finding, BLOCKERS, and FABLE_REPORT.md's #1 ranked failure — **it was never verified against the account**, and it is false. `_paced.conf` corrected in place today; DESIGN-NOTES and BLOCKERS still carry it.
  - What IS true: aedile's `run.log` shows completed cycles on 07-20, 07-21, and 07-25 only — a real 07-22..07-24 gap, plausibly the world-writable `~/.ssh` that blocked `git push` (aedile's own 07-25 run fixed it and said so). So the symptom was real, the diagnosis was wrong, and the recorded fix (a human installing a crontab) would have been a no-op. Exactly the credential-gap lesson: a plausible explanation that fits the symptom is not a tested one.
  - What this changes: these two stay at weight 0 **as a correct choice, not a stalled migration** — re-enabling them here would double-dispatch against the live svc-vaporwave jobs. The real gap is observability: zach's registry, milestone-audit, glance and the proposed liveness audit are all blind to externally-dispatched projects, so two healthy projects read as dead. Liveness must key on *reports*, not on local registry weight.
  - **Security, unrelated to dispatch but found the same way:** `/home/svc-vaporwave` is recursively `0777`, including `.claude/` and `.claude.json` (that account's Claude credentials) and `bin/` (the four wrappers cron runs unattended with deploy-key access to the shared org). Any local user can read the credentials or rewrite what runs. The account was adopted for isolation and currently provides none. Not changed — it's another account's home and a live one; needs zach's call.
  - **APPLIED 2026-07-25:** `/home/svc-vaporwave` locked down. Was `0777` on 2,637 real files/dirs including `.claude.json` (that account's Claude credentials), `bin/` (the four wrappers cron runs unattended), and `.bashrc`/`.profile` — any local user could have read the credentials or injected code that runs as that account with deploy-key access to the shared org. Applied as `sudo -u svc-vaporwave`: home `0700`, recursive `go-w`, `.claude.json` + `.claude/*.json` `0600`, `bin/` and its four scripts `0700`. Now 0 real world-writable entries (85 remain by `find -perm -o+w`, all symlinks — `lrwxrwxrwx` is fixed on Linux and the target governs). `.ssh` was already correct: aedile's own 07-21/07-25 runs fixed it, which is what had been blocking its `git push`.
  - Witnesses: both deploy keys still authenticate post-change (`git ls-remote` as the account against `github-wavebucks` and `github-vkv-inventory` — OK/OK), so tonight's 03:00/04:00 pushes are unaffected. Report access is unaffected too: reports are symlinks to `/srv/vaporwave-reports`, which is `2775 root:vaporwave-reports` setgid and never lived in the home. Nothing of zach's reads that home (grepped `bin/`, `lib/`, `~/.local/bin`, crontab — no hits). Before-state saved outside the repo at scratchpad/svc-vaporwave-perms-before.txt.
  - Method note worth keeping: the first survey ran `sudo -n find ...` (root, no `-u`), which needs a password, failed, and with stderr dropped printed a clean "0 world-writable" — a fabricated all-clear from a silently failed command. The NOPASSWD grant is `(svc-vaporwave)` only. Same shape as the finding above it.

## Mechanisms queued from the 2026-07-25 propagation pass

<!-- The one-liners from this pass are DONE (see below). These are the ones
     that need real build time. Each names the incident it prevents. -->

- **[batch] `scheduler dispatchers`** — read every crontab (this account plus each conf's `CRON_ACCOUNT`), plus each `_paced*.conf`, and print who dispatches what, where, as whom. The point is to make conf comments describing system state unnecessary: the costliest failure of 2026-07-25 wasn't a bug, it was a true-once sentence nobody re-checked ("no crontab exists there") that outlived its verification by a day and drove a remedy that was a no-op. Highest value item here.
- **[batch] behind-origin / unpushed audit across working copies** — a daily check reporting, per registered project, commits behind origin and unpushed local commits. Measured 2026-07-25: crt 51 behind, groc-mangr 26, chezz 18, sequestria 15, nine-speakers 12, vim-arcade 11. Dispatch clones push to origin; nothing pulls the human-facing clones back, so every human-side edit starts on a stale base and can't fast-forward. Two `scheduler -i` idea commits (vim-arcade, wtul) were stranded this way — committed, push failed, message scrolled past.
- **[batch] bidirectional liveness** — the proposed `liveness-audit.sh` shouts when an enabled project has no recent report. Add the inverse: shout when a project registered as parked/weight-0 is producing FRESH reports. That second signal was sitting unread in `scheduler glance` (aedile 6h, vkv-inventory 5h) the entire time both were believed dead for four days.
- **[batch] one resolver for per-project path + ref** — `SCHEDULER_SUBDIR`, `BRANCH`, and the FOCUS.md path all come from the conf through a single shared helper that any tool can call. Today three separate things hardcoded a project's FOCUS path or branch and each broke independently: chezz's pre-commit allowlist (missed the `.claude`→`.scheduler` move), realisateur's `inject-suggestions.sh` (same), and wtul's injection landing on a feature branch its wrapper never reads. Config-from-one-source, applied to paths and refs rather than ports.
- **[batch] hygiene-lint row: stamped-checklist drift** — BUILD-DISCIPLINE.md's checklist gained three rows on 2026-07-25 (`3be6629`); the copies already stamped into each project's CLAUDE.md now lag the baseline and nothing detects that.

## AUTONOMY_TIER engine enforcement built (2026-07-25, human-directed: "replace me as the valve")

`lib/autonomy-merge.sh` now enforces `AUTONOMY_TIER="high"` for real (test-gated
auto-merge+push, modeled on `scheduler-dev-cycle.sh`'s `merge_mode()`), wired
into `lib/sweep-loop-common.sh` (runs at the end of every sweep/batch cycle,
conf-based or legacy-wrapper) and a new one-off `scheduler autonomy-sweep
[project]` subcommand. groc-mangr/vim-arcade (already `high`) got
`BATCH_TEST_CMD`; wtul raised `low`→`high` gated on pytest; vkv-inventory
raised `medium`→`high` ungated (no test suite; safe only because its clone is
a dev copy, not the live media-arts-collective site — see the comment on
`AUTONOMY_TIER` in `schedule/vkv-inventory.conf`). Ran once against the
existing backlog: vkv-inventory (5/5), groc-mangr (1/1), vim-arcade (1/1)
cleared; wtul 2/8 (6 hit real merge conflicts, correctly left for manual
review — see `bin/wtul-rip`/`tests/test_wiring.py` across
discid-rerip-cache/ocr-metadata-extraction/rip-rehearsal-harness/
rip-speed-monitoring/spin-live-watch/web-photo-capture).

- **[batch] fix stale "not built yet" claims** — `bin/scheduler`'s
  `cmd_explain` (was lines ~217, 300-302) and this file's own "not yet
  built"/"real design work for a future session" language (was lines
  ~189-192, 2087-2090) both now describe an unenforced field; update to
  reflect the above, per BUILD-DISCIPLINE's "claims re-probed, not quoted."
- **[batch] monthly autonomy-tier policy-revisit watcher** — a `CronCreate`
  job (proposed: 1st of the month) that greps `[autonomy-tier:high, ...]`
  merge-commit tags across the high-tier projects' dedicated clones since
  the last review, summarizes auto-merge vs. gate-failure vs. conflict-abort
  counts, and appends a dated entry here asking whether the tier/gate policy
  needs to change. A check-in, not an auto-adjuster — surfaces data, doesn't
  act on it.
- **RESOLVED 2026-07-25, both items above, human-confirmed.**
  `drilldown-browse-redesign` was real, independent 11-commit work (browse/
  drilldown UI + style-default sync tests) that had been evolving on the
  DISABLED `vkv-inventory-bug-sweep` clone since before it was disabled,
  unreconciled with `main` the whole time (true 11-ahead/11-behind
  divergence from a shared ancestor, not a stale-cache artifact). Merged
  clean (no conflicts), its own two `tools/test_*.mjs` suites re-run first
  (13/13 passing), pushed to origin/main (`5caf704..7817158`). wtul's
  personal-working-copy divergence turned out to be nothing: diffed content
  (not just messages) on all 4 "local-only" commits — 3 were byte-identical
  patches already on `main` under different SHAs (replayed independently by
  the automation clone), the 4th (a raw fable-review note) was already
  present on `main` in triaged/resolved form. Stale local branch deleted;
  nothing was lost.
  - **Root cause, not "bad git discipline":** a clone nobody fetches
    silently diverges, whether it's an automation clone for a disabled
    tier or a human's own personal working copy — same mechanism the
    2026-07-25 propagation pass already queued a fix for below
    ("behind-origin / unpushed audit"), just caught here in two more
    places (a *disabled* tier's clone, and a personal checkout, neither of
    which that item's current wording calls out explicitly).
  - **[batch] extend the behind-origin audit to cover clones the current
    wording misses:** (a) dedicated clones for DISABLED tiers
    (`SWEEP_JOB_NAME=""` etc.) — today's audit item only mentions "human-
    facing" working copies and active dispatch clones, so a disabled
    clone like vkv-inventory-bug-sweep's is invisible to it and can drift
    for weeks unnoticed; (b) personal working copies whose branch names
    collide with a dedicated automation clone's branch names for the same
    project (wtul's `label-printer-integration` existed independently in
    both zach's checkout and the batch clone) — flag the collision, not
    just the ahead/behind count, since "diverged" reads as alarming when
    the content is actually identical and reads as safe-to-drop when it
    isn't.
  - **Method note worth keeping, not just fixing in tooling:** before
    trusting an "N commits ahead/behind" count enough to act on it (merge,
    discard, or panic), fetch fresh and diff actual patch content, not
    commit messages or counts — same message + different SHA can mean
    "identical, already safe" (wtul, here) or "genuinely diverged, use it"
    (vkv-inventory, here) and the count alone doesn't distinguish them.

- **2026-07-28 (interactive `/cloture`, scheduler session): deferred
  cross-writes to realisateur, and the reason this row exists at all.**
  `check-project-busy realisateur` = BUSY (pid 1937642, a different
  interactive claude, since 07:54:28; my own session is 1933794 — checked,
  not assumed, because the two locks look identical in the output). So the
  writes were correctly declined. They were then **announced in a chat
  summary and nowhere else**, which is the live exhibit of the failure
  pattern already proposed one screen up in this same file: *a correct
  refusal that nothing retries.* Filing it properly is the point; the row
  above predicted this exact loss and I still had to be asked before I
  wrote it down.

  ~~[batch] DEFERRED CROSS-WRITE, realisateur was BUSY:~~ **RETIRED
  2026-07-28 by realisateur `f9e6462`** — the lock cleared during the same
  session, so the real write was made rather than left as a stub. This is
  the pattern-16 rule working as intended: re-check the lock at close, do
  not assume still-blocked. Struck rather than deleted, so the deferral
  and its discharge are both legible.
  Original payload: realisateur's
  `.scheduler/FOCUS.md` had no record of the overnight cybernetics study.
  Branch `research/ecosystem-cybernetics`, pushed, `ddd422b` (100
  generations of results + `TECHNICAL-MANUAL.md` +
  `PHILOSOPHY-AND-CRITIQUE.md`) and `29c90ab` (`ELI5.md`). Headline
  findings, so the record is usable without re-reading the sims:
  reconciling co-blind sensors adds ZERO variety (`A_baseline` and
  `B_more_sensors` identical to the digit in all 20 cells — so
  `sensor-agree.sh`, queued in `UNIVERSE.md`, is aimed at the wrong
  invariant); a third symbol cuts undetected disturbance ~92% and survives
  hostile parameterisation; slack buys latency tolerance, NOT detection;
  local repair and null-discrimination are complements. Four self-inflicted
  defects are named in the manual's §8 — including a metric that read 0.0
  for 50 generations because it was structurally unable to fire, which is
  the study's own subject matter committed by the study's own instrument.

  ~~[batch] DEFERRED CROSS-WRITE~~ **RETIRED 2026-07-28 by realisateur
  `f9e6462`**, which carries the do-not-promote marker verbatim.
  Original payload: the study's strongest
  observation is UNREGISTERED and must be guessed-first-then-tested before
  it counts. A sensor that fails toward OK scores PERFECTLY on every
  dashboard metric (0.00 wasted attention, 1.00 trust, zero false alarms)
  while carrying 688 undetected ticks and 1062 false cleans. Generalised:
  *a silent sensor optimises every observable metric*, so any regime that
  rewards a dashboard selects for silence. This is doctrine-shaped —
  candidate for `BUILD-DISCIPLINE.md` alongside pattern 14 — but it must
  go through `sim/prereg.py` first, and `prereg.py` refuses to backdate.
  Do NOT promote it to a finding on the strength of this row.

  ~~[batch] Also unfiled in realisateur~~ **RETIRED 2026-07-28 by
  realisateur `f9e6462`.** Original payload: `bin/silence-audit.sh` and
  `bin/install-silence-audit.sh` remain staged-only on
  `staging/silence-audit` (`39d64e0`, pushed, upstream clean), uninstalled
  and unwired by design. The install script is dry-run by default, names
  what it retires, and gates on three tests. Nothing dispatches from that
  branch, which is intentional — but it means the artifact has no reader,
  and that is pattern 2 with a longer fuse.
