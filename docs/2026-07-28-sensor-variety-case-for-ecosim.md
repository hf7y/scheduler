# A live case for the sensor-variety thesis, produced accidentally tonight

*Filed 2026-07-28 ~23:00 by realisateur `/ideate` (Zach-directed dexter-migration
session, running from the scheduler repo). Dropped as a new file at a new path
rather than into `.scheduler/FOCUS.md` or `QUESTIONS.md`, because
`check-project-busy ecosim` reported `BUSY: interactive session (pid 2562484,
since 2026-07-28T22:53:14-05:00)` — your own session, opened to take the
migration here. New path = no writer collision by construction.*

---

## Why this is being sent to ecosim rather than filed as a scheduler bug

`THESIS.md` claims, and I am quoting it because the case below is an almost
uncomfortably exact instance:

> A regulator cannot respond differently to two world-states that its sensor
> maps onto the same symbol. **Sensor variety upper-bounds effector variety.**

> If sensors' blind spots are **correlated**, adding sensors adds no variety.
> Reconciling *N* co-blind sensors yields exactly the variety of one. The only
> remedy that adds variety is adding an **output symbol**.

Tonight produced two independent confirmations, one of them self-inflicted in
the most literal way the thesis could ask for. Both are fresh, dated, and
reproducible — this is empirical material, not another doctrine entry.

---

## Case 1 — A sensor with a one-symbol alphabet (self-inflicted, ~22:45)

The dexter migration needs a readiness gate: for each registered project, can
the executing host actually reach its `REPO_URL`? I wrote the obvious probe and
ran it on dexter across all 19 projects:

```sh
if out=$(git ls-remote --heads "$u" 2>&1 | head -1); then
    echo "$p READY"
else
    echo "$p BLOCKED"
fi
```

It reported **all 19 READY.**

The `| head -1` means `$?` is *head's* exit status, which is 0 essentially
always. The sensor's output alphabet is `{READY}`. It has no symbol for
BLOCKED — not "it computes BLOCKED incorrectly", it **cannot emit BLOCKED at
all**. The two world-states "remote reachable" and "remote refuses on publickey"
map onto the identical symbol, so no downstream regulator, however capable,
could have responded differently to them.

The true answer, once the pipe was removed:

```
READY:   chezz, wtul                                    (2 of 19)
BLOCKED: 15 × git@github.com: Permission denied (publickey)
         home-assistant  ssh: Could not resolve hostname github-ha-deploy
         gardien         /home/zach/git-remotes/gardien.git does not exist here
```

**17 of 19 wrong, in the safe-looking direction.** Had that gate been trusted,
it would have greenlit 17 migrations that each die at first clone.

What makes this thesis-relevant rather than merely embarrassing: I caught it
*not* by testing the sensor, but because I knew one answer a priori — `gardien`'s
remote is a filesystem path on mandark and therefore cannot be reachable from
dexter. The correction came from **out-of-band knowledge of a specific expected
BLOCKED**, not from any property of the sensor or its output. A sensor that can
only say OK is indistinguishable from a healthy system precisely when you most
need to tell them apart, and nothing internal to the reading distinguishes them.

The practical rule this suggests, if the thesis wants one: **every gate needs a
negative test — a known-bad input that must produce the alarm symbol.** A gate
validated only against inputs that should pass has never demonstrated it owns
more than one symbol. I would guess most gates in this ecosystem have never had
one written.

## Case 2 — Four co-blind sensors, reconciled, yielding the variety of one

This is the stronger case, because nobody wrote it wrong. Every component worked
as designed.

**Timeline, all times 2026-07-28, all re-probed this session:**

- `22:01:06` — commit `3a45bf3` "REPO_URL: point all 15 projects to GitHub"
  repoints 15 projects from assorted remotes to plain `git@github.com:hf7y/*.git`.
  Authored on mandark. Correct-looking. Nothing fails.
- `22:25` — `scheduler` status runs. Then `ecosystem-survey`, `milestone-audit`,
  `steward-survey`, `hygiene-lint` — four independent surveys, the full
  proprioceptive apparatus. **All four report a healthy ecosystem.**
  `steward-survey` even prints `10 live / 9 dark` with per-project weights and
  stranded-backlog counts, i.e. it makes confident positive claims about exactly
  the projects that are broken.
- `22:45–22:52` — `git ls-remote` against each `REPO_URL`, run **from each host**.
  Neither dexter **nor mandark** can reach any of those 15 remotes. Neither host
  has a generic GitHub identity; both have only a handful of per-repo aliases.

So: **15 of 19 projects have been unable to clone their own source since 22:01,
and every sensor in the ecosystem reported healthy for the 50 minutes that
followed.**

The only reason nothing has *failed* yet is unrelated to any regulator noticing:
`usage-gate.sh` has returned `HOLD` (on-pace, 26–27% of the 7d window) on every
5-minute tick since 22:01, so no project has dispatched. The breakage is armed
and has not fired. The first `GO` fires it 15 times.

**Why this is the thesis's exact claim and not merely a missing check:** the four
surveys are genuinely independent — different code, different authors, different
questions, different output formats. Adding a fifth of the same kind would have
added nothing, because they share one blind spot: *every one of them reads
configuration and repository state on the host it runs on, and none of them ever
asks whether the declared remote answers from the host that would execute the
job.* Their blind spots are perfectly correlated. Reconciling all four yields the
variety of one. That is the prediction, stated in advance in `THESIS.md`, and it
held.

**The missing output symbol, named concretely.** `steward-survey`'s alphabet is
roughly `{LIVE, DARK, NOT PROBEABLE}` — where `DARK` means `enabled=0` (a stated
human decision) and `NOT PROBEABLE` means the local repo path could not be read.
There is no symbol for:

> **UNREACHABLE — registered, enabled, local checkout fine, and the declared
> `REPO_URL` does not answer from the host that would run it.**

That state is not rare or exotic: it is the *default* state of 15 projects right
now. It has no symbol, so it renders as `LIVE`, which is the same symbol as a
perfectly healthy project. Per the thesis, no amount of effector capability
recovers this — the fix is not a better runner or a smarter gate, it is one more
symbol at the sensor.

## A third instance already filed, same shape, for corroboration

`scheduler`'s own `FOCUS.md` (entry dated 2026-07-28 14:13) independently
describes the same defect in a different organ: a project that moves to dexter
goes dark in mandark's `scheduler status`, which keeps printing the last local
run record *as if current*. Live witness in that entry: `scheduler status crt`
on mandark reports a `done` timestamp four days stale, because crt moved hosts.
Nobody noticed for four days.

Same structure: the sensor maps "ran successfully four days ago on a host that
no longer runs this" and "running successfully now" onto one symbol. That
entry's own recommendation — print *"runs on dexter — last-run state not visible
from here"* instead of a stale record — is, in this thesis's vocabulary,
**precisely the addition of an output symbol**, and it was arrived at
independently without the framework. That's mild evidence the framework is
carving at a real joint rather than describing one incident.

---

## What this offers ecosim, concretely

1. **A dated, reproducible natural experiment with a pre-registered prediction.**
   `THESIS.md` predicts co-blind sensors add no variety. Four surveys, one
   correlated blind spot, 50 minutes of confident false healthy. Both probes are
   one-liners and rerunnable; the broken state is (at time of writing) still live
   and can be observed rather than reconstructed.
2. **A falsifiable design rule** worth simulating rather than asserting: does
   requiring every gate to carry a negative test measurably change time-to-detect
   in the sim? Case 1 says a gate with one symbol survives review indefinitely,
   because nothing about its output looks wrong.
3. **A sharper question than "add a check".** The tempting fix is a fifth survey
   that probes remotes. The thesis says that is the wrong move if it shares the
   blind spot, and the right move is enlarging an existing sensor's alphabet.
   Which is correct here is genuinely open, and is exactly the kind of thing the
   simulator could arbitrate: model *N* co-blind sensors versus *N-1* sensors and
   one added symbol, and see whether detection latency actually differs.
4. **A live migration to instrument.** The dexter migration (design filed tonight
   in scheduler `.scheduler/FOCUS.md`, commit `01e1bee`) moves ~10 heterogeneous
   projects whose readiness states differ. Zach's stated purpose for it is data
   for "a more intelligent scheduler philosophy that's not simply about fair round
   robin turns." The units differ in *readiness*, and round-robin gives a blocked
   unit the same turn as a ready one — burning a gate probe and a failing clone
   each lap. Recording per-unit state transitions (blocked → ready → moved →
   verified), with the block reason and wall-clock in each state, is a dataset
   that cannot be reconstructed after the fact. It has to be instrumented before
   the migration runs, and the migration has not started.

## The honest caveat

Case 2 is one incident, 50 minutes old, and the "four independent sensors" claim
deserves adversarial checking rather than acceptance — it is possible one of the
four *would* have caught it on a later code path I did not exercise, and I did
not read all four implementations to rule that out. I probed their **outputs**,
not their source. Treat the correlated-blind-spot claim as strongly suggested and
not yet established; the honest test is to read each survey and confirm none has
a remote-reachability path at all.

Case 1 needs no such caveat. That one is just true, and it is mine.

---

**Reader: this is inbox material for a human or a `/ideate` pass, not a task for
ecosim's nightly to execute.** Nothing here asks ecosim to change scheduler. The
armed outage is filed separately where it belongs — scheduler's `BLOCKERS.md`
and its `FOCUS.md` backlog — and is Zach's call tonight, not ecosim's.
