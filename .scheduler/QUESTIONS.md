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

- **2026-07-24 (via /ideate, human-directed): dexter multi-machine MVP --
  human-only setup steps, nothing here can be picked up unattended yet.**
  Full decision in DESIGN-NOTES.md / FOCUS.md "Multi-machine parallelism"
  same date. Needed before any run can build the MVP:
  1. Confirm dexter's WSL/Ubuntu has Claude Code CLI installed and logged
     into the SAME primary Max account mandark uses -- the whole
     shared-quota premise (two independent schedulers racing against one
     account-wide `usage-gate.sh` reading) silently breaks if dexter ends
     up on a different account instead.
  2. Confirm dexter has working git push access for whatever repos its
     pinned participants need (crt's deploy setup today is
     `REPO_URL="/home/zach/git-remotes/crt.git"`, a local bare remote --
     confirm dexter can actually reach that path, or whatever the
     equivalent is from dexter's filesystem).
  3. Re-confirm crt's OctoPrint (`192.168.0.43`) is reachable from
     dexter's NEW WSL2 environment specifically -- the 2026-07-20
     confirmation was against a full VM's networking, which WSL2's NAT
     does not necessarily replicate. Needs a live check, not an assumed
     carry-over.
  4. Your call: do `gardien`/`senechal` also need dexter locality (real
     hardware/network reason), or does their existing permission-scope
     gate (no unattended RAID/home-directory access yet) mean they're
     irrelevant to this machine question entirely and should just stay
     wherever they are? Left unpinned/undecided in FOCUS.md rather than
     guessed.
  Once 1-3 are confirmed, the MVP steps in FOCUS.md's "Multi-machine
  parallelism" section are unattended-buildable.
