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
  VM password in `HANDOFF.md` never leaves the machine. So every option
  trades that property away or works around it, and picking one is your
  call, not a mechanical fix:
  (a) set up the private GitHub mirror the deploy key was made for --
      simplest, but crt's history (including whatever `HANDOFF.md` holds)
      then leaves the LAN, which is the exact thing the current setup
      avoids;
  (b) give dexter SSH access to mandark and point `REPO_URL` at
      `ssh://mandark/...` -- keeps everything on the LAN, but makes
      dexter's unattended jobs depend on mandark being up, which partly
      defeats "two independent schedulers";
  (c) host crt's bare repo on dexter instead and have mandark reach it --
      inverts (b), reasonable if crt is meant to be dexter's project now
      that it is hardware-pinned there;
  (d) leave crt on mandark for now, accept that dexter has no runnable
      participants yet, and let the host-scoped split sit unused until
      some other project earns a hardware pin.
  Until this is answered dexter's rotation is empty (logged explicitly
  each tick, not silent). Note (d) is the current state, so nothing breaks
  while it waits.

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
  git history, each auto-merging to its own local `main`, is the same
  divergence already open as a question above (from two worktrees on a
  *single* host, which a paced cycle refused to reconcile). Adding a second
  machine before that one is settled would multiply it rather than test it.
  Your call, and probably answer the two-worktree divergence question
  first -- it is the same question with fewer machines.

- **2026-07-24 (restated, still open -- was item 4 of the MVP-setup
  entry): do `gardien`/`senechal` need dexter locality?** Or does their
  existing permission-scope gate (no unattended RAID/home-directory access
  yet) mean they are irrelevant to the machine question entirely and
  should stay where they are? Left unpinned rather than guessed. Note the
  pinning policy now has a written home -- `_paced.dexter.conf`'s header:
  only hardware/network-evidenced projects belong on dexter -- so the
  question is specifically whether either has such evidence, not whether
  it would balance load.
