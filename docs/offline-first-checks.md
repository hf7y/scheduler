# Pattern: offline-first checks, AI layered on top as an opt-in

`bin/scheduler status <project>` (added 2026-07-22) is the reference
implementation of a pattern worth reusing anywhere a project wants a
"how's this doing" check: **build the check entirely out of deterministic
scripting first, then offer AI as a strictly optional layer on top of the
same output** — never as the only way to get an answer.

## Why

The common case of checking in on something (repo health, pending human
feedback, open questions, last automated run's outcome) is almost always
answerable from files and `git` state that already exist on disk. Routing
that through an LLM call by default costs tokens and time for a question
a few scripts can answer instantly, and — more importantly — trains you
to reach for a full agent session even when nothing here requires
judgment. Reserve the AI step for the part that actually benefits from
it: narrating/prioritizing what the offline check already found.

## The shape

1. **A pure-script "build the report" step.** No `claude` invocation
   anywhere in it. In `bin/scheduler`, this is `build_status_report()`:
   git status/ahead/behind/diverged, `bin/collect-feedback.sh` output
   against any report/blockers file, an awk pass over a QUESTIONS-style
   file for unanswered entries, a log-tail for the last automated run's
   outcome. All of it plain bash/awk/git. Print this by default, always,
   free.
2. **An opt-in one-shot AI summary**, e.g. `--claude`: pipe the exact
   same report text into a single non-interactive `claude -p` call,
   restricted to **read-only tools** (`--allowedTools "Read,Grep,Glob"` —
   no `Bash`/`Write`/`Edit`), asking it to narrate/triage what's already
   there. This call must never be able to change anything; it's a report
   reader, not a dev cycle. Verify this empirically (diff `git status`
   before/after the call) rather than assuming the tool restriction
   holds — that's how `bin/scheduler status <project> --claude` was
   confirmed safe before being called done.
3. **An opt-in interactive session**, e.g. `--interactive`/`-I`: `cd` into
   the real project directory and `exec claude "<the same report text>
   ...starting context..."` — a human-driven session seeded with the
   identical offline report, for when the human wants to actually dig in
   rather than read a summary.

The three modes share one report-building function; only the last two
steps ever touch `claude` at all, and both are strictly additive to the
first.

## Applying this elsewhere

Any project that already has git-based state, a feedback/report
convention, and a QUESTIONS-style human-in-the-loop file (i.e. anything
following this scheduler's own conventions — see `SCHEDULER.md` in a
registered project for that shape) can build the same three-mode check
almost for free: reuse `bin/collect-feedback.sh` directly (it's generic —
works on any file with `%%TAG`/`> ` conventions, not just this repo's),
reuse the git ahead/behind/diverged logic (`report_divergence()` in
`bin/scheduler`, small enough to copy or source), and write one new
"tail the log for the last run's outcome" block per project's actual log
format.

The instinct to generalize: **before adding an AI call to any tool,
finish the version of it that has none.** If the AI call turns out to add
real value, layer it on top exactly as this pattern does — you'll know
because the offline report alone will have visibly left something out
that only judgment could supply (open-ended prioritization, unfamiliar
code context), not because building the AI path was easier than the
scripting path.

## A check must prove it RAN, not just that it exists (2026-07-28)

A check nothing calls is indistinguishable, from the outside, from a check
that calls clean. `bin/blockers-freshness-check.sh` spent two days
built-but-unwired here and nothing reported it — the sweep was quiet, and
quiet is what "no problems" looks like.

Static analysis cannot close this. Grepping for a check's name proves it is
*mentioned*, and a call site inside a branch that never executes greps
identically to a live one. What proves wiring is a **runtime witness**:

- Every check in `bin/` calls `check_witness` (`lib/check-witness.sh`) as
  its **first act**, before any early exit — a check that ran and came back
  BLIND still ran, and that is what the witness records.
- `bin/check-witness-lint.sh` reads the witnesses back and reports
  `NEVER RUN` (no witness ever written) or `STALE` (a witness that stopped
  being refreshed — it *was* wired and something unwired it).
- The witness call is never fatal. Bookkeeping that can break a check is
  worse than no bookkeeping; an unwritable witness surfaces as a finding in
  the lint instead.
- The reader runs **last** in `scheduler sweep`, after the passes that
  invoke the other checks, so a genuinely wired check can never be reported
  stale by the same sweep that just ran it.

This is the dead-man-switch shape (`EXPIRY_DAYS`) that this repo already
trusts for *jobs*, applied to *checks*. Any project accumulating its own
`bin/*-check.sh` collection wants it for the same reason: the checks
accumulate faster than the wiring, and only the wiring does anything.
