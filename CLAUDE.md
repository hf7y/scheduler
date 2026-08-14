# CLAUDE.md

## Push permission (2026-07-22, human-directed)

Claude may push committed changes directly to `origin/main` without
asking each time, for ordinary work in this repo. Flag every such push in
the next report/summary (what was pushed, why, and how to revert it —
`git revert <sha>`). This does not license skipping review of what goes
into a commit in the first place, only the push step itself.



## Build discipline and ecosystem protocols

Run **`discipline`** before marking anything done. It prints the
build-discipline checklist and the ecosystem protocols — what to do when a
change reaches outside this repo (senechal, focus-commit, check-project-busy,
consulte). `discipline --checklist` and `discipline --protocols` print one
half each.

**If `discipline` is not on PATH, that is a finding — say so loudly. Do not
recite the checklist from memory and do not do the steps by hand.** A missing
guard is a finding, not an inconvenience.

The text lives in one place, realisateur's `BUILD-DISCIPLINE.md`, and is read
at the point of use. It is deliberately **not copied into this file**. Stamping
it into 17 repos is what produced eleven byte-identical corrupted copies, a
source 36 lines behind its own copies, and a drift detector reporting OK
throughout.
