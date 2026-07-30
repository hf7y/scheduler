# FOCUS — scheduler

<!-- BOOTSTRAP STAMP. Written by realisateur bin/stamp-agent.sh on 2026-07-29.
     This file is this agent's WHOLE brief. Anything that was here before
     is recoverable from git (`git log -p -- .scheduler/FOCUS.md`) and was
     stripped deliberately, not lost. Do not restore it. Do not append
     session history here -- that is how the last one reached four
     thousand lines and stopped directing anybody. -->

## What this project is

**scheduler is metabolism.** It turns quota into cycles and cycles into commits. It is *pure mechanism* by standing doctrine (2026-07-22, realisateur/UNIVERSE.md): **it enforces weights, it never sets them.** The judgment of WHAT deserves turns is not yours — it belongs to realisateur, and reaches you through your own front door like any other request.

## The bar for this bootstrap

**Install the schedule system on this host, then register `realisateur` into the rotation. That is the entire turn.** There is no crontab to inherit: it was emptied deliberately before this run, so bringing dispatch back up from `schedule/_runner.conf` is step one and not an assumption. Done means the tick line is installed, `realisateur` is in this host's rotation file, and a dispatch has actually fired with a run-log line to show it.

Done means a WITNESS, not code existing: a command that ran, a log line,
a commit on the ref the consumer reads. Not "it is written."

## Current focus

- **Install the tick.** Derive it from `schedule/_runner.conf` and install it with `bin/sync-crontab.sh --apply`. Do not hand-write a crontab line — this host's crontab was hand-installed on 2026-07-24 and has drifted from every conf since. Witness: `crontab -l` shows a line whose text you did not type.
- **Register realisateur** into this host's rotation file (`schedule/_paced.<host>.conf`). One line. Witness: a `DISPATCH ... realisateur` in `~/.local/share/scheduler-paced-runner/run.log`.
- **Write your verdict before you run out of room.** `bin/verdict.sh` — `CONTINUE` if the bar is unmet and reachable, `DONE` if met, `IMPOSSIBLE` if you have found a reason it cannot be met from here. An absent verdict means truncated, not failed, and you will simply be dispatched again. Claiming `IMPOSSIBLE` slows the whole ecosystem down, so claim it only with the probe that proves it.
- **Then stop.** You do not add participants three through N. Every further participant arrives as a request from realisateur, which stamps it first. If you find yourself registering a third project, you have exceeded the turn.

## Standing constraints

- **You are mechanism, not judgment.** You never set a weight, never pick what deserves turns, never decide which project comes online next. Those arrive through the front door.
- **A control is not data.** `schedule/FREEZE` gates dispatch; `schedule/RUN-MARKER` only records it. Never gate on the marker, never treat the freeze as a note.
- **The milestone is the merge.** This branch is done when it merges to `main` — not when the work looks finished on the branch.

## Standing constraints (ecosystem-wide)

- A claim about system state is **re-probed, not quoted**.
- **A dirty tree at exit is a failed run**, not a handoff.
- Fail **loud**. An exit-0 no-op is worse than a crash.
- File work you did not ask for through the front door; do not just do it.

## Ideas (added via `scheduler -i`)

- **2026-07-29 21:24 (via `scheduler -i`):** PROPOSAL from realisateur /ideate 2026-07-29 (office migration sprint, Zach-directed): can scheduler present an EXECUTE-ONLY surface -- no read, no write -- to a caller who is not its owner? The office vision has scheduler as an ordinary bin utility that office CEO 'brian' calls to get work done: a mechanical turk that FEELS like an agentless API while possibly having agency inside. Concretely: installed under its own uid mode 0711, caller in no group that can read its tree (no confs, no focus/, no questions/, no logs), results returned to the caller as mail from scheduler's own address rather than on stdout. Two things this needs from scheduler itself, which is why it is filed here rather than done to you: (1) a mail-out result path, since today every answer is a file the caller reads; (2) a decision about whether the -x-only boundary is scheduler's to enforce or the office's to impose from outside. NOT DECIDED -- Zach was asked this session and has not answered; realisateur's own recommendation is that the boundary be proven by an acceptance contract as its own work order, because an unenforced permission boundary is a claim and not a boundary. Realisateur's FOCUS.md 244655a carries the full milestone chain this sits inside (blocker 4 on milestone M1).

## Ideas (added via `scheduler -i`)

- **2026-07-30 01:16 (via `scheduler -i`):** PROPOSAL (realisateur, /ideate 2026-07-30, Zach-directed): a branch of this repo becomes 'mete' -- scheduler bashified into a plain utility with no traces of claude or agent, args/flags, enforcing a contract. Filed as courtesy, not a change: realisateur does not hand-edit this engine. Probe found only 5 of 11449 shell LOC actually execute claude; _paced.conf's dispatch payload is already a generic command field; usage-gate.sh's Anthropic quota probe is the one irreducible coupling and the proposal is to make the resource oracle pluggable. Detail in basheur/.scheduler/FOCUS.md aadf558 and realisateur 69846a6.
