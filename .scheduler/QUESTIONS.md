# Questions for the user

Running log for this directory itself (the scheduler design/tooling, not
any one project's batch job). This project isn't itself under an
automated nightly/batch job -- it's maintained by hand -- so entries here
come from whoever's working on it directly, human or agent, whenever
something bigger than a routine edit comes up. Clear an entry by deleting
its line once you've actually read and dealt with it.

**Shape rule (2026-07-27, `/ideate`, human-directed).** An entry here is
addressed to a HUMAN who has not read the code. Lead with the question
itself in the bold line -- not the provenance -- and keep the whole entry
short enough to answer without scrolling. Provenance (`(via
/nightly-batch, paced cycle)`), verification transcripts, commit SHAs and
the full reasoning belong in `DESIGN-NOTES.md`; link to it. The prior
convention grew 30-line agent-to-agent essays whose first line -- the
only part any summary view shows -- was almost always the date and the
source, so `scheduler status` rendered ten questions as ten
indistinguishable stubs. Answered entries get DELETED and recorded in the
consumed ledger at the bottom, not left inline: on 2026-07-27 five of
fifteen entries were resolved-in-place and still sat between the open
ones.

## Open

- **Do svc-vaporwave's aedile/vkv-inventory wrappers source their own copy of lib/sweep-loop-common.sh, or a path into /home/zach?**  `q-ba2045` 2026-07-28, via /nightly-batch paced cycle 2026-07-26, re-filed by /ideate

- **Does bibliothecaire want resolved QUESTIONS/BLOCKERS entries as files committed into its own repo, or as an ingest command it exports?**  `q-741cda` 2026-07-28, via /ideate 2026-07-28

## Consumed / resolved (one line each -- detail lives in DESIGN-NOTES.md)

- **2026-07-27** Installed `~/.local/bin` copies vs symlinks -> symlink
  all three (`/ideate`). Queued in FOCUS.md Backlog.
- **2026-07-27** `USAGE_CEILING` committed value -> 0.92 in
  `_usage.conf`, shared not per-host (`/ideate`). Dropping the ambient
  0.99 env override is still Zach's, outside this repo.
- **2026-07-27** `EXPIRY_DAYS` outage semantics -> keep wall-clock, make
  expired-without-ever-having-run a distinct louder state (`/ideate`).
- **2026-07-27** wtul-on-dexter deploy key / non-hardware-on-dexter test
  -> test RETIRED, pin-by-need stands, no GitHub step needed
  (`/ideate`). Unused dexter keypair to be cleaned up dexter-side.
- **2026-07-27** `.claude/commands/nightly-batch.md:68` date-only report
  filename -> FIXED this session (`%Y-%m-%d` -> `%Y-%m-%dT%H%M`); it
  needed an interactive session because unattended runs are hard-refused
  on `.claude/**` writes.
- **2026-07-27** axis-1 `bin/scheduler-run` migration for paced
  participants -> option (a), sequenced after the committed-conf gate.
- **2026-07-24** dexter reaching crt's bare repo -> option (b), SSH to
  mandark; live-verified, `crt` enabled=1 in `_paced.dexter.conf`.
- **2026-07-24** does mandark pull `origin/main`? -> it did not; fixed,
  the paced runner now fetches + `--ff-only` every tick inside the flock.
- **2026-07-24** should dexter self-develop `scheduler`? -> yes, safe
  once every cycle pushes `origin/main` immediately after merging;
  review is revert-based, not a pre-push gate.
- **2026-07-24** Claude Code on dexter / crt's OctoPrint reachable from
  WSL2 -> both confirmed live.
