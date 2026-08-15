# FOCUS — retired 2026-08-15, migrated to GitHub issues

**The backlog now lives at https://github.com/hf7y/scheduler/issues.**
This file is a pointer, not a second source of truth. Do not add work
items here — file an issue.

Retired by [#66](https://github.com/hf7y/scheduler/issues/66) (2026-08-07);
the estate-wide sweep is
[hf7y/realisateur#230](https://github.com/hf7y/realisateur/issues/230).
Note that #66 §1 lists "a mostly static `FOCUS.md`" among what markdown
keeps — this file is that, reduced to its pointer.

## What this file was

A **bootstrap stamp**, written by `realisateur bin/stamp-agent.sh` on
2026-07-29. The predecessor had reached 4,455 lines and stopped directing
anybody; the stamp cut it to 43 and stated one bar:

> Install the schedule system on this host, then register `realisateur`
> into the rotation. That is the entire turn.

The host was **dexter**. That bootstrap is over: self-dev moved to
`monkey` on 2026-08-03 (`realisateur/MONKEY.md`, milestone met), mandark's
scheduler self-dev went dark (`58d6495`), and dexter dispatches nothing.
Nothing in the brief survives as work.

## Nothing was reaped from it, deliberately

Read end to end before retiring. It carried a project statement
("scheduler is metabolism… it enforces weights, it never sets them"), the
bootstrap bar above, and a short Current-focus list whose items — install
the tick from `schedule/_runner.conf`, register `realisateur` into
`schedule/_paced.<host>.conf` — are all about that dead host and its
hand-drifted crontab.

The one durable thing in it is doctrine, not a task, and it is already
recorded where doctrine lives (`realisateur/UNIVERSE.md`, 2026-07-22):
scheduler is pure mechanism; the judgment of *what* deserves turns belongs
to realisateur and arrives through the front door. #66 §3 is the current
form of that argument.

Full history — including the 4,455-line predecessor the stamp replaced —
is in git.
