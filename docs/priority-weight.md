# Priority/pace weight: the scheduler/realisateur boundary

`schedule/_paced.conf` supports an optional `weight` field
(`name|enabled|weight|command`, weight omitted defaults to 1) that
`bin/usage-paced-runner.sh` enforces by literally repeating a
weight-N participant N times in its round-robin rotation pool — a
weight-3 participant gets 3 turns for every 1 turn a weight-1
participant gets. Ties still resolve by plain rotation order.

**This is a mechanical enforcement point only.** Scheduler's job stops at
"run the number in this field this many times more often" — it has no
opinion on what the number should be. That judgment belongs to
realisateur, which has the thing scheduler deliberately doesn't: a
cross-project view of which ideas are converging on something real (more
turns, more benefit from steady iteration) versus which are still
speculative/likely to morph before anything built on them would survive
("vision debt" — pace slower, avoid sinking dev cycles into something
that gets discarded once the idea itself changes shape).

Realisateur is expected to edit this field directly as part of its own
periodic pass, the same way it already edits `schedule/<project>.conf`
files when registering a new project. No new mechanism is needed beyond
this file already being a plain, human/agent-editable conf scheduler
re-reads on every dispatch tick — the same "edit the conf, sync/apply"
loop as any other schedule change (this field doesn't need a
`sync-crontab.sh` step; `usage-paced-runner.sh` reads `_paced.conf`
directly on every tick, no crontab regeneration involved).

This is one piece of a larger scheduler/realisateur division of labor
being worked out 2026-07-22: scheduler stays a pure mechanism (timing,
pacing, resource gating); realisateur owns interpreting vision (feature
requests, cross-project synchronicities, idea stability) and expresses
that interpretation through mechanical knobs like this one rather than
scheduler ever needing to understand *why*.
