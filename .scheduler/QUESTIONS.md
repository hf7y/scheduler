# Questions for the user

Running log for this directory itself (the scheduler design/tooling, not
any one project's batch job). This project isn't itself under an
automated nightly/batch job -- it's maintained by hand -- so entries here
come from whoever's working on it directly, human or agent, whenever
something bigger than a routine edit comes up. Clear an entry by deleting
its line once you've actually read and dealt with it.

- **2026-07-24 (via /ideate): verify svc-vaporwave cron credential
  refresh.** Under the new account model (primary = Max, always logged
  in; svc-vaporwave = nonprofit only, for its batch jobs + nonprofit
  interactive), primary's CLI creds stay fresh so personal jobs stop
  hitting "Not logged in." Confirm the same holds for svc-vaporwave:
  does your nonprofit *interactive* use actually refresh the SAME creds
  its cron jobs (aedile, vkv-inventory) read, or can that account still
  lapse mid-week? If it can lapse, that account needs its own refresh
  ritual. See DESIGN-NOTES.md 2026-07-24 entry.

  > **Answer (2026-07-25):** Not critical if it lapses, but make the
  > failure LOUD instead of a silent no-op -- same principle the rest of
  > this file already applies (stale `.active` markers, unverified
  > migration destinations, push-reason surfacing). Concretely: whatever
  > checks auth for svc-vaporwave's cron jobs (aedile, vkv-inventory)
  > should detect "Not logged in" and escalate the same way other hard
  > failures here do -- CRITICAL log line + `notify-send -u critical` /
  > a flagged line in that project's report -- instead of the job just
  > quietly not running. Small paced-cycle item, not urgent.

- **2026-07-24 (via /nightly-batch, paced cycle): gardien/senechal's
  `AUTONOMY_TIER` left UNSET, real judgment call not guessed.** Declaring
  `AUTONOMY_TIER` per project (FOCUS.md axis 1.5) for 12 of 14 registered
  projects this cycle, using already-decided evidence (the FOCUS.md
  "Target UX" mockup, or a project's own conf/FOCUS.md push-policy
  language). gardien and senechal have neither: they're on the
  self-spawned/local-bare-remote precedent (which elsewhere maps to
  `high`), but their own `.claude/FOCUS.md`/conf comments talk only about
  a *scope* gate (no unattended run may touch the real RAID mount / real
  home directory yet) -- silent on push/merge autonomy specifically, and
  that scope gate is the separate "irreversibility" axis the Vision
  section says sits ABOVE tier, not a stand-in for it. Rather than assume
  `high` from the bare-remote precedent alone, left both unset per the
  instruction ("if a project's actual policy is unclear or contested,
  leave AUTONOMY_TIER unset and flag it... rather than guessing"). Your
  call: are gardien/senechal `high` (bare-remote containment already
  covers it) or does the physical-effect nature of their eventual real
  work (RAID writes, real home-directory scanning) argue for `medium`
  instead, independent of the remote-credential question? Once answered,
  the field can be added to `schedule/gardien.conf`/`schedule/senechal.conf`
  in a follow-up cycle.

  > **Answer (2026-07-25):** `high` for both, but tier alone doesn't
  > cover it -- apply the existing universal irreversibility gate
  > (Vision section: "one rule sits ABOVE the tier system... always
  > needs explicit human sign-off, no matter the tier") to each
  > project's specific write surface, rather than inventing a new
  > guardrails concept:
  > - **gardien**: `high`, with RAID writes treated as WORM-shaped --
  >   copies/additions are revertible (nothing destroyed, run
  >   autonomously) but deletion and dedup destroy information, so they
  >   count as "genuinely irreversible actions" under the gate that
  >   already exists and always need human sign-off regardless of tier.
  >   Not a new tier value -- write the concrete op list (delete/dedup =
  >   gated, copy/move-with-original-retained = autonomous) into
  >   gardien's own FOCUS.md as its specific instance of the gate.
  > - **scheduler**: `high` extends to pruning/injecting known project
  >   files across dexter/mandark, but flag this explicitly as an
  >   INTERIM policy tied to the no-local-checkout redesign (roadmap
  >   item 4/5) still being unfinished -- revisit once that lands, don't
  >   let it quietly become permanent scope.
  > - **senechal**: don't assert `high` from day one -- condition it.
  >   `medium` until the config files it will own actually have
  >   verified version control/redundancy in place, then promote to
  >   `high` once that's a checkable fact, not a target date.
  >
  > Clear enough to act on, no further ideation needed. Translate into
  > `schedule/gardien.conf` / `schedule/senechal.conf` `AUTONOMY_TIER`
  > fields + each project's own FOCUS.md irreversibility-gate list, next
  > paced cycle.

- **2026-07-24 (RESOLVED BY THE 2026-07-24 dexter self-build -- items 1
  and 3 of the old MVP-setup entry).** Item 1 (Claude Code installed on
  dexter, logged into the same primary Max account): confirmed --
  `usage-gate.sh` runs on dexter and reads the shared account's live 5h/7d
  windows, and push access to `origin` works. Item 3 (crt's OctoPrint
  reachable from WSL2 specifically): confirmed -- `192.168.0.43` answers
  with 0% ICMP loss, TCP 80 open, and an OctoPrint-identifying HTTP 302
  (`x-clacks-overhead` header), so it is the real service, not just an
  open port. Items 2 and 4 are still open and restated below.

- **2026-07-24 (via the dexter self-build): how should dexter get crt's
  source? This is the one thing blocking crt from actually running on
  dexter, and it has a security dimension I would not decide alone.**
  crt's OctoPrint pin is confirmed and `crt` is pinned in
  `schedule/_paced.dexter.conf` -- but with `enabled=0`, because
  `schedule/crt.conf` sets `REPO_URL="/home/zach/git-remotes/crt.git"`, a
  bare repo on *mandark's* filesystem. dexter cannot reach it (verified by
  running it: `fatal: repository ... does not exist`), and crt has no
  mirror -- crt.conf notes a deploy key exists "if a private GitHub mirror
  is wanted later", never set up. **That remote is local on purpose**:
  crt.conf's own comment says it is a local bare repo specifically so the
  VM password in `HANDOFF.md` never leaves the machine.

  **NARROWED, same evening, by realisateur's `/ideate` on mandark
  (`28a1617`, landed while this session was running):** "non-GitHub
  projects reach dexter via local bare remote over LAN/SSH" is now
  DECIDED policy. That rules out a GitHub mirror for crt (which would have
  been the easy option, and is the one the unused `crt_deploy_key` was
  made for) and settles the *transport*. What remains is a concrete
  human/setup step, not a design choice:
  (a) **expose mandark's `/home/zach/git-remotes/crt.git` over SSH** and
      point crt's `REPO_URL` at `ssh://mandark/...` -- the decided
      pattern. Note the tradeoff it carries: dexter's unattended crt job
      then depends on mandark being up, which softens "two independent
      schedulers" for that one project;
  (b) **move crt's bare repo to dexter** and have mandark reach it over
      the same LAN/SSH pattern -- same transport, opposite direction.
      Worth considering because crt is now hardware-pinned to dexter, so
      dexter is arguably its natural home; this is the variant that keeps
      dexter independent rather than newly dependent on mandark;
  (c) leave it as-is for now -- dexter simply has no runnable participant
      yet. This is the CURRENT state, so nothing is broken while it waits.

  **One factual correction to `28a1617` while you're here:** that entry
  says "no non-GitHub project is pinned to dexter today (only crt is, and
  it already uses this exact pattern)". crt uses a local bare remote, but
  **not over LAN/SSH** -- `REPO_URL` is a plain filesystem path that only
  resolves on mandark. Verified from dexter by running it:
  `fatal: repository '/home/zach/git-remotes/crt.git' does not exist`. So
  the policy is settled but its first real instance is unbuilt, and crt is
  that instance rather than an example of it already working.

- **2026-07-24 (via the dexter self-build): does mandark pull
  `origin/main` automatically? Affects whether this session's fixes have
  actually reached it.** This matters more than it sounds. mandark
  *executes* `bin/usage-paced-runner.sh` and `lib/sweep-loop-common.sh`
  out of a checkout of this history on a `*/5` tick, so this repo is
  shared **running code**, not just shared config -- a commit here can
  change the other machine's live behavior with no human in the loop.
  Nothing in this repo appears to pull `origin/main` on mandark (the only
  `git fetch` found is inside a job's own disposable clone). If mandark
  does not pull: (a) the `sweep-loop-common.sh` clone/`cd` hardening
  committed today -- which stops a failed clone from running `claude` with
  write tools in cron's working directory and still exiting 0 -- is NOT
  live there yet, and (b) the prepared crt-drop
  (`dexter/drop-crt-from-mandark-paced`) will have no effect there when
  it lands. Everything built today was written to be a no-op on mandark
  precisely because this was unknown, so nothing is broken either way --
  but if the answer is "no", someone has to pull on mandark by hand, and
  the two-host design probably needs a deliberate answer for how code
  reaches the other box at all.

- **2026-07-24 (via the dexter self-build): should dexter self-develop
  `scheduler` too?** `bin/scheduler-dev-cycle.sh` no longer hardcodes
  mandark's repo path, so dexter *could* run it -- but it is deliberately
  absent from `_paced.dexter.conf`. Two hosts committing to one scheduler
  git history, each auto-merging to its own local `main`, is a stronger
  version of the divergence that bit this repo earlier the same day (two
  worktrees on a *single* host drifting far enough apart that a paced cycle
  refused to reconcile them and escalated it here).

  That entry was cleared by `558c1c1` while this session ran -- **but note
  how it was resolved: a fast-forward.** That worked only because one side
  had not independently advanced. With two hosts pushing to one `origin`,
  that is precisely the condition that stops holding, so the resolution
  does not generalize to the two-machine case; if anything it shows what
  the cheap fix depends on. This session already hit the two-host version
  in miniature -- mandark pushed 5 commits mid-session and this work had
  to be rebased onto them (cleanly, this time).

  Your call. Worth noting that a second self-developing host is the one
  addition that would make this repo's own history the contended resource,
  as opposed to today's situation where the two hosts contend only over
  config files that the `_paced.<host>.conf` split now keeps separate.

- **2026-07-24 (restated, still open -- was item 4 of the MVP-setup
  entry): do `gardien`/`senechal` need dexter locality?** Or does their
  existing permission-scope gate (no unattended RAID/home-directory access
  yet) mean they are irrelevant to the machine question entirely and
  should stay where they are? Left unpinned rather than guessed. Note the
  pinning policy now has a written home -- `_paced.dexter.conf`'s header:
  only hardware/network-evidenced projects belong on dexter -- so the
  question is specifically whether either has such evidence, not whether
  it would balance load.

  > **Answer (2026-07-25):** No pinning -- both stay parallel stewards
  > of their own systems, not much cross-system work implied by
  > co-locating them. If dexter's WSL2 setup can host a shared
  > Windows/Linux dev stream elegantly (similar in spirit to how it
  > already reaches crt's OctoPrint), that's worth exploring
  > opportunistically, but it's not a requirement driving this decision.
  > Leave unpinned; revisit only if real hardware/network evidence for
  > either shows up, per `_paced.dexter.conf`'s stated pinning bar.

- **2026-07-24 (same session, follow-up): RESOLVED -- "does mandark pull
  origin/main automatically?" (the item above this one).** Answer was no,
  confirmed live, then fixed the same session: `usage-paced-runner.sh` now
  pulls (fetch + `--ff-only`) at the start of every tick, inside the flock,
  fail-loud-not-block on a dirty tree/failed fetch/genuine divergence. Full
  writeup: DESIGN-NOTES.md 2026-07-24 "auto-pull wired into
  usage-paced-runner.sh". Symmetric across both hosts (same script), so
  this closes the gap on dexter too. The item above is left as-is rather
  than edited, per this file's own convention of not silently rewriting
  history.

- **2026-07-24 (same session, follow-up): IN PROGRESS -- "how does dexter
  reach crt's bare repo?" (item #1 above).** Answer: option (b), dexter
  clones mandark over SSH; (c) "dexter becomes authoritative instead"
  explicitly parked for later, human-directed. Mandark side is done this
  session (openssh-server installed+enabled, a restricted git-shell-only
  deploy key for dexter, `crt.conf`'s `REPO_URL` updated, dexter's prepared
  crt-drop branch merged). Full writeup: DESIGN-NOTES.md 2026-07-24 "crt's
  bare-repo access."
  **Still open, needs a live session ON dexter:** add the `mandark-lan`
  SSH alias to dexter's own `~/.ssh/config`, verify with
  `git ls-remote ssh://mandark-lan/home/zach/git-remotes/crt.git`, then
  flip `crt` to `enabled=1` in `schedule/_paced.dexter.conf` (steps
  written into that file's crt comment directly). Until that happens crt
  runs on neither host -- an accepted, visible interim gap, not an
  oversight.

- **2026-07-24 (same session, follow-up): RESOLVED -- crt's bare-repo
  access (item #1 above).** Live-verified from dexter (`git ls-remote`
  succeeded, host key fingerprint cross-checked against mandark's real
  key), `crt` flipped to `enabled=1` in `schedule/_paced.dexter.conf`.
  crt now runs on dexter only. Full writeup: DESIGN-NOTES.md 2026-07-24
  "crt live-verified from dexter, enabled."

- **2026-07-24 (same session, follow-up): RESOLVED -- "should dexter
  self-develop scheduler too?" (item #3 above).** The blocker wasn't
  cross-host overlap, it was that `scheduler-dev-cycle.sh` merged into
  local `main` but deliberately never pushed (a once-a-day human-review
  design) -- staleness could occur with zero time overlap, purely from
  sequencing, and already had (see the same-day "main/paced-2026-07-24
  divergence" entry cleared earlier). Fixed durably, human-directed:
  every cycle now pushes `origin/main` immediately after merging, in the
  same cycle. Review is revert-based, not a pre-push gate -- restated
  everywhere this policy is written (FOCUS.md Push/Merge policy sections,
  `bin/scheduler-dev-cycle.sh`'s own header, DESIGN-NOTES.md 2026-07-24
  "push-on-cycle, not push-on-morning-review" for the full writeup).
  `scheduler` is now safe to add to a host's rotation on this specific
  concern; a cheap secondary safeguard (advisory lookahead to skip if
  another host has a dispatch due imminently) is still queued as a fast
  follow, not a blocker.

- **2026-07-25 (via /nightly-batch, paced cycle): does the axis-1
  `bin/scheduler-run` migration (FOCUS.md "Consolidation roadmap" item 1)
  need to change, given it's currently a no-op for every project it names?**
  MIGRATION.md's flip (drop `*_SCRIPT`, verify `sync-crontab.sh` preview,
  `--apply`) only affects entries in the *generated crontab* -- but
  `chezz`, `home-assistant`, and `wtul` are all now dispatched as **paced
  participants** instead, meaning `bin/usage-paced-runner.sh` execs the
  literal wrapper-path string straight out of `schedule/_paced*.conf`'s
  command column and never looks at `schedule/<project>.conf`'s
  `BATCH_SCRIPT`/runtime fields or the generated crontab at all (confirmed
  by reading `usage-paced-runner.sh`'s dispatch loop and by
  `sync-crontab.sh` preview's own "paced participant -- fixed cron
  suppressed" note for all three). `vkv-inventory` is disabled in
  `_paced.conf` for an unrelated reason (unverified svc-vaporwave
  migration). So dropping `BATCH_SCRIPT` for any of the four would edit a
  file nothing currently reads for dispatch purposes -- it would look
  "migrated" without moving anything. Two ways to actually finish axis-1
  for a paced participant, and I don't want to guess which you'd prefer:
  (a) change that project's line in `schedule/_paced*.conf` to invoke
  `bin/scheduler-run <project> nightly-batch` instead of the wrapper path
  directly -- the real switch, but a materially bigger/riskier edit than
  MIGRATION.md describes: two hosts (mandark/dexter) pull and act on
  `_paced*.conf` within one 5-minute tick, with no `--apply`-style human
  gate the crontab flip has, so a mistake here is live much faster; or
  (b) leave axis-1 explicitly scoped to *non-paced* projects only (rewrite
  the FOCUS.md item to say so) and treat "paced participant still calls
  its own wrapper" as an accepted, permanent shape rather than a debt to
  pay off, since the paced runner's dispatch contract (`name|enabled|cmd`)
  doesn't actually care whether `cmd` is a legacy wrapper or
  `scheduler-run` under the hood -- there may be no real value being left
  on the table by never doing (a). Full finding written up in FOCUS.md's
  "Consolidation roadmap" item 1, same date.
