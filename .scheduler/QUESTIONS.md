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

- **Should lib/sweep-loop-common.sh wrap its ~10 notify-send calls in timeout, and why did the unguarded one NOT hang? Found 2026-07-28 while extracting lib/deadman-switch.sh. THE HANG IS REAL: the first attempt to source the new switch into aedile wrapper hung indefinitely (rc=124 under a 60s timeout). Cause: that wrapper exports DBUS_SESSION_BUS_ADDRESS at svc-vaporwave own /run/user/1001/bus, where the socket exists but nothing listens, so notify-send blocks forever. Reproduced directly: sudo -u svc-vaporwave with that env, timeout 8 notify-send test hello returns rc=124. The idiom used everywhere here, notify-send ... 2>/dev/null || true, guards against FAILING and not against NEVER RETURNING, and those are different failure modes. Fixed in the new lib with timeout 5. WHAT I CANNOT EXPLAIN, and did not paper over: sweep-loop-common.sh exports dbus identically at lines 176-177 and calls notify-send unguarded in about ten places, including the dead-man switch trip at line ~283. vkv-inventory sources this engine and runs under the SAME svc-vaporwave account, and its switch tripped on 2026-07-27T20:51. Its 2026-07-28 04:00 run should therefore have hit that exact unguarded call -- and it did not hang: sweep.log shows the complete ===-delimited expiry record written at 04:00:01 with a 0s duration. So identical code, identical account, identical dbus export, one hangs interactively and one does not under cron. Plausible differences not yet tested: cron env versus sudo env, presence of a controlling TTY, whether the bus socket had a listener at 04:00 versus at 11:40. THE ASK: either wrap them (cheap, ~10 one-word edits, no behaviour change when notify-send works) or establish why the cron path is immune and write that down, because right now the ecosystem most-used unattended engine contains a call that is known to block forever under conditions we cannot yet distinguish from its normal ones. Do NOT close this by observing that it has not hung in practice -- that is the argument that a silent failure is fine because nobody noticed. Filed rather than fixed because this is engine code with every project downstream of it, and the safe half was done in the new file.**  `q-756f82` 2026-07-28, via unattended run

- **Under the three-printable-views milestone, what happens to the EDITOR-OPENING verbs -p/-f/-q/-b? The bar names three stable PRINTABLE views, and those four print nothing -- they open a file in $EDITOR. Three readings, all defensible: (a) RETIRE -p specifically, since the milestone spec already says 'scheduler <project>' does reorder/reweight-from-there, which is exactly what -p is for -- tweaks made to it now are throwaway and the ACCRETION FREEZE arguably already covered them; (b) EXEMPT editor-openers as a class -- the fold is about printing surfaces, so -p/-f/-q/-b survive alongside the three views; (c) KEEP -p but promote it into the deploy-gated writer -- the one sanctioned way to edit _paced.conf (edit, validate, commit, deploy, refuse-if-dirty), which would close the exact live-edit risk that is the hard sequencing gate on axis-1's scheduler-run convergence. Raised 2026-07-28 by Zach during realisateur /ideate ('we just made some tweaks to scheduler -p but maybe that was slated for deletion anyway') -- he stepped away before answering, so it is filed rather than assumed. (c) is the only one that does work the roadmap already needs.**  `q-13a017` 2026-07-28, via unattended run

- **Does step 2's `scheduler resolve <project> <id>` get an exemption from the ACCRETION FREEZE, or does it wait for the front-door redesign?**  `q-f75d57` 2026-07-28, via /nightly-batch paced cycle 2026-07-28

  Two rules now point opposite ways and this cycle is not the one to
  break the tie. `q-741cda` came back ANSWERED by bibliothecaire the same
  day, and its answer is explicit: `scheduler resolve <project> <id>`
  should write a drop directory into bibliothecaire's repo and commit it.
  That unblocks step 2 of the readability chain — **and it is a NEW
  VERB**, which the Stability milestone's ACCRETION FREEZE says nobody
  adds before the front-door redesign lands ("new needs go into the
  spec"). Building it anyway would be "layer not retired" in the act:
  growing the surface the milestone exists to shrink.
  Three readings, and picking one is a judgment call, not a fact:
  (a) exempt it — the freeze is about the three human-facing VIEWS, and
  `resolve` is a mutation verb like the existing `ask`/`-i`, so it is
  in-scope now; (b) hold it — put it in the redesign spec as a footer
  one-liner of the `<project>` detail view and build it there; (c) build
  the mechanism WITHOUT a verb — have `sweep`/`ask` do the drop, so no
  new front-door entry appears.
  Also worth stating plainly: step 2 writes into ANOTHER repo, so an
  unattended paced cycle cannot deliver it under this job's hard rules
  regardless of which reading wins. Whoever picks it up needs
  `check-project-busy bibliothecaire` and a non-worktree session.

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
