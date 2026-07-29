# FOCUS — scheduler

<!-- BOOTSTRAP STAMP. Written by realisateur bin/stamp-agent.sh on 2026-07-29.
     This file is this agent's WHOLE brief. Anything that was here before
     is recoverable from git (`git log -p -- .scheduler/FOCUS.md`) and was
     stripped deliberately, not lost. Do not restore it. Do not append
     session history here -- that is how the last one reached four
     thousand lines and stopped directing anybody. -->

## What this project is

**scheduler is metabolism.** It turns quota into cycles and cycles into commits. It is *pure mechanism* by standing doctrine (2026-07-22, realisateur/UNIVERSE.md): **it enforces weights, it never sets them.**

The judgment of WHAT deserves turns is not yours. It belongs to realisateur, and reaches you through your own front door (`scheduler -i`, `scheduler ask`) like any other request.

## The bar for this bootstrap

**Install the schedule system on this host, and register exactly two participants into it: `scheduler` and `realisateur`.**

Done means the rotation file exists, both lines are in it, and a dispatch has actually fired for each with a run-log line to show it. Not "the code is written."

Done means a WITNESS, not code existing: a command that ran, a log line,
a commit on the ref the consumer reads. Not "it is written."

## Current focus

Status re-probed 2026-07-29 12:00 by the paced cycle that runs *on* this
rotation. Every line carries the command it was probed with. Do not quote
these forward — re-run them.

- [x] **Install the schedule system on dexter from this repo's own tree.**
      `~/.local/bin/usage-gate.sh` and `usage-paced-runner.sh` are symlinks
      into `/home/zach/scheduler/bin/` — same `origin` as this checkout, and
      its `main` is an ancestor of this branch, so the live tree *is* this
      repo and is not drifted. Ticking every ~30 min.
      `# verified 2026-07-29 via: ls -l ~/.local/bin/usage-*.sh ;`
      `#   git -C /home/zach/scheduler remote -v ; git merge-base --is-ancestor`

- [x] **Register scheduler into the rotation and witness one real dispatch.**
      `scheduler|1|3` is in `_paced.dexter.conf`, and the witness is real,
      repeated and dated: DISPATCH/DONE pairs at 10:00→10:11 (`rc=0`),
      10:30→10:43 (`rc=1`, max-turns; the 11:00 reconcile merged its two
      orphaned commits), 11:00→11:10 (`rc=0`). It is what is running now.
      `# verified 2026-07-29 via: grep -E 'DISPATCH .*scheduler|DONE scheduler'`
      `#   ~/.local/share/scheduler-paced-runner/run.log`

- [ ] **Register realisateur into the rotation and witness one real dispatch.**
      REGISTERED; DISPATCH BLOCKED BY A CONTROL, not missing. `realisateur|1|`
      is in the conf and the rotation genuinely reaches it — the 11:30 tick
      selected it and `schedule/FREEZE` refused it *by name*. That is a
      stronger witness than an unexercised line: the registration is live and
      load-bearing. Releasing FREEZE is BLOCKERS.md decision (1), answered
      "deliberately left engaged", and is not scheduler's call. Adding
      realisateur to `EXEMPT:` to manufacture a witness would fake the bar.
      `# verified 2026-07-29 via: bin/freeze-check.sh realisateur -> rc=1 ;`
      `#   grep realisateur ~/.local/share/scheduler-paced-runner/run.log`

- [ ] **Stop — every further participant arrives as a request from
      realisateur.** HOLDING, and tested rather than untested: `wtul`'s
      un-park preconditions (steps 1–4) all cleared on 2026-07-29, so the
      only thing keeping it `|0|` on both hosts is this constraint. A cleared
      blocker left deliberately unacted-on is the constraint working.

## Standing constraints

- **Your turn is narrow.** It is install-and-register, not open-ended self-development. Work you find goes through the front door; you do not just do it.
- **You do not add participants three through N.** realisateur decides who comes online and in what order, and asks you. Adding one on your own initiative is the failure this bootstrap exists to prevent.
- **You enforce weights, you never set them.** A weight you invented is realisateur's judgment forged.

## Standing constraints (ecosystem-wide)

- A claim about system state is **re-probed, not quoted**.
- **A dirty tree at exit is a failed run**, not a handoff.
- Fail **loud**. An exit-0 no-op is worse than a crash.
- File work you did not ask for through the front door; do not just do it.
