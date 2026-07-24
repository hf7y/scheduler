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

- **2026-07-24 (via /nightly-batch, paced cycle): local `main` and this
  worktree's `paced/2026-07-24` branch have genuinely diverged -- not
  discovered/fixed here, flagging for a human decision.** Both worktrees
  share one `.git` (`/home/zach/Documents/Project Archive/scheduler` on
  `main`, this dev worktree on `paced/2026-07-24`). `main` (already pushed
  to `origin/main`, confirmed via its local `origin/main` ref -- no
  network from this worktree to double check live) has 8 commits this
  branch doesn't (`8552051` token-usage.sh, `d05fcc8` glance/status ETA
  feature, plus several `/ideate` pass #3 and human-edit-via-`scheduler`
  commits). This branch has 6 commits `main` doesn't (`fae54c5` scheduler
  explain, `1300c82` stranded-unpushed surfacing, `690bd8b` migration-dest
  verification, `44a8c8e` stale `.active`-marker detection, `743859d`
  stability milestone doc, `51c90a8` notify-send guard). Merge-base is
  `b4b2e2d`. I deliberately did NOT merge/rebase either way this cycle --
  that's real judgment on the meta-tool that runs every job, not a routine
  edit, and outside this cycle's "commit only on `paced/2026-07-24`" rule.
  Left both branches exactly as found. Likely cause: this worktree's
  branch wasn't rebased/synced after an earlier cycle (or a different
  session) advanced `main` directly. Needs a human call on how to
  reconcile (rebase this branch onto `main`, merge `main` in, or merge
  this branch's commits into `main` and rebuild this worktree from there)
  before either side's unique work is lost to a careless merge later.
