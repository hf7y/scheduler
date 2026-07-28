# Questions for the user

Running log for this directory itself (the scheduler design/tooling, not
any one project's batch job). This project isn't itself under an
automated nightly/batch job -- it's maintained by hand -- so entries here
come from whoever's working on it directly, human or agent, whenever
something bigger than a routine edit comes up. Clear an entry by deleting
its line once you've actually read and dealt with it.

**Add entries with `scheduler ask <project> "<question>"` -- do not
hand-type them.** RETIRES the "Shape rule" paragraph that stood here for
one day (2026-07-27 to 2026-07-28): it asked writers to remember to put
the question first, and a convention nobody can enforce is a latent bug.
The id/date/provenance are now stamped by the generator and the question
comes first structurally, because that bold span is exactly what
`scheduler status` prints. `bin/questions-lint.sh` FLAGs hand-written
entries and unstamped machine-state claims in `scheduler sweep`.
Resolved entries get DELETED, not left inline.

## Open

- **Do svc-vaporwave's aedile/vkv-inventory wrappers source their own copy of lib/sweep-loop-common.sh, or a path into /home/zach?**  `q-ba2045` 2026-07-28, via /nightly-batch paced cycle 2026-07-26, re-filed by /ideate

  Second half, same step: aedile's wrapper is bespoke (opts out of the
  shared engine, calls `claude -p` directly) and needs the auth-failure
  branch added by hand. Loud "Not logged in" detection is built at source
  and verified against shims, but this account cannot read
  svc-vaporwave's home directory, so delivery can't be done or checked
  from here. For a headless account the LOG line is the loud channel --
  `notify-send` is a no-op there.

- **Does bibliothecaire want resolved QUESTIONS/BLOCKERS entries as files committed into its own repo, or as an ingest command it exports?**  `q-741cda` 2026-07-28, via /ideate 2026-07-28

  **ANSWERED by bibliothecaire's nightly batch, 2026-07-28** (commits
  `06a8422` and the two before it, on bibliothecaire `main`). Left inline
  rather than deleted because the answer is bibliothecaire's, not the
  user's, and clearing an entry here is a human's action.

  1. **Yes, they belong there** — not as a new scope, but as the third
     wing already decided 2026-07-27 in realisateur and parked pending "a
     concrete pain point." A 743-line `BLOCKERS.md` whose open items
     could not be found among 732 resolved ones is that pain point, so
     the park is lifted.
  2. **Files committed IN. Do not build an exported ingest command.**
     bibliothecaire's CLAUDE.md hard rule is that consumers never import
     code from it; an exported verb would make that repo a runtime
     dependency of all 18 registered projects, which is that rule's own
     failure mode at scale. A committed file needs no version, no PATH
     entry and no working install to succeed. So `scheduler resolve
     <project> <id>` should **write a directory and commit it.**
  3. **Drop format**, per `intake/README.md` in bibliothecaire:
     `intake/<producing-project>-<topic>-<YYYY-MM-DD>/` containing a
     required `README.md` (what it is, why it left, who to ask) plus the
     records. bibliothecaire's next run files it to
     `archive/<project>/<YYYY-MM-DD>-<topic>.md`, indexes it, and deletes
     the drop directory in the same commit.

  One boundary to know before wiring this up: archived records are
  explicitly **not sources**, are not under bibliothecaire's honesty
  policy, and can never be quoted or cited by a concept brief. They are
  kept, not curated.

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
