---
description: Interactive vision/triage pass for the scheduler project itself -- pull live state, surface blockers and divergence, ask direct design questions, record decisions into DESIGN-NOTES and GitHub issues, and queue work for the nightly self-run. Does NOT build inline unless explicitly told to.
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
nightly self-run, so decisions land in `DESIGN-NOTES.md` and the work and
questions land as **GitHub issues on `hf7y/scheduler`**.

**`FOCUS.md`, `QUESTIONS.md` and `BLOCKERS.md` are retired** (#66,
2026-08-07) and DELETED (hf7y/realisateur#293). Never restore
them, and do not create a new top-level `.md` — `schedule/_standing-rules.md`
rule 5 ("NO NEW MARKDOWN FILES") and `bin/markdown-cost.sh` both enforce
this at merge.

## 0. Priority-order arguments (if given)

`ARGUMENTS` may pass a `:`-separated lens order, e.g. `vision : milestone
: jobs : blockers : quickfix`. This is NOT decorative -- if given, state
it back verbatim before doing anything else (`Priority order this pass:
vision > milestone > jobs > blockers > quickfix`), and:
- Address lenses in the stated order -- don't let a later lens (e.g.
  quickfix) get worked before an earlier one (e.g. blockers) has been
  looked at this pass.
- In the step-5 summary, report each lens as **covered** (found +
  surfaced/recorded something) or **skipped** (nothing live under it
  this pass) -- explicitly, by name, not folded into prose. A lens with
  nothing to say still gets a one-line "skipped: nothing live."
- If no `ARGUMENTS` are given, skip this step silently -- the ordering
  only applies when the caller actually specifies one.

## 1. Orient

Pull real, current state before saying anything about status:
- `git log --oneline -10`, `git status`, and `git rev-list --left-right
  --count origin/main...main` -- sync first if behind.
- **Live quota**, if the question touches pacing/burndown: `bash
  bin/usage-gate.sh`. It reads whichever account the CLI is logged into.
  Account model (decided 2026-07-24, see DESIGN-NOTES): primary = Claude
  Max, **always logged in**, pools all personal work; svc-vaporwave =
  nonprofit only. So a primary reading is now stable and trustworthy --
  but during the transition confirm you're actually on the primary before
  attributing a number to it (an earlier pass misread svc-vaporwave's
  quota as the primary's).
- `gh issue list --repo hf7y/scheduler --state all --limit 200` -- the
  existing queue and already-decided direction. Read the COMMENTS on an
  open issue before treating it as unaddressed: Zach answers by commenting
  and leaving the issue open, so issue state is never an answer signal.
  Don't re-ask a settled decision.
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
  counts/quotes (git history, usage-gate output, issue dates), not
  vibes.
- **Already-settled** -- matches DESIGN-NOTES. Note it's unchanged
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
- File the work as a **GitHub issue** (`scheduler -i`, or `gh issue create
  --repo hf7y/scheduler --body-file <file>`), pointing back at DESIGN-NOTES
  for detail. One issue per discrete item, with enough context that a fresh
  agent could execute it.
- If a decision needs a follow-up only the **user** can do -- scope,
  credentials, a physical/account action, something outside this repo --
  that is an issue too, not just a mention in chat. Do not write it into a
  markdown file; that is the failure #66 retired.
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
letting the gap stay invisible. When you touch the queue, if it's been
growing without draining, **say so explicitly** in the step-5 summary --
rough queue depth, oldest un-started item's age, accrual-vs-clear trend
(intake is zero-cost and unthrottled; clearing is quota-gated and shared
across paced jobs). The user's own call whether that's fine or a signal
to re-scope or throttle intake; this command just makes the gap visible.

## 5. Commit, push, and stop

Commit the `DESIGN-NOTES.md` / `schedule/_paced.conf` changes on a branch
and open a PR -- `main` is protected, so a direct push is rejected for
everyone. Follow `claim-drift --convention` verbatim. End with a short
summary: what's now queued and in what order, what issues are still open
for the user, and explicitly confirm no implementation code was touched
(or, if
the user asked for an inline fix, what it was and that it's separate from
the queue). If a priority-order argument was given (step 0), report each
lens's covered/skipped status by name here.
