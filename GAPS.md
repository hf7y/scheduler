# GAPS -- what this branch's verbs cannot yet do

Recorded 2026-07-30 during the bashify pass, one section per verb. These
are to be closed later; they are written down now so no utility here
ever pretends.

## dose: the cost baseline

No before-measurement exists for what the previous implementation cost
per call, so the saving from mechanising it is **unmeasured, not zero
and not assumed**. Closing this needs a real measurement, not an estimate.

## invoque: freeform instructions beyond the fixed report template

hf7y/scheduler#109 asked for a verb to "spawn an agent with a prompt
template and perhaps specific instructions". `invoque` covers the
template half -- the fixed status-report preload `scheduler status
--claude`/`--interactive` already builds, unchanged. Appending a
caller-supplied freeform instruction on top of that report is not yet
built; nothing in `bin/scheduler` supports it today, so extending
`invoque` to accept it is new work, not a wrap. Until it lands, a caller
who needs that gets it by hand, from inside the launched session.
