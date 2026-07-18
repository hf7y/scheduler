# Auditing the nightly batch: where the "todo" lives, where to check what happened

Written 2026-07-18 after tracing the chezz nightly-batch workflow end to
end. This is a description of how auditability works *today*, plus the
gap toward TODO.md item 2 ("make the tasks for nightly jobs auditable and
in one place ... as simple as editing a text file to introduce a new
idea"). It does not change any code — it documents what's already on disk
so the answer to "where do I audit the nightly?" lives in one place.

## TL;DR — where to look right now

- **What the nightly DID last night:** run `bin/morning-report.sh`. It
  cats every `~/reports/<project>/LATEST.md` and then every open item in
  `questions/<project>.md`. That's the single command to read the whole
  fleet's overnight output. (If it prints "No reports found", no project
  has produced a nightly report yet — e.g. chezz's first nightly-batch
  run is scheduled but had not fired at the time of writing.)
- **What the nightly is SUPPOSED to work on (its "todo"):** two separate
  sources, neither of which is a single editable file in this repo yet —
  see "The task queue" below.

## The three layers of the workflow

### 1. Input — what the night's work is drawn from

The nightly's todo is **not** one file. It's the union of:

- **The live tracker feature backlog** — the actual task queue. The
  nightly fetches `?scope=bugs&status=open&type=feature` (see the target
  project's `leaderboard/Code.gs` doc comment) and works it **oldest
  first**, a handful per night. For chezz these are player-submitted
  ideas that arrive through the in-game chat box, so the queue grows on
  its own and there is no text file to edit to add one — you'd POST to
  the tracker (or file in-game).
- **`.claude/FOCUS.md`** in the project repo — the hand-editable
  "what's live right now" scope/priority steer. This is the closest
  thing to "edit a text file to introduce an idea," but it is a *filter*
  ("only do work in service of this focus; defer the rest"), not an
  enumerated task list. It is read FIRST every run.
- **The `NIGHTLY:`-flagged big-bug handoff** — items Tier 1 (`/bug-sweep`)
  decided were too big and punted to Tier 2 (convention, see README
  "Two more standard pieces").

### 2. Output — the audit trail of what actually happened

Four independent records, in rough order of trustworthiness (objective →
narrative):

- **git history on `origin/main`** — the objective record. "An overnight
  run that is not saved anywhere didn't happen" (nightly-batch.md step 6).
  Every shipped feature is a real commit referencing its tracker report.
- **The tracker's per-report status** — each feature report the run
  touched is flipped to `resolved` (with a `Shipped in <hash>` note) or
  left `open` with a deferred note. `?scope=bugs&status=all&type=feature`
  shows the current state; `?scope=sweep-status` shows the last run's
  counts.
- **`~/reports/<project>/YYYY-MM-DD.md` + `LATEST.md`** — the run's own
  narrative: implemented (with hashes) vs. deferred (with blocking
  reason) vs. skipped (with why), what broke, backup work, open
  questions. `LATEST.md` mirrors the newest dated file. **Lives under
  `~/reports/`, not in this repo** — it is not committed anywhere.
- **`.claude/QUESTIONS.md`** (a real file at each project's repo root) →
  symlinked to `questions/<project>.md` here by
  `bin/sync-crontab.sh --apply` — the durable list of judgment calls that
  need a human. Survives past the one day its report is glanced at.

### 3. Aggregation

`bin/morning-report.sh` unifies layers-2 `LATEST.md` + `QUESTIONS.md`
into one read. It is the intended "check every morning" surface. It is
**not** wired to print git log or tracker status — those you check
directly if the narrative report raises a question.

## The gap (TODO.md item 2)

There is **no single, hand-editable, symlinked-into-each-project todo
file** for the nightly today. The two things that decide the night's work
are (a) the live tracker backlog, reachable only over HTTP, and (b)
`FOCUS.md`, which is per-project scope rather than a shared task list.
The audit *output* is well covered (four records above, aggregated by
`morning-report.sh`); the *input* is what TODO item 2 is really about —
"introduce a new idea by editing a text file."

Design options for closing it, cheapest first (not yet decided — this is
a note, not an implementation):

1. **Treat `FOCUS.md` as the editable todo and lean into it.** Already
   symlink-adjacent (its sibling `QUESTIONS.md` is already symlinked into
   `questions/`). Add a `questions/`-style `focus/<project>.md` symlink
   set in `sync-crontab.sh` so every project's `FOCUS.md` is browsable
   from one place in this repo. Zero new moving parts; the "todo" stays
   the scope file it already is.
2. **A shared `scheduler/nightly-tasks/<project>.md` inbox**, symlinked
   into each project as `.claude/NIGHTLY-TASKS.md` (mirror the
   `QUESTIONS.md` mechanism exactly, just the other direction), that the
   nightly reads as an additional task source alongside the tracker.
   Editing that file = adding an idea. Costs a new convention the nightly
   command files must all learn to read.
3. **Leave the tracker as the only queue** and add a tiny CLI in `bin/`
   to append a feature report from the terminal, so "edit to add an idea"
   becomes "run one command." Keeps a single source of truth (the
   tracker) but loses the plain-text-file feel item 2 asks for.

Recommendation: option 1 first (it's nearly free and makes the existing
todo auditable in one place immediately), and revisit 2 only if a
genuinely separate, non-player task inbox is wanted.

## Worked example that motivated this doc (chezz color feedback)

A concrete case showing why the audit trail matters: a chezz reporter
filed ~9 color/readability ideas (2026-07-17) as **feature** reports —
"revert to monochrome immediately", "king is hard to see", "mark squares
red/orange fire-emblem style". Because Tier 1 `/bug-sweep` reads only
`type=bug` by default, it never saw them and left the reporter's angry
`type=bug` note ("why are the colors not fixed?") with "no color report
exists" — technically true of the bug queue, misleading about the
product. The color work is legitimately **nightly (Tier 2) scope**, but
oldest-first ordering means a 55-item backlog could bury urgent
readability feedback for many nights. That tension — urgent player
feedback vs. fair oldest-first ordering — is exactly what `FOCUS.md` is
for, which is the strongest argument for making `FOCUS.md` the visible,
one-place, editable todo (option 1 above).
