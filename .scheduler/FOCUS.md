# FOCUS — scheduler (what its own nightly job should work on)

The scheduler's Tier 2 job (`/nightly-batch`) is scoped by this file, same
as every other project. Difference: this project is the **meta-tool** that
controls all the other jobs.

## Stability milestone

**Current:** scheduler dispatches every registered project unattended with zero silent failures — a run that gets cut off, can't push, or has its assumed external dependency (a migrated crontab, a credential) quietly stop being true is always flagged loudly, never left to look like nothing happened — and the user can explain how the system actually works instead of just trusting `bin/scheduler` to smooth over the parts they don't follow — status: in-progress
Done when:
- [ ] Stale `.active`-marker / stranded-run detection built (a run cut off before any commit shows up nowhere today — see "NEXT UP" note above, `scheduler sweep`'s natural next extension)
- [ ] Stale/incomplete-push visibility built (`pushed: no` in `scheduler status`/`sweep.log` says WHY — spend-limit cutoff vs. something else — instead of a silent generic no-op; this is what the 2026-07-24 chezz/wtul credential-gap misdiagnosis actually needed and didn't have)
- [ ] Generalized "disabled-with-unverified-external-dependency" sweep built (any `_paced.conf` line disabled with a `# migrated to X` comment gets its claimed destination checked to still exist — the exact gap that let aedile/vkv-inventory sit undispatched 4 days undetected, fixed by hand 2026-07-24 but not yet generalized so it can't recur elsewhere)
- [ ] A real, honest explainer of how the system currently works exists (e.g. `scheduler explain`/`scheduler help` — a walkthrough a human can hold in their head, not another design doc for an agent)

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
2026-07-24 via realisateur's `/ideate`, human-directed this pass — the
four checklist items are scheduler's own already-stated "Current focus"
priorities below, formalized into a checkable bar, not new scope.)*

**Push policy (changed 2026-07-18, human-approved):** the nightly job MAY
push its own commits directly to `origin/main` — no `nightly/<date>` branch,
no human merge step required. This is *not* a license to skip review after
the fact: every push MUST be flagged prominently in that night's report
(what was pushed, why, and how to revert it — e.g. `git revert <sha>`) so
the human can review it the next morning same as before, just after the
fact instead of before. See item 6 in Current focus for the sequencing
requirement (push after other jobs, before morning) and conflict-awareness
work still to build before leaning on this. Until that safety work lands,
prefer the old review-gate branch behavior for any change riskier than a
docs/FOCUS-only edit.

**Merge policy (changed 2026-07-19, human-directed):** `bin/scheduler-dev-cycle.sh`
now merges each finished paced cycle's commits from `paced/<date>` into
*local* `main` right after the cycle (`git merge --no-ff`), instead of
leaving them on the branch for a manual merge first. Review still happens —
just after the fact (`git show <merge-sha>`, revert with
`git revert -m 1 <merge-sha>`) instead of before. This is a **toggleable
flag**, not a rewrite of the safety model: `~/.local/share/scheduler-paced-dev/merge_mode`
holds `merge` (default, new behavior) or `branch` (old behavior, commits
stay on the branch for manual review/merge). The cycle also self-guards:
if `main` isn't clean and checked out in the scheduler repo when a cycle
finishes (e.g. another session has an in-progress edit, as has happened
with `crt.conf`), it automatically falls back to leaving commits unmerged
rather than merging into a dirty tree. **Still separate from and unaffected
by this: pushing to `origin` stays exactly as cautious as the push policy
above** — this only changes local-main merge timing, not whether/when
anything reaches GitHub.

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
   - **NEXT UP (queued 2026-07-20, human-directed): stale `.active`-marker
     / stranded-run detection.** Design already written up in this
     file's stranded-commit section above (record what a run is
     attempting, and have `bin/scheduler`/`morning-report.sh` flag a
     `~/.local/share/scheduler-registry/<PROJECT_KEY>.active` marker
     that's older than a job's typical runtime with no matching
     completion). `scheduler sweep` now covers the git/commit half of
     "did a run get cut off" (dedicated-clone check, added same
     session) — this is the other half: a run that got cut off before
     ever making a commit at all wouldn't show up in sweep, only in a
     stale `.active` marker. Natural fit for `sweep` itself once built
     (same 15-minute tick already exists), not a new mechanism.
   - **Same shape, found for real 2026-07-24 (see DESIGN-NOTES.md
     "silently-orphaned finding"): `_paced.conf` disabled aedile and
     vkv-inventory on the unverified assumption their migration to
     svc-vaporwave's crontab had completed — it hadn't (`crontab -l`
     came back empty), so both sat with zero dispatch for 4 days and
     nothing caught it.** Generalize the sweep to also check: any
     `_paced.conf` line disabled with a `# migrated to X` comment should
     have its claimed destination (a crontab entry, another conf's
     participant line, whatever X is) verified to actually exist —
     flag drift the same way a stale `.active` marker gets flagged.
     Scheduler's job here is only the mechanism check; what to DO about
     a confirmed-orphaned participant (finish the migration vs. pull it
     back) is realisateur's call, queued to its inbox separately.
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
2. **Write a clear, honest explainer of how the current system actually
   works, for the user's own understanding** — not another design doc
   for an agent to read, a genuine "here's what happens when you do X"
   walkthrough a human can hold in their head. Concrete candidate home:
   `bin/scheduler help` or a new `scheduler explain` subcommand that
   prints exactly this, so understanding lives next to the tool, not in
   a file that goes stale. Not started yet.
3. **(parked, per the Stability milestone above)** Only after 1-2 are
   genuinely solid: revisit item 0, the consolidation roadmap axes below,
   and any other bigger redesign — same "vision debt" discipline applied
   to this file's own backlog, not just to individual project ideate
   sessions.

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

## Watch and report tonight

- **Per-project pre-commit hook cost.** Unattended sweep/batch jobs commit
  *per item*, so each commit pays that project's pre-commit hook. chezz's
  hook runs the full Playwright suite (>2 min) — observed 2026-07-18 stalling
  a commit past a 2-min tool timeout. Across several commits that silently
  eats the turn/time budget and can leave a commit half-made on a timeout.
  Scheduler is the right place to be aware of this (it owns the budget and
  the optimal-usage work). Tonight: don't fix it, just **surface it** — note
  in the report which registered projects have a heavy pre-commit hook and
  roughly how long, and propose the cheapest awareness mechanism (e.g. the
  engine timing each `git commit` into the state dir so `morning-report.sh`
  can sum per-project commit overhead, and/or a conf note per project). A
  natural sibling to the `USAGE_GATE_CMD`/token-logging idea already in the
  backlog. Do not touch other projects' hooks or `--no-verify` their commits
  from here — that's each project's own call.

## Backlog (the intake — add a line to propose an idea)

- **2026-07-24 03:40 (via `scheduler -i`):** Two real bugs found 2026-07-24 while setting up realisateur's milestone convention, both stemming from the same wrong assumption: aedile has NO git repo, treated as migrated/defunct. That was wrong -- verified directly (should have done this before writing it down, per tonight's earlier credential-gap lesson): aedile IS a real, actively-committed project (5 recent commits, e.g. 'aedile: DM-tier bump/triage tuning'), just tracked as a subdirectory of the wavebucks monorepo at /home/zach/Documents/vkv/wavebucks (its own .git lives at the parent, not at aedile/ itself). Bug 1: bin/scheduler's git-health check (~line 622) uses [ -d "$repo_path/.git" ], a literal directory check that fails for any PROJECT_REPO_PATH pointing at a subdirectory of a repo rather than a repo root -- same failure mode would hit any future monorepo-subdirectory project, not just aedile. Fix: use 'git -C "$repo_path" rev-parse --is-inside-work-tree' (or similar) instead of the literal .git-dir check. Bug 2: aedile already uses the .scheduler/ subdirectory layout in practice (aedile/.scheduler/FOCUS.md is real, git-tracked, actively updated) but schedule/aedile.conf never declares SCHEDULER_SUBDIR=".scheduler" -- so any tool reading that field (realisateur's milestone-audit.sh, sync-crontab.sh's own symlink logic) misses it. Fix: add SCHEDULER_SUBDIR=".scheduler" to schedule/aedile.conf to match its real layout. Routing both here per realisateur's ideate.md step 5 front door (engine detection logic + registration conf) rather than hand-editing scheduler's own files from realisateur.

- **2026-07-24 01:33 (via `scheduler -i`):** Root cause found 2026-07-24 for the 'stranded local commit' pattern seen on chezz and wtul nightly-batch runs (previously misdiagnosed by realisateur's /ideate as a dedicated-clone-vs-working-checkout push race): it's a credential gap, not a race. The dispatch environment can push to local bare remotes (crt, realisateur, gardien, senechal) fine, but has no SSH credentials for GitHub-hosted remotes (chezz + wtul both use git@github.com:hf7y/...). Their nightly-batch runs commit successfully but the push step silently fails/is skipped, leaving commits local-only until a human or interactive Claude Code session (which does have working credentials) pushes them by hand -- confirmed tonight by manually pushing wtul's 51e2545 and chezz's 0189195, both landed cleanly. Proposal: either (a) give the dispatch environment's SSH agent/keys access to the github.com host (deploy keys or agent forwarding, scoped read+write to just these two repos), or (b) if that's intentionally not wanted (e.g. credential-scope hygiene), make the failure LOUD in scheduler status / sweep.log instead of the current silent 'pushed: no' with no reason given, so it reads as 'needs a human push' rather than looking like a generic failed run. Either is scheduler's call -- routing here per realisateur's ideate.md step 5 front door rather than hand-fixing dispatch config from realisateur.

- **2026-07-24 00:57 (via `scheduler -i`):** Realisateur's stability-milestone convention (see realisateur/STABILITY-MILESTONES.md) asks whether scheduler itself (the engine, not a scaffolded project) should participate. Decided 2026-07-24 via /ideate: yes, give the engine a milestone too -- even mechanism benefits from a stated stability bar (e.g. 'reliably dispatches N registered projects with zero silent failures/stranded commits'). milestone-audit.sh currently reads scheduler as no-focus since its FOCUS lives under .scheduler/ not .claude/ -- either teach milestone-audit.sh to also check .scheduler/FOCUS.md, or add a lightweight '## Stability milestone' section directly to scheduler's own .scheduler/FOCUS.md. This is scheduler's own engine/FOCUS file to decide the shape of, routed here per realisateur's ideate.md step 5 front-door rule rather than hand-edited from realisateur.

- **2026-07-23 23:55 (via `scheduler -i`):** Unify a status/admission taxonomy across the ecosystem: 'active vs parked vs waiting' for vision/idea items is the SAME underlying need as the BLOCKERS.md blocking/waiting/fyi taxonomy (the parked 'Spec-out-a-more-principled-eco' idea). Proposal: one shared status vocabulary + convention that serves both vision-backlog items (FOCUS.md) and blockers (BLOCKERS.md), so counts reflect real commitments, not the free-growing reservoir. Surfaced by realisateur /ideate 2026-07-23 vision-debt strategy pass (see realisateur FOCUS.md) — this is the mechanism that makes milestone-gated parking legible in glance/status views. Realisateur owns the vision-item half; this -i note is for scheduler's convention/engine half.

- **2026-07-23 12:50 (via `scheduler -i`):** eventually during high season, we'll need google calendar integration. a way to invite small teams to their meetings, input deadlines, etc

- **2026-07-23 09:24 (via `scheduler -i`):** add a column in scheduler noargs view to show last run as well as next up. last run timestamp, next run timestamp. specific next up task text can be moved to projects individual status view to save space, though open jobs can stay.

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

- **2026-07-22 15:19 (via `scheduler -i`):** should the idea intake in scheduler actually file things to realisateur first so it can triage/prioritize? or actually file in both locations. should realisateur properly run before other jobs within a certain window? or should those ideas await implementation until realisateur analyses them? wondering how ideas intake should evolve based on the evolving scheduler/realisateur split. drop questions to me about this if appropriate but also pick off low hanging fruit if an obvious principled first step or steps is available right now

- **2026-07-22 14:17 (via `scheduler -i`):** committed locally in /home/zach/Documents/Project Archive/scheduler -- run 'git -C /home/zach/Documents/Project

- **2026-07-22 14:13 (via `scheduler -i`):** fix the graphical display of the no args schduler view. columns don't really make sense. implement the merger of questions and blockers into one view (at least inside this bin utility ahead of formal merge). drop a line explaining + and ✓ convention. introduce estimated run time, estimated usage, and also number of tasks open. number of tasks expected to run

- **2026-07-22 (Zach, via chat): shipped the cheap slice of priority
  ordering — `bin/scheduler`'s no-arg glance now sorts rows by
  `q_unanswered + blocker count` descending instead of conf/registration
  order** (see [[scheduler-usage-pacing]]-adjacent 13:59 backlog entry
  above for the fuller quota/ETA-aware target this is a stand-in for).
  Two related pieces scoped but deliberately NOT built this pass:
  - **Tab-completion for `scheduler <project>`/subcommands** — a bash
    `complete -F` function (or `bin/scheduler-completion.bash` to source)
    reusing the existing `projects()` list in `bin/scheduler`. Purely
    mechanical, no design work needed, just didn't fit this pass.
  - **`scheduler <project>` direct shorthand** — one truncated view
    combining that project's focus/questions/blockers with "expand"
    hints, instead of requiring `-f`/`-q`/`-r`/`status` separately. A
    smaller, buildable-now slice of item 0's "merged report" vision
    above — item 0 as designed is bigger (full print-friendly merged
    file with reply hooks); this would be a thinner read-only first cut
    reusing today's separate files, same spirit as how item 3's first
    cut skipped ahead of its own (a) step.
  **Priority-adjustment (a `scheduler priority <project> <n>`-style
  command) and bug/feature tagging on backlog items stay vision-level,
  not scoped further here** — Zach's own framing this session was
  explicitly "later," and both need a real schema decision (where does a
  priority/tag live — a conf field? an inline prefix agents must honor
  when writing `-i` entries?) before either is buildable, not just an
  implementation pass.

- **2026-07-22 14:02 (via `scheduler -i`):** revisit integration with realisateur. realisateur should not promote ideas to scheduler until out of an incubation period. this prevents the scheduler status from getting crowded with nacent ideas. potential automated flag whereby scheduler suggests projects migrate to realisateur if they're underdeveloped (few files, nothing pending). eventual symmetrical structure to move projects to archive once out of development

- **2026-07-22 13:59 (via `scheduler -i`):** streamline the cli flow. scheduler no args should produce what's scheduled, in order of priority, with information about next run, time/cost etc. scheduler <project> should tab-complete. should show more detail about project including next tasks/requests in order of priority. flag design can remain for backwards compatibility. focus questions blockers should all be called out in the project view (truncated with suggested command to expand if too many lines). should have an easy way to promote a project's urgency in both the main scheduler view and it's individual project. start developing and maintaining a man page for scheduler that explains its use.

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

- **2026-07-20 21:40 (via chat, queued for later):** `lib/sweep-loop-common.sh`'s
  `notify-send` calls have no `2>/dev/null || true` guard (unlike aedile's
  bespoke wrapper, which already has this) -- on a headless account with
  no D-Bus/desktop session (confirmed on `svc-vaporwave` running
  `vkv-inventory-nightly-batch-loop.sh`: `Error calling StartServiceByName
  for org.freedesktop.Notifications: Timeout was reached`), each call
  burns real wall-clock time waiting on a timeout instead of failing
  fast. Not correctness-breaking (the run still completes), just wasted
  time on every cron fire for any headless account sourcing this engine.
  Fix: add the same `2>/dev/null || true` guard to every `notify-send`
  call in the shared engine.

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

- **Batched, not built now 2026-07-20: `scheduler -i <project>` with no
  text argument should open `$EDITOR`** instead of failing with a usage
  message — pre-populate a blank templated bullet at the backlog
  insertion point (so existing/older ideas are naturally visible right
  there, no separate "show parked ideas" feature needed) for a normal
  project; for realisateur, open a fresh empty `.idea` file. After the
  editor closes: if real content was typed, run it through
  `cmd_commit_file` same as today; if the placeholder was left untouched,
  clean up rather than leaving a stray empty entry. Deliberately NOT
  building a richer "surface my parked ideas for me" UX here — that's
  explicitly realisateur's future abstract-visioning scope (see its own
  FOCUS.md), not something to guess at from scheduler's side.
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
- **Right-size per-tier model choice** (see Cost insight above) — audit each
  registered project's `schedule/*.conf` `<TIER>_MODEL` fields; identify
  which nightly/batch tiers are running Opus (or Opus-priced reasoning) for
  work that's mechanical enough for Sonnet, and propose the downgrade
  per-project (don't silently change other repos' confs from here — flag it,
  same as other cross-project proposals). Opus is ~5x Sonnet per token, so
  this is likely the single cheapest lever for slimming automation cost.

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
   one-tier-at-a-time move. **Next unattended cycle: execute MIGRATION.md
   for one project/tier** (read the wrapper, copy its config into the
   conf's runtime fields, drop the `*_SCRIPT` line, verify `sync-crontab.sh`
   preview is byte-identical except for the entrypoint line, apply). Pick
   the lowest-risk project first (home-assistant or wtul — single tier,
   no web tracker to break) rather than chezz/vkv-inventory's dual-tier
   setups. One project per cycle, not all four at once.

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

2. **Sweep pacing** — Tier 1 bug-sweeps (chezz, vkv-inventory) have been
   sitting paused (`SWEEP_JOB_NAME=""`) since the usage-paced governor
   migration orphaned them. **Decision made 2026-07-20: fold sweeps into
   the main `_paced.conf` rotation** as ordinary participants alongside
   the Tier 2 batches (not a separate faster rotation) — accept the
   cadence drop (once per full rotation lap instead of every ~15min) as
   the tradeoff for one dispatcher instead of two. **Next unattended
   cycle: add chezz's and vkv-inventory's bug-sweep wrappers to
   `schedule/_paced.conf`, un-pause `SWEEP_JOB_NAME` in their confs**
   (pointing at the paced runner path, not a fixed cron), verify with a
   `sync-crontab.sh` preview that the fixed sweep cron lines are now
   suppressed the same way batch lines already are for paced participants.

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
