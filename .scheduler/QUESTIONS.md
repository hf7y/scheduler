# Questions for the user

Running log for this directory itself (the scheduler design/tooling, not
any one project's batch job). This project isn't itself under an
automated nightly/batch job -- it's maintained by hand -- so entries here
come from whoever's working on it directly, human or agent, whenever
something bigger than a routine edit comes up. Clear an entry by deleting
its line once you've actually read and dealt with it.

- **2026-07-25 (dexter, verifying commit 0366936): wtul's dexter move
  needs a deploy key -- HUMAN GitHub-UI step, parked until then.** The
  named-exception test that moved `wtul` onto dexter's rotation was
  landed without the credential it needs. Verified from dexter by
  running it, not assumed:

  ```
  $ git ls-remote git@github-wtul-deploy:hf7y/wtul.git
  ssh: Could not resolve hostname github-wtul-deploy: Temporary failure
       in name resolution
  fatal: Could not read from remote repository.
  ```

  Name resolution, not auth: dexter's `~/.ssh/config` has only
  `github-scheduler-deploy` and `mandark-lan`, and no wtul key exists
  here. crt got its `dexter_mandark_deploy` key provisioned *before* its
  enabled=1 flip; wtul's move landed ahead of its credential instead, so
  the "live-verified from dexter itself" bar that `_paced.dexter.conf`'s
  own crt block sets as the pattern was never met for wtul.

  **Parked, not abandoned** (2026-07-25): `wtul|0|` in
  `_paced.dexter.conf`, restored to `wtul|1|2|` in `_paced.conf` in the
  same change, per the revert instructions both files already carried --
  so wtul keeps running on mandark instead of running nowhere and
  burning a failing clone every rotation slot.

  **Dexter's half is DONE (2026-07-25, on request).** A dedicated
  passphraseless keypair scoped to wtul alone was generated on dexter
  (`~/.ssh/dexter_wtul_deploy`, same shape/naming as the crt key), and a
  `Host github-wtul-deploy` block was added to dexter's `~/.ssh/config`.
  Verified wired rather than assumed -- the failure mode moved from DNS to
  auth, which is precisely what "our half done, GitHub's half not" looks
  like:

  ```
  before: ssh: Could not resolve hostname github-wtul-deploy
  after:  git@github.com: Permission denied (publickey)
  ```

  **What's needed from you -- ONE step, GitHub UI.** Add this public key
  as a Deploy Key on `hf7y/wtul` with **write** access (wtul's batch job
  pushes), restricted to that one repo -- same minimal-scope precedent as
  crt's key:

  ```
  ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMuscF0WDv5aMq0vonqphUyl//kneFEA9HgNLj1ENAEP dexter-wtul-deploy
  ```

  Fingerprint `SHA256:PF2dUFFdzCvD4lZ/Mhcd2Kkf9m103pt0kWxb9ov/QLA`. It has
  to be the UI (or another host with an authenticated `gh`): `gh` is not
  installed on dexter at all (`gh: command not found`), so there is no
  authenticated path to `gh repo deploy-key add` from there.

  Then `git ls-remote git@github-wtul-deploy:hf7y/wtul.git` from dexter
  must return refs before the enabled flip -- the key existing on dexter
  is NOT the same fact as GitHub accepting it. Full checklist with the
  exact flip in `schedule/_paced.dexter.conf`'s wtul block.

  Secondary question worth answering at the same time: is the
  non-hardware-on-dexter test still wanted at all, or does crt's single
  data point plus this friction argue for leaving the pin-by-need policy
  as-is?

- **2026-07-26 (via /nightly-batch, paced cycle): loud "Not logged in"
  detection is BUILT at source, but delivery to svc-vaporwave's own
  wrapper copies can't be done or verified from here -- one small human
  step remains.** Acting on your 2026-07-25 answer ("make the failure
  LOUD"): `lib/sweep-loop-common.sh` now captures claude's own output
  per-run and, on a failed run whose output matches auth-lapse markers
  ("Not logged in", "please run /login", expired OAuth, invalid API
  key), emits a distinct `CRITICAL: claude authentication failure` log
  line naming the fix (run any interactive session as that OS user), a
  dedicated `notify-send -u critical`, a specific `push reason:` when a
  commit was stranded, and a `=== FAILED (auth: not logged in)` status
  line that `scheduler status` surfaces (only while the LAST run is
  still FAILED). Verified against fake `claude`/`notify-send` shims:
  auth-fail, generic-fail, success, and commit-then-auth-fail paths all
  behave. **The gap:** every job sourcing this lib gets it once merged
  (chezz, wtul, home-assistant, vkv-inventory's mandark wrapper source
  the lib from the real checkout) -- but aedile's wrapper is BESPOKE
  (its header opts out of the shared engine; it calls `claude -p`
  directly with no auth-failure branch), and svc-vaporwave's installed
  copies live in its home directory, which this account cannot read
  (permission denied), let alone edit -- and installed wrappers are
  outside an unattended cycle's write scope anyway. Needed from you (or
  a session as svc-vaporwave): (1) confirm whether svc-vaporwave's
  aedile/vkv-inventory wrappers source their own lib copy or a path
  into /home/zach; (2) for the bespoke aedile wrapper, add the same
  pattern after its `claude -p` failure branch -- capture output, grep
  the auth markers, CRITICAL log line + flagged line in the report
  (notify-send is a no-op for a headless account, the LOG line is the
  loud channel there).


- **2026-07-26 (via /nightly-batch, paced cycle): should the three
  installed COPIES under `~/.local/bin` become symlinks into the checkout?
  Detection is built; the fix is one `ln -sfn` each and I won't run it --
  installed wrappers are outside an unattended cycle's write scope, and
  the choice is a real policy call, not a typo.** Verified live this
  cycle: `~/.local/bin/usage-paced-runner.sh` (what cron runs every 5
  minutes) is a copy matching `d431e8b` (2026-07-24), one commit behind
  `origin/main`; `scheduler-dev-cycle.sh` and `usage-gate.sh` are copies
  that match today; only `scheduler` is a symlink. The sharper half is
  that a copy install doesn't just go stale, it **changes behavior**: the
  runner's auto-pull (built 2026-07-24 so a commit on one host reaches
  the other) resolves its repo from its own path, gets `~/.local` under a
  copy install, finds no git dir, and skips the pull entirely -- 0 `PULL`
  lines in 1633 lines of its `run.log`, and 11 `[legacy absolute path]`
  fallbacks for the same reason. The two answers I can see:
  (a) **symlink all three** (`ln -sfn "<checkout>/bin/<name>"
  ~/.local/bin/<name>`) -- every merged commit is live immediately, the
  auto-pull and the repo-relative `_paced.conf` resolution both start
  working, and drift becomes impossible rather than merely detected;
  (b) **keep them copies on purpose**, as a manual deploy gate so a bad
  commit doesn't reach a 5-minute cron tick unreviewed -- in which case
  the runner needs an explicit repo path (e.g. a `SCHEDULER_REPO_ROOT`
  in `_runner.conf`'s `RUNNER_ENV`) instead of path-derived resolution,
  because today it silently gets neither behavior.
  I've built the detector either way: `bin/deploy-drift-check.sh`, wired
  into `scheduler sweep`, which now prints all three findings with the
  exact `ln -sfn` line -- so under (b) the sweep will keep flagging the
  copies, and that noise is itself a reason to answer rather than leave
  it. Related, seen the same pass and *not* drift: today's paced cycles
  ran with a hand-set `USAGE_CEILING` (0.95, then 0.99) while
  `sync-crontab.sh`'s preview still emits only `PACED_MAX_PER_TICK=16` --
  the crontab is consistent with the repo; the ceiling was overridden
  per-invocation, which is exactly the ephemeral-override pain the
  "make the usage-gate ceiling settable from a config file" backlog item
  (2026-07-25 17:06) is about.

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

- **2026-07-25 (via /nightly-batch, paced cycle): `.claude/commands/nightly-batch.md`'s
  own report-filename bug (line 68, `$(date +%Y-%m-%d).md`) can't be fixed
  from inside an unattended cycle -- the harness refuses the write outright.**
  FOCUS.md's confirmed-real "report filenames are date-only" finding
  (2026-07-20) says the fix (`$(date +%Y-%m-%dT%H%M)`) already landed in
  every in-repo template (`examples/nightly-batch-loop.sh`,
  `examples/nightly-batch.md.template`, `examples/schedule-entry.conf.template`)
  and only the *installed* `~/.local/bin/*-loop.sh` wrappers were left
  pending human go-ahead (they're live, outside this repo). But this
  repo's own `/nightly-batch` command definition -- `.claude/commands/
  nightly-batch.md`, tracked in git, not a live wrapper -- still has the
  same stale line, and was missed by that pass. Tried to fix it directly
  this cycle (`Edit` tool): the harness returned "Claude requested
  permissions to write to .../.claude/commands/nightly-batch.md, but you
  haven't granted it yet" -- consistent with the ".claude/** writes get
  hard-refused in unattended runs" gate this repo's own
  `SCHEDULER_SUBDIR` design already worked around for FOCUS/QUESTIONS
  (moved to `.scheduler/` for exactly this reason), but slash-command
  definitions have no equivalent escape hatch -- `.claude/commands/` is
  where Claude Code itself requires them to live. Needs a human touch (a
  one-line edit, `date +%Y-%m-%d` -> `date +%Y-%m-%dT%H%M` at line 68) or
  an explicit permission grant for that one path if unattended cycles
  should be able to fix their own command files going forward.

- **2026-07-26 (via `/nightly-batch`, paced cycle): the live ceiling
  (`USAGE_CEILING=0.99`) is set somewhere I can't see or edit — do you want
  it moved into `schedule/_usage.conf`, and at what value?** Built this
  cycle: the gate now reads its pacing knobs from `schedule/_usage.conf` /
  `_usage.<host>.conf`, so a durable ceiling is a one-line conf edit instead
  of a `RUNNER_ENV` + `--apply` round trip that ends up on a crontab line
  (commit `4355972`, FOCUS.md backlog item 2026-07-25 17:06). Env still
  outranks the conf, deliberately — one-off `USAGE_CEILING=x` tests keep
  working.

  The catch, found while testing: **this cycle's own environment carries
  `USAGE_CEILING=0.99`, and that value appears in no conf in this repo.**
  `schedule/_runner.conf` sets only `PACED_MAX_PER_TICK=16`, and an earlier
  cycle today already noted the crontab preview matches the repo — so 0.99
  is a hand-set override living outside version control (an earlier cycle
  logged it as "hand-set 0.95 → 0.99"). I did not go looking in the live
  crontab: reading it means running `crontab`, which this job is forbidden
  to do. Because env wins, **live pacing is unchanged by my commit** — 0.99
  stays in force until you act.

  Three things I'd want your call on rather than guessing:
  1. **Should 0.99 become the committed value** in `_usage.conf` (uncomment
     `USAGE_CEILING=0.99`), or was it a temporary push toward a quota
     deadline that should decay back to the 0.85 default? At the moment I
     checked, the 7d window was at 90% utilisation — at the 0.85 default the
     gate returns HOLD, so this is the difference between dispatching and
     not, i.e. don't let it drift by accident either way.
  2. **Once it's in the conf, the ambient env value should be dropped** from
     wherever it's set — otherwise the conf is decorative and the real value
     is still invisible. That edit is outside this repo (a `crontab -e`, or
     whatever shell/wrapper exports it), so it's yours.
  3. **Per-host or shared?** `_usage.dexter.conf` would let dexter keep more
     headroom now that two hosts probe one account budget
     (DESIGN-NOTES.md:807 anticipated exactly this). I built the mechanism
     but set no host-scoped value — nothing suggests dexter needs a
     different ceiling *yet*.
