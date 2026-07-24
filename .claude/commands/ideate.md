---
description: Interactive vision/triage pass for the scheduler project itself -- pull live state, surface blockers and divergence, ask direct design questions, record decisions into DESIGN-NOTES/FOCUS/QUESTIONS and queue work for the nightly self-run. Does NOT build inline unless explicitly told to.
---

The interactive counterpart to `/nightly-batch` (unattended). Where the
batch implements, `/ideate` triages, prioritizes, and records -- it
exists because an ordinary interactive session drifts into implementing
whatever's asked, which is right for a concrete request but wrong for
open-ended prioritization or a real design fork. Default posture:
**surface, ask, record, queue -- not build.** The user can always say
"just fix that now" to override for any one item; that's a normal
request, not a violation of this command.

Ported from chezz's `/ideate` (2026-07-23), adapted to scheduler's own
file model: this repo is maintained by hand AND runs a review-gated
nightly self-run (see `.claude/scheduler/FOCUS.md`), so decisions land in
`DESIGN-NOTES.md` + `.scheduler/FOCUS.md` + `.scheduler/QUESTIONS.md`,
not a game tracker.

## 1. Orient

Pull real, current state before saying anything about status:
- `git log --oneline -10`, `git status`, and `git rev-list --left-right
  --count origin/main...main` -- sync first if behind (stash/pop around
  any uncommitted `QUESTIONS.md` answer sitting there).
- **Live quota**, if the question touches pacing/burndown: `bash
  bin/usage-gate.sh`. It reads whichever account the CLI is logged into.
  Account model (decided 2026-07-24, see DESIGN-NOTES): primary = Claude
  Max, **always logged in**, pools all personal work; svc-vaporwave =
  nonprofit only. So a primary reading is now stable and trustworthy --
  but during the transition confirm you're actually on the primary before
  attributing a number to it (an earlier pass misread svc-vaporwave's
  quota as the primary's).
- `.scheduler/FOCUS.md` (Current focus, Backlog, Vision, Consolidation
  roadmap), `.scheduler/QUESTIONS.md`, `BLOCKERS.md` -- the existing
  queue and already-decided direction. Don't re-ask a settled decision.
- `schedule/_paced.conf` weights + `docs/priority-weight.md` if the pass
  is about relative project priority.

## 2. Find what's actually worth surfacing

Sort what you find into:
- **Urgent, small, low-ambiguity** (a regression, a stranded commit, a
  broken tooling path) -- flag it, propose the fix, don't implement
  unless told to. Usually not worth an `AskUserQuestion`: one sensible
  answer, just say so.
- **Real design forks** -- multiple plausible, conflicting directions.
  These are what `AskUserQuestion` is for. Ground each in real
  counts/quotes (git history, usage-gate output, FOCUS.md dates), not
  vibes.
- **Already-settled** -- matches DESIGN-NOTES/FOCUS. Note it's unchanged
  and move on; don't re-litigate.

## 3. Ask, don't guess

For genuine forks, ask directly (`AskUserQuestion`, up to 4 per call,
options with real tradeoffs). Don't implement speculatively while
waiting -- the answer changes the shape of the work, not just priority.

## 4. Record and queue, don't build

For each decision (new or re-confirmed):
- Write the decision **and its rationale** into `DESIGN-NOTES.md` --
  future sessions and the nightly self-run need the "why." If it
  corrects an earlier entry, say what changed rather than silently
  overwriting.
- Update the relevant section of `.scheduler/FOCUS.md` (Current focus,
  Backlog, or Consolidation roadmap), pointing back at DESIGN-NOTES for
  detail -- keep FOCUS.md entries short.
- If a decision needs a follow-up only the **user** can do -- scope,
  credentials, a physical/account action, something outside this repo --
  append a real entry to `.scheduler/QUESTIONS.md`, not just a mention in
  chat.
- Mechanical priority changes (`_paced.conf` weights) are fair game to
  apply here when human-directed, but note in the comment that
  realisateur owns re-tuning them over time.
- **Do not build feature/tooling code in this step.** Implementation is
  `/nightly-batch`'s job. Exception: something explicitly urgent and
  small the user asks you to just fix now.

## 4.5. Watch for "vision debt" -- the queue growing faster than it drains

Named 2026-07-20 (cross-project pattern, originated in this very repo):
the user generates ideas faster than any implementation cadence can
stabilize them, so a backlog that only grows is the expected shape of the
problem, not proof this command is failing. What *would* be failure:
letting the gap stay invisible. When you touch the Backlog, if it's been
growing without draining, **say so explicitly** in the step-6 summary --
rough queue depth, oldest un-started item's age, accrual-vs-clear trend
(intake is zero-cost and unthrottled; clearing is quota-gated and shared
across paced jobs). The user's own call whether that's fine or a signal
to re-scope or throttle intake; this command just makes the gap visible.

## 5. Commit, push, and stop

Commit the `DESIGN-NOTES.md` / `.scheduler/FOCUS.md` /
`.scheduler/QUESTIONS.md` / `schedule/_paced.conf` changes. Push is
allowed for this repo without asking (see CLAUDE.md) -- flag the push in
the summary (what/why/how to revert). End with a short summary: what's
now queued and in what order, what's still open in `QUESTIONS.md` for the
user, and explicitly confirm no implementation code was touched (or, if
the user asked for an inline fix, what it was and that it's separate from
the queue).
