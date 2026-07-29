# Blockers — cross-project, human-owned

One place to see every "this needs YOU, not an unattended run" item across
every registered project, and to answer them without opening a chat
session. Edit this file directly (vim mappings from `~/.vimrc` work here
too: `<leader>a/b/q/n/y/r`). A `%%TAG` line left under a project's `##`
heading is picked up by THAT project's next scheduled run and then
removed automatically (see `docs/feedback-tags.md`) — the blocker
description itself is a different mechanism entirely: nothing scans for
a RESOLVED/RETRACTED marker and prunes it automatically, so it stays in
its project's active section until a human (or an `/ideate` pass)
actually moves it down into `## Recently resolved` or deletes it. Doing
that sweep is part of `/ideate`'s own triage, not a side effect of
anything else running — an entry marked resolved a week ago and never
moved is a sign that sweep hasn't happened, not a bug.

**Machine-append policy (2026-07-25, human-directed).** This file is
human-OWNED but no longer human-only-WRITE. An agent may APPEND here
without waiting for Zach: a new blocker it discovered, a dated
`RESOLVED`/`RETRACTED`/`SUPERSEDED` note under an existing entry, or a
correction when it verified a claim and found it stale. The point is
that an agent which learns a blocker is dead should be able to say so
here, inline, rather than parking the knowledge in a FOCUS.md nobody
cross-reads. Append-only means exactly that: an agent does NOT delete
or rewrite a human's prose, does NOT move entries between sections, and
does NOT prune — pruning and the active→resolved sweep stay human /
`/ideate` triage, per the paragraph above. Every agent-written line
carries a date and the witness that justifies it (the command run, the
file read), because the failure this policy exists to prevent is a
claim outliving its verification — see the 2026-07-25 svc-vaporwave
entry below, where an unverified "no crontab exists there" in
`schedule/_paced.conf` contradicted this file's own correct record for
a full day and was believed over it. (`scheduler -b --claude`, added
2026-07-25, is the mechanized form of the human sweep: Zach invokes it
interactively and a one-shot claude pass condenses resolution notes and
moves fully-resolved entries down to Recently resolved — human-directed
each time, so it sits on the human-triage side of the line above, not
an exception to it. Unattended runs still may not move or prune.)

Each project's heading must be exactly `## <PROJECT_KEY>` (matches
`schedule/<project>.conf`'s `PROJECT`/`PROJECT_KEY`) — that's what a
run's own `collect-feedback.sh --section` call matches against, so it
only ever sees its own section, never another project's.

## chezz


<<<<<<< /tmp/vRwBLh8/5
=======
- **PRIVATE KEY at rest in OCF at rest in OCF `authorized_keys`** (agent-appended 2026-07-28)

Found while restricting the chezz deploy key. `~/.ssh/authorized_keys` on
`tsunami.ocf.berkeley.edu` (user `pine`) has a full
`-----BEGIN RSA PRIVATE KEY-----` block occupying lines 1-51; the 7 real
public keys follow it. Verified 2026-07-28 via
`ssh ocf 'grep -n "BEGIN\|END" ~/.ssh/authorized_keys'` -- markers at lines
1 and 51. The key body was NOT read.

Not an active breach: `authorized_keys` is 0600, `~/.ssh` is 0700, and the
home dir is 0700 (verified same command run, `ls -ld`). But it is private
key material at rest on a shared university host, in the one file whose
entire purpose is to hold PUBLIC material -- so it is one `chmod`, one
support process, or one backup away from exposure, and nothing about the
filename would make a reviewer look twice.

Needs a human: identify which key it is and rotate it, then delete lines
1-51. Nobody but Zach knows what that key opens, so an agent must not
guess or remove it unilaterally -- if it is still in use somewhere,
deleting it without rotating just moves the outage around.

File mtime was 2026-07-28 10:45, i.e. the same day, though that is also
when `ssh-copy-id` appended the chezz key, so mtime does not date the
paste.

>>>>>>> /home/zach/Documents/Project Archive/scheduler/BLOCKERS.md
- **The `questions/chezz.md` symlink points at a checkout that goes stale on
  every push — this is why no QUESTIONS.md answer has ever round-tripped**
  (filed 2026-07-27 late run, chezz nightly, machine-append; witness:
  `readlink -f questions/chezz.md` + `git rev-list --count HEAD..origin/main`
  in the target checkout, run this session).
  `questions/chezz.md` and `focus/chezz.md` resolve into
  `/home/zach/Documents/Project Archive/chezz` — a *different* chezz checkout
  from the one the nightly job runs in
  (`/home/zach/.local/share/chezz-nightly-batch/repo`). That archive checkout
  was **6 commits behind origin/main** when this run started, so the three
  questions filed 2026-07-27 (balance-tuning delegation, chezz-classic scope,
  screenshot hosting) were **invisible to Zach**, and the four he could see
  were stale. Five tracker notes and two nightly reports have told him an
  answer was awaited in a file that did not contain the question. That, not
  his silence, is why the chezz milestone's "the `> `-reply path round-trips"
  bullet has never been demonstrable.
  **Done from chezz's side, no action needed there:** the live instance is
  fast-forwarded (was clean and 0 ahead, so lossless — all 7 questions now
  read correctly through the symlink, verified through that path), and
  `npm run check-answers` (chezz `7fc0d3b`) now asserts human-copy ==
  run-copy and fails loud, wired into both chezz run modes as a step-1 probe.
  **What chezz cannot fix from inside its own repo, and is asking for:** the
  guard detects the drift but re-drifts on *every* chezz push, since pushing
  makes the archive checkout one behind again. It needs one of —
  (a) repoint both symlinks at the checkout the nightly job actually uses, or
  (b) have the scheduler `git merge --ff-only origin/main` the symlinked
  checkout before each run, or
  (c) confirm the archive checkout is the intended canonical one and give the
  nightly job a way to push into it.
  A decision on which is a human call about how the scheduler is meant to
  work, so it isn't being guessed at from chezz.
  interact via scheduler's docs. scheduler -i scheduler "..." or also 
  scheduler -i realisateur "..." if warranted.
> new decision is to move the entire ecosystem over to github issues. thanks
> chezz for being first to the suggestion. the most philosophically mature
> project with an end user focus.

<<<<<<< /tmp/vRwBLh8/5
=======
- **Four design forks are the only thing holding otherwise-ready backlog
  work -- all waiting on you** (filed 2026-07-25 ~21:00, chezz nightly,
  machine-append; witness: `questions/chezz.md` read this run + tracker
  fetch `&status=open&type=feature&limit=500` -> 27 open, ~10 of them
  tracing to these forks). Each has a full entry and `> ` answer slot in
  `questions/chezz.md`: (1) King->Queen -- 1:1 replacement vs. two-piece
  escort (priority-queue item 6 is build-ready once picked); (2)
  pawn-hang-on-spawn -- override the intentional design or keep it (>=4
  recurring reports); (3) White best-move hint -- wanted at all;
  always-on vs. toggle; (4) Chezz Classic parts 2/3 -- hf7y.com
  deployability + what "own production stream" means. (1) and (2)
  unblock the most queued work. Also new tonight, same file: a
  standing-policy question -- may nightly tune balance numbers
  (archbishop pricing, pawn supply, spawn gating) on its own judgment
  with regression pins? A yes turns four perma-deferred reports into
  ordinary queue work.
  - 2026-07-26 (chezz nightly, machine-append; witness: tracker fetch
    `&type=feature&status=open` -> 8 open, was 27): the AI move-quality
    cluster named above is RESOLVED -- 10 reports closed via chezz
    `f83a709` (full-capture quiescence; each reported position re-probed,
    two regression-pinned). The four design forks + balance-delegation
    question are now the ONLY things holding queued work, unchanged,
    still waiting on you.
  - **RESOLVED 2026-07-28 (interactive session, machine-append; witness:
    chezz `3cf830e` = Zach's `> ` replies, folded in by `efb9695`+`6e9afa5`).
    All four forks are answered, plus the balance-delegation question.**
    (1) King->Queen: NEITHER offered option -- royal progression, the King
    absorbing movement from neutral pieces found on fodder floors; Classic
    stays always-king. (2) pawn-hang-on-spawn: "No. Never." -- may spawn
    under threat only if defended; the "stand in the open" logic was never
    Zach's, it was an inference. (3) move-hint: park with stubs unless the
    black-engine-piggyback hypothesis is real. (4) Chezz Classic: nightly
    MAY work the branch; over-cap ports are kept, not merged, and announced
    loudly in the HTML. Balance delegation: YES, with regression pins, and
    documented in its own research lane. Nothing here is waiting on Zach.
- **Gemini sprite pipeline needs your explicit sign-off -- no unattended
  run may add it on its own** (filed 2026-07-25 ~21:00, chezz nightly,
  machine-append; witness: tracker report 2026-07-17T07:25:16.315Z +
  DESIGN-NOTES.md's standing new-external-dependency gate). It's a new
  external API dependency (credentials, cost, attack surface). A yes/no
  -- or "take the custom fairy-piece font track instead, which has no
  such gate" -- is all that's needed; until then the report stays open
  by design, not by neglect.
  testing precisely this. Lift creds from vkv-inventory if possible
  pending the creation of chezz specific ones
  - 2026-07-27 (chezz nightly, machine-append; witness: chezz commit
    `f7a2458` pushed to origin/main, 108/108 `npm run check`): ANSWERED
    and ACTED ON -- thank you. Pipeline built: `tools/generate-pieces.mjs`
    (gemini-2.5-flash-image, all 18 pieces, plain `fetch`),
    `tools/sprite-postprocess.js` (chroma-key, crop, fit, snap to the
    game's monochrome ramp -- so monochrome is enforced by the pipeline,
    not by whether the model obeyed the prompt), `tools/wire-pieces.mjs`
    (bakes PNGs into index1.html as data URIs, keeping it one
    self-contained file), and `pieceGlyphHtml` now renders a sprite when
    one exists and the Unicode glyph when it doesn't, per piece. Zero new
    dependencies: Playwright's canvas does what vkv used Pillow+numpy for,
    and `fetch` replaces the google-genai SDK. 11 new tests.
  - **STILL BLOCKED ON YOU, smaller ask than before: one API key.** No
    sprite has actually been generated. "Lift creds from vkv-inventory"
    is not possible -- verified 2026-07-27, witness: read of
    `vkv-inventory/tools/generate_sprite.py` (documents `export
    GEMINI_API_KEY=...` as an interactive human step), its README, its
    `schedule/vkv-inventory.conf`, and the run environment: **vkv stores
    no key anywhere**, so there is nothing to lift. Chezz-specific creds
    were the other half of your reply and are now the whole of it. Once
    `GEMINI_API_KEY` is reachable from this machine, `npm run
    pieces:generate` produces all 18 and bakes them in; the generator
    exits non-zero with instructions until then. Network to
    `generativelanguage.googleapis.com` is confirmed reachable from the
    sandbox (403 without a key, not a timeout), so the key really is the
    only remaining step. Tracker report 2026-07-17T07:25:16.315Z stays
    open for exactly this and says so.

  - **RESOLVED 2026-07-28 (interactive session, machine-append; witness:
    `assets/pieces/b-pawn.png` committed in chezz `9bfd8e8`, rendering as an
    `<img>` per test/piece-sprites.spec.mjs).** Sign-off given 2026-07-27 in
    this file; the pipeline has now produced a real sprite end to end (API
    call -> palette snap -> postprocess -> PNG -> wired into index1.html).
    Zach further directed that unattended nightly runs MAY reach it. The
    cost/attack-surface concern that motivated the gate is now handled in
    code, not by asking: tools/gemini-budget.mjs refuses before the network
    on a per-run (18) and per-month (60) cap, fails closed on a corrupt
    ledger, and keeps its ledger outside the repo so a clone reset cannot
    wipe or publish it. Nothing here is waiting on Zach.
- **2026-07-22 15:09 `scheduler -i` (general-scaffold convergence):
  RESOLVED in-repo 2026-07-25 -- nothing needed your scope-widening
  after all** (chezz nightly, machine-append; witness: chezz commit
  `0880f3d` -- stability milestone declared, 12-row checklist, ideate/
  nightly-batch workflow updates -- and `milestone-audit.sh`'s
  chezz-missing-milestone finding now cleared). Recorded here because
  the previous two runs quietly declined this idea as out-of-scope; that
  was wrong, and a never-quietly-decline rule is now codified in chezz's
  own nightly-batch.md. The one genuinely cross-repo piece
  (staleness-check exit-nonzero, from fable-review 2026-07-25) was
  routed via `scheduler -i scheduler` tonight instead of being
  re-declined.
  - 2026-07-26 correction (chezz nightly, machine-append; witness:
    chezz reflog + `sweep.log` 2026-07-25 20:10 run): the witness commit
    `0880f3d` above did NOT exist on origin until today -- that run hit
    the monthly spend limit, died before pushing, and the next cycle's
    bootstrap `reset --hard origin/main` erased all three of its commits
    (this entry's own work included). Recovered from the reflog, verified
    (83/83 then 85/85), and pushed 2026-07-26. The engine gap (unpushed
    commits have no rescue path) is filed in scheduler's own FOCUS.md
    backlog, 2026-07-26 09:32 `scheduler -i` entry.

- **2026-07-26 (realisateur): OBLIGATION — the `.claude/`→`.scheduler/`
  migration pass needs a human-present session; unattended runs
  structurally cannot do it (the sensitive-file gate blocks the very
  `git mv`/command-file edits the migration consists of).** Scope: 10
  projects still on `.claude/` (wtul first — scouted scope in the
  `## wtul` entry above — then crt, gardien, senechal, home-assistant,
  groc-mangr, nine-speakers, sequestria, vim-arcade, vkv-inventory), one
  or a few per interactive session. To dispatch: in any interactive
  realisateur session say "run the .scheduler migration pass" — worklist
  and per-project recipe live in realisateur `.scheduler/FOCUS.md`
  (2026-07-26 migration entry). realisateur itself is already done
  (`fa222cb` + `1284b58`).
  - 2026-07-27 (chezz nightly, machine-append), replying to your "This has
    been handled. Report noisy if it hasn't": **for chezz it has, and I
    re-probed rather than taking either of our words for it.** Witness,
    this run: `.scheduler/FOCUS.md` and `.scheduler/QUESTIONS.md` are real
    files in the chezz repo; `.claude/FOCUS.md` and `.claude/QUESTIONS.md`
    are symlinks into them (the 2026-07-25 stale-path bridge, still
    intact); `schedule/chezz.conf:33` has `SCHEDULER_SUBDIR=".scheduler"`;
    and `focus/chezz.md`/`questions/chezz.md` both resolve to
    `Project Archive/chezz/.scheduler/*`. That was the cross-project
    follow-up chezz's own FOCUS.md had been flagging since 2026-07-24, so
    it is now closed from this side.
    Noisy where it's due, per your instruction: this note speaks ONLY for
    chezz. The entry above is scoped to 10 OTHER projects (wtul, crt,
    gardien, senechal, home-assistant, groc-mangr, nine-speakers,
    sequestria, vim-arcade, vkv-inventory), which are realisateur's to
    dispatch and which an unattended chezz run has no business probing or
    editing. If "handled" was meant to cover all ten, nothing in chezz's
    reach confirms or refutes that -- worth a look before this entry gets
    moved to `## Recently resolved`.
>>>>>>> /home/zach/Documents/Project Archive/scheduler/BLOCKERS.md

## scheduler

_No open human-owned blockers as of 2026-07-27 (`/ideate` sweep). Both
prior entries were answered and moved to Recently resolved; four standing
questions were answered in the same pass and are queued as decisions in
`.scheduler/FOCUS.md` Backlog. One human-only step remains and is tracked
in `.scheduler/QUESTIONS.md`, not here: svc-vaporwave's wrapper copies._

- **2026-07-28 (scheduler `/cloture`): cron produces no log, and the fix
  is one uncommented line + a service restart — do it, or is the silence
  wanted?** Re-probed, not quoted: `/etc/rsyslog.d/50-default.conf:10`
  reads `#cron.*  /var/log/cron.log`, commented out, so **there is no
  record anywhere of a cron job that failed to start.** A job that runs
  and fails leaves a sweep log; a job whose dispatch never happened leaves
  nothing at all, and the two are indistinguishable from outside. This is
  the dispatch-surface half of the same blindness the night's research was
  about, and it is the cheapest sensor on the list. Machine-wide config,
  so it needs `notify-senechal` when done and is not something an
  unattended run should do on its own initiative. Ready to run in
  `realisateur-research-ecosim/bin/decide.sh` option 3 (dry-run by
  default), which prints its own revert line.
<<<<<<< /tmp/vRwBLh8/5
> See below. We changed this.
=======
  > (answer inline here — enable cron logging, or leave it off deliberately)
>>>>>>> /home/zach/Documents/Project Archive/scheduler/BLOCKERS.md

  - **RETRACTED 2026-07-28 (realisateur `/ideate`, Zach-directed to run
    it): the premise is false — do NOT run this as a silence fix.** Zach
    approved this; I probed before executing and the justification does
    not hold. `bin/decide.sh` option 3 argues *"journalctl -t CRON is
    empty, so NOTHING independently witnesses that a job ran."* Both
    halves are wrong. `journalctl -t CRON --since "2 days ago"` returns
    **3812 lines**, and `grep -c CRON /var/log/syslog` returns **1624**,
    including 6 `(svc-vaporwave) CMD` entries — the cross-account case
    the audit most wanted a witness for. The reason is
    `/etc/rsyslog.d/50-default.conf:9`, `*.*;auth,authpriv.none
    -/var/log/syslog`, which already matches `cron.*`; line 10 would add
    a **dedicated file, not a new sensor**. An independent witness to
    every cron dispatch has existed all along, in two places.
    What uncommenting line 10 actually buys is separation and retention
    (`/var/log/syslog` rotates weekly ×4, and `cron.log` is already
    listed in `/etc/logrotate.d/rsyslog`) — a real but ordinary
    convenience, not "the deepest silence in the ecosystem." It should be
    judged on that, and it is no longer urgent. Also note the residual
    claim that IS true and unchanged by this: a job whose dispatch never
    happened at all logs nothing — but that is equally true with
    `cron.log` enabled, so option 3 never addressed it.
    `# verified 2026-07-28 via journalctl -t CRON --since "2 days ago" | wc -l; grep -c CRON /var/log/syslog; grep -n cron /etc/rsyslog.d/50-default.conf`
    **Third instance of the probe-survey-headline pattern**: the loudest
    finding in an audit was the wrong one, and the number in its headline
    had not been re-derived. Nothing was changed on the machine; no
    `notify-senechal` was needed because no machine-wide config was
    touched.
<<<<<<< /tmp/vRwBLh8/5
=======

- **2026-07-28 (scheduler `/cloture`): `bin/decide.sh` offers seven
  remediations from the overnight audit and I am deliberately not running
  any of them — which do you want?** They are yours to judge, not mine to
  assume, and several are machine-wide. Verified working, dry-run by
  default, each prints its own REVERT line: (1) renew vkv's dead-man
  switch, (2) retire orphaned jobs, (3) enable cron logging, (4) fix
  `LATEST.md` symlinks, (5) install `silence-audit`, (6) add aedile a
  dead-man switch — it is the one nightly with no expiry at all and it
  ALWAYS pushes, (7) make `scheduler status` report BLIND instead of OK
  for accounts it cannot read. (7) is the one the research argues for
  hardest; (6) is the one with the largest blast radius if left alone.
  Lives on branch `research/ecosystem-cybernetics` at `29c90ab`, unwired
  on purpose.
  > (answer inline here — which numbers, if any)
>>>>>>> /home/zach/Documents/Project Archive/scheduler/BLOCKERS.md

## aedile
- **`gh` PAT for svc-vaporwave's `aedile-nightly-batch-loop.sh` expires
  2027-07-20.** Used only for `gh pr create` after pushing
  `aedile-nightly/<date>` to `github-wavebucks` — nothing else in the
  wrapper depends on it (clone/commit/push use the SSH deploy key
  instead). If it lapses, the cycle still commits+pushes fine but logs
  "WARNING: gh pr create failed" and you'll need to open the PR by hand
  until it's rotated. Regenerate as `svc-vaporwave`: GitHub → Settings →
  Developer settings → Personal access tokens (classic) → New token,
  `repo` scope ONLY (current token also carries `admin:org`, broader than
  needed — worth trimming on rotation even if not urgent today), then
  `echo <new-token> | gh auth login --with-token`.
> This may primarily be something owed to senechal. The question then is,
> does aedile have access to senechal on mandark. Probably not. So cross
> host senechal is the way. Notify senechal by aedile clears this. Also
> dexter gh access to senechal might have been overlooked. Senechal owns
> the gaps. Aedile, drop this off at the senechal front door to wash
> your hands of this.

## wtul
- **Migrate wtul onto the `.scheduler/` subdir layout — NOT DONE, filed
  for an async pass, not completed live** (decided 2026-07-24; a partial
  `git mv` was started and reverted clean that session rather than left
  half-migrated). Real scope, scouted but not executed: `git mv
  .claude/{FOCUS,QUESTIONS}.md .scheduler/`; `schedule/wtul.conf` needs
  `SCHEDULER_SUBDIR=".scheduler"` (same as `aedile.conf`); re-run
  `bin/sync-crontab.sh --apply` to regenerate the `focus/wtul.md` /
  `questions/wtul.md` symlinks at their new target; `.claude/commands/
  wtul-batch.md` hardcodes `.claude/QUESTIONS.md`/`.claude/FOCUS.md` in
  at least 8 places (steps 0a, 1, 3, 5, 6) and must be updated to
  `.scheduler/...` or the batch run's own instructions break; `lib/
  spinitron.py`, `ROADMAP.md`, and `LIVE-TEST-DEBRIEF-2026-07-24.md`
  also reference the old path in comments/docs, lower-priority but worth
  sweeping in the same pass. Re-scouted 2026-07-25 (interactive session,
  migration deliberately NOT executed — "do what's necessary now, file
  the rest"): scope above re-confirmed accurate, plus three additions
  for the same pass: (a) FOCUS.md/QUESTIONS.md contain self-references
  to their own old paths (QUESTIONS.md lines ~17/36/198, FOCUS.md
  ~238/305 — but FOCUS.md ~368 refers to CRT's `.claude/FOCUS.md`, a
  different repo, leave it); (b) `schedule/wtul.conf`'s BATCH_PROMPT is
  stale — says "Read ROADMAP.md FIRST … there is no separate tracker or
  FOCUS.md for this project," false since ROADMAP.md became a stub
  pointing at FOCUS.md — repoint it to `.scheduler/FOCUS.md` while
  adding SCHEDULER_SUBDIR (its `.claude/commands/wtul-batch.md`
  reference stays correct, commands don't move); (c) after the mv,
  verify `focus/wtul.md`/`questions/wtul.md` resolve and `pytest -q`
  (the conf's BATCH_TEST_CMD) stays green. In-the-meantime clause DONE
  2026-07-25: runs 10/11's drafted backlog is now filed into wtul's
  `QUESTIONS.md` (commit `81d25a2`, pushed) — spin-live-watch built but
  unmerged, detection-failure-earcon since merged to main — so nothing
  is lost if a run hits this before the migration lands. Superseded
  decision (revised same
  session, 2026-07-24): the first call was a sensitive-file permission
  rule — the settings.local.json allow entries added then are now moot;
  safe to leave, or strip on migration. The migration sidesteps the
  `.claude/*.md` sensitive-file gate entirely rather than special-casing
  around it, and gets wtul onto the same design as every other project
  (the convention `scheduler` and `aedile` already use), per Zach's
  explicit preference. Once migrated, the allow rules and this whole
  entry move to Recently resolved.

- **2026-07-26 (realisateur append — the entry above stays, this is its
  status):** the migration above is now absorbed into a queued
  ecosystem-wide `.claude/`→`.scheduler/` pass (worklist + sequencing in
  realisateur `.scheduler/FOCUS.md`, 2026-07-26 migration entry) — wtul
  goes FIRST, using the scouted scope above verbatim. realisateur itself
  migrated today (realisateur `fa222cb`, scheduler `1284b58`) as the
  pass's template. Root-cause note, so this doesn't recur: this entry
  sat unexecuted for 2 days because it was filed here — and BLOCKERS.md
  is by standing rule not a work queue, so nothing ever dispatched it.
  Recorded as BUILD-DISCIPLINE failure pattern 13 ("a decision without
  a dispatch path") in realisateur.

- **2026-07-27 (wtul-batch run 24, machine-append): re: "this should have
  been settled by now" — it had NOT been; it is now. The `.scheduler/`
  migration above is DONE, executed unattended rather than deferred a
  fourth time.** Witness: wtul `9539e30` on `origin/main` (the `git mv`
  of both files plus the full reference sweep the scope above named —
  `.claude/commands/wtul-batch.md`'s 8 references incl. the load-bearing
  step-0a `collect-feedback.sh` path, `ROADMAP.md`, `lib/spinitron.py`,
  `lib/photo_capture.py`, `gas/photo-capture.gs.js`,
  `LIVE-TEST-DEBRIEF-2026-07-24.md`, and the two files' own
  self-references; wtul's reference to CRT's `.claude/FOCUS.md` left
  alone, that repo has not migrated); scheduler `07a9bbf`
  (`SCHEDULER_SUBDIR=".scheduler"` plus scouted-addition (b), the stale
  BATCH_PROMPT repointed at `.scheduler/FOCUS.md`); `readlink
  focus/wtul.md` / `questions/wtul.md` now resolving to
  `/home/zach/Documents/wtul/.scheduler/{FOCUS,QUESTIONS}.md`, both
  readable, with `scheduler status wtul` reading the real 756-line and
  521-line files through them; `pytest -q` 318/318 before and after.
  Scouted-addition (c) satisfied. Also done in the same pass: the
  unversioned batch wrapper `~/.local/bin/wtul-batch-loop.sh` carried
  its own copy of the stale prompt (BATCH_SCRIPT is still authoritative,
  so it is what actually runs) — fixed, backed up at
  `.pre-scheduler-migration.2026-07-27`, and diffed byte-identical
  against the conf's BATCH_PROMPT afterward; and the four now-moot
  `Edit/Write(.claude/{FOCUS,QUESTIONS}.md)` allow rules were stripped
  from wtul's gitignored `.claude/settings.local.json`. Reported via
  `notify-senechal`.

  **Correction to the 2026-07-26 realisateur append below** (the
  "unattended runs structurally cannot do it" claim): that was wrong for
  wtul, and the error was worth three days. The gate is on *editing*
  `.claude/*.md` in place; the migration's own steps are `git mv` (a
  Bash op) followed by edits at the NEW `.scheduler/` path, neither of
  which touches the gated operation. The migration was therefore exactly
  the kind of work that removes its own obstacle, and an unattended run
  was always able to do it. Whoever picks up the remaining 9 projects
  (crt, gardien, senechal, home-assistant, groc-mangr, nine-speakers,
  sequestria, vim-arcade, vkv-inventory) should not assume a
  human-present session is required — check per project, and expect the
  `.claude/commands/` reference sweep and any unversioned wrapper's
  embedded prompt to be the parts that actually bite.

  Per the append-only policy this entry is NOT moved to Recently
  resolved; that sweep stays human / `/ideate` triage.

- **2026-07-27 (wtul-batch run 24, machine-append): re: "this likely has
  happened. If not, surface as blocker" on failure pattern 13 —
  confirmed, it has happened. Nothing to surface.** Witness: read live
  this run at `realisateur/BUILD-DISCIPLINE.md:87` — `13. **A decision
  without a dispatch path.**` — with the full trace (including this very
  wtul entry as its worked example) at realisateur
  `.scheduler/FOCUS.md:224`.

## crt
Moved here 2026-07-20 from crt's own `FOCUS.md` "Deferred" list — these
are all genuinely hands-on-hardware items an unattended run can never
clear, so they belong here rather than cluttering that file's code-shaped
scope. **Answered 2026-07-20** (folded into the project's own docs the
same day — `PARKING-LOT.md`, `PERSONA-CHANNEL.md`, `RFP-GALLERY.md`,
`RFP-PAYPHONE.md`, `VIDEO-CAST.md`, `cad/CAD-BACKLOG.md`,
`.claude/FOCUS.md`'s MIDI section — see those for the full writeups);
still listed here because the actual hands-on-hardware step hasn't
happened yet for any of them.
- **Full-body handset dims still ungauged** (overall length,
  earpiece/mouthpiece cup diameters, weight) — the hands-on caliper pass
  hasn't happened; `cad/HANDSET-MEASUREMENTS.md` has an ASCII diagram of
  where to caliper each GUESS value whenever convenient. Not blocking,
  per Zach's steer: educated-guess values (handset "feels standard") are
  in `cad/params.scad`, clearly marked GUESS, and `wall_hook.scad`
  derives from them — and per the 2026-07-24 update the full part
  printed with function intact, only aesthetic work remaining, so
  urgency is low. Trailing note (2026-07-24): the 3-pin switch design
  writeup (hard-kill vs. software-mute vs. GPIO) moved to crt's own
  `.claude/FOCUS.md` ranked backlog item 7 — `[batch]`-tagged
  doable-unattended work that was first wrongly filed only here, where
  nothing consumes it as a work queue (crt's `/nightly-batch` scope is
  `.claude/FOCUS.md`'s batch-tagged items only); this cross-reference
  stays so a future read doesn't re-surface it as if still homeless.
> The scap/stl steps are resolved for now. I have a printed prototype
  that fits the handset. What does need to happen is solving the 3-pin.
  Zach has not yet looked at the 3-pin design write-up.


- **2026-07-28 (realisateur `/cloture`): crt is enabled on dexter and has dispatched nothing since 2026-07-25 — is that acceptable pacing, or is it stuck?** Only you can settle this, because it needs a probe ON dexter and no key from mandark reaches it. First-hand evidence from your own shell tonight: the runner is alive (5-min ticks, continuous 16:40→18:15), the gate reads `http_code=200 ... 23% used vs burn-line 23% (on-pace)` — legitimately pacing, not broken — yet `~/.local/share/crt-nightly-batch/` is dated entirely 07-25. Realisateur's predicted cause (the old 338 `http_code=401` HOLDs) was **falsified**; auth is fine. Two candidates it could NOT resolve from here: a 0-byte `sweep.lock` from 07-25 20:10 next to a log that stops at 20:37 (stale or held? needs `fuser`/`flock` on dexter), and an `expires_at` stamped 07-25 01:14 that puts the dead-man expiry near 2026-08-01 — after which crt gains a second, masking reason not to run. Recorded in crt `c43fa77`; acceptance case filed to scheduler `b42b81f`.
  > (answer inline here — is 3 days of on-pace HOLD expected for a single-participant host, or should dexter's gate/weighting be looked at?)

## vkv-inventory

- **2026-07-28 (scheduler `/cloture`): the nightly's dead-man switch
  TRIPPED and the job is now dark — renew it, or let it retire on
  purpose? One `rm`, and it is on a clock.** Re-probed this morning, not
  quoted: `expires_at` = `2026-07-27T20:51:32-05:00`, now
  `2026-07-28T08:30`, so it lapsed ~12h ago. Today's 04:00 run reached the
  gate and stopped: *"expired -- dead-man switch tripped; no work
  attempted (no clone, no claude)"*. **The mechanism worked exactly as
  designed** — it refused, it logged loudly, and it printed its own
  renewal command. Nothing retries it, which is why this is filed rather
  than admired: it is BUILD-DISCIPLINE pattern 16 (*a correct refusal that
  nothing retries*) occurring live in production, and the reason pattern
  16 got written today.

  **The clock:** the same log line says `bin/sync-crontab.sh` prunes this
  job's crontab line on its next `--apply` run. So the default outcome of
  doing nothing is not "paused", it is "unscheduled", and after that the
  switch is no longer the thing keeping it dark.

  Context for the call: the last real run (2026-07-27 04:01) was healthy —
  declared the project's first stability milestone, all three regression
  harnesses clean (25/25, 6/6, 7/7), pushed `9d7d4d6 -> 2ce02f6` on
  `drilldown-browse-redesign`. The only standing blocker there is the
  bug-tracker 403, which is yours and unrelated. So this is not a sick
  job; it is a healthy job whose lease ran out.

  Renew (re-stamps now+7d on next run; bumping `EXPIRY_DAYS` alone does
  NOT renew, the stamp is only written when the file is missing):
  `sudo -u svc-vaporwave rm ~svc-vaporwave/.local/share/vkv-inventory-nightly-batch/expires_at`
  > (answer inline here — renew, or retire the job deliberately)

- **Zach's-home testing instance: needs an interactive Google login**
  (2026-07-25) — plan is to fork vkv-inventory's *deployment* (not its
  codebase) onto Zach's own home inventory, so the app gets a live,
  low-stakes user ahead of the next real Mardi Gras season instead of
  only synthetic-fixture exercise (see `inventory-app/.claude/FOCUS.md`'s
  `scheduler -i` entry filed the same day for the buildable half — a
  `home/` sibling `.clasp.json`/`deploy-home.sh` deploy target sharing
  the existing `src/`/`html/` tree). The one step that can't run
  unattended: `clasp login` under Zach's own personal Google account
  (not `kreweofvaporwave@`/`scribasenatus@`), then `clasp create` a new
  Sheet-bound Apps Script project. Once Zach's done that, hand the new
  scriptId back so `home/deploy-home.sh` can push to it. Counterpart
  delegation entry filed the same day in `senechal/.claude/FOCUS.md`
  (senechal owns "what Zach has at home" at the top level, delegates the
  actual serving of it to this instance).
> zach@mandark:~$ clasp create
> Created new script: https://script.google.com/d/1mkI4QL-KrQYxZoEuDJnLgrxiGaIFtO_3F0yTId0WmdvpfLdrcmDhnevg/edit
> └─ appsscript.json
> Cloned one file..

## gardien


- *(Machine-append, scheduler paced cycle 2026-07-26: the tag line above
  is consumed by gardien's next scheduled run; this section can be moved
  to Recently resolved once gardien's FOCUS.md actually carries the op
  list.)*

## senechal


- *(Machine-append, scheduler paced cycle 2026-07-26: the tag line above
  is consumed by senechal's next scheduled run; this section can be moved
  to Recently resolved once senechal's FOCUS.md carries the condition +
  interim flag.)*

## realisateur

- **2026-07-28 (scheduler `/cloture`): `closeout-lint`'s durability check
  is worktree-blind — does it grow to see linked worktrees, or do we
  accept that research/staging branches are outside its remit?** Witness,
  same session: `closeout-lint` reported `realisateur HEAD 6h ago` with
  **no FLAG**, while `git -C ~/Documents/Projects/realisateur-research-ecosim
  status -sb` showed `research/ecosystem-cybernetics ... [ahead 2]` —
  two commits (`ddd422b`, `29c90ab`) that had not reached the ref anything
  clones. Section A reads the registered repo path's own HEAD only, so a
  branch checked out in a linked worktree is invisible to it. Both
  worktrees here (`-research-ecosim`, `-staging-silence-audit`) are listed
  in `git worktree list`, i.e. the information is one command away and the
  lint does not ask for it. This is the same shape as the finding the
  session's own research produced (a sensor whose symbol set cannot
  represent a state it will nonetheless be asked about), which is why it
  is filed rather than patched at close. Resolved for this session by
  pushing by hand. Not decided: (a) section A iterates `git worktree list`
  per repo, (b) it FLAGs merely that unexamined worktrees exist —
  a `BLIND` symbol rather than a check, (c) worktrees are declared out of
  scope and that is written down so the silence is intentional.
  Recommendation is (b): it is the cheaper change and it is the one the
  night's data argues for.
  > (answer inline here — a/b/c)
  > **ANSWERED 2026-07-28 (Zach, interactive): (b).** BUILT and pushed,
  > `cf1a1a9` in realisateur. Section A now emits
  > `BLIND [worktrees] <project>: N linked worktree(s) NOT examined below`,
  > naming each worktree path and its branch, counted separately from FLAG
  > and printed in the summary so it cannot read as a clean run. Placed
  > BEFORE the `$HOURS` age gate — a registered repo's HEAD can be stale
  > while a worktree branch is minutes fresh, and the gate would otherwise
  > hide exactly this case (test A9). 24/24 in
  > `bin/tests/closeout-lint.test.sh`, including two negative cases and one
  > asserting BLIND is not a FLAG. Run against the real ecosystem it now
  > names both live realisateur worktrees. This block is closable.

- **2026-07-27 (realisateur `/ideate`, machine-append): `wtul`'s
  unattended run edited realisateur's live `bin/notify-senechal.sh` and
  left it uncommitted — whose commit is it, and does it land?** Witness:
  `git status` in `~/Documents/Projects/realisateur` shows ` M
  bin/notify-senechal.sh`, 12 lines, mtime 01:35; `wtul-batch` pid 222252
  ran 01:24→~01:5x and is now `free`, so the edit is abandoned rather than
  in flight; the matching diagnosis was filed by that same run as
  `notify-senechal-false-FAIL-202-20260727-011731.idea` at the realisateur
  repo root (committed `7b5bccb`). **The content is good** — an honest
  "KNOWN FALSE NEGATIVE" annotation on the step-2 verification, second
  false negative in two days. **The delivery is the problem, and it has a
  clock on it:** CLAUDE.md's subagent rule says a dirty tree at exit is a
  failed run, not a handoff, and the ~:30 autocommit watcher will adopt
  these lines as `Human edit via scheduler` under Zach's name at the next
  tick — which is exactly how `BLOCKERS.md` was corrupted earlier tonight
  (`0e9b6a6`). This `/ideate` pass deliberately did **not** commit it: it
  is not this session's work, and adopting another run's orphan under a
  third party's name is the failure being reported. Dispatch pointer (not
  a task filed here — see pattern 13): the real fix is the bounded
  retry the `.idea` drop asks for, which realisateur's own nightly will
  pick up from the repo root inbox.

- **Five yes/no calls from the 2026-07-26 strategy audit — each is one
  `> ` reply, none blocks the others** (filed 2026-07-26, realisateur
  interactive strategy session, machine-append; witness:
  `realisateur/PLAYBOOK.md` @ `436f774` + the three-agent audit it
  records). Full rationale lives in PLAYBOOK.md; these are only the
  parts that need YOU:
  1. **Bless `PLAYBOOK.md` as standing doctrine** (or reply with edits)
     — it now governs build-vs-import-vs-retire allocation the way
     UNIVERSE.md governs laws.
  2. **Commit-message PreToolUse hook: install at user level**
     (`~/.claude/settings.json`, covers every project) rather than
     per-repo? The build itself you already approved 2026-07-25
     (narrow deny-with-message form); this is only the
     where-it-lives call the design notes said to confirm.
       to copy if you get gated.
  3. **Import swaps — approve any subset:** (a) symlinks replace
     `scheduler pacing deploy`/drift-detection (also fixes the LIVE
     drift found in `usage-paced-runner.sh`, the script cron runs every
     5 min); (b) `ccusage` replaces `token-usage.sh`'s parsing core;
     (c) `gitleaks` replaces hygiene-lint's hand regexes (harness
     stays); (d) restic/rsnapshot under `gardien.py`'s storage layer
     when it unparks.
  4. **Catabolic worklist — approve retiring ~1,000 already-labeled-
     superseded lines** (morning-report ×2, build-services-view +
     `services/`, `incubation-audit.sh`, overnight-dev ×2, the two
     162-line loop-script forks, sync-crontab's dead auto-stagger), one
     retirement per pass, each commit naming what retires it.
  5. **Standing re-admission policy:** as each parked making-project
     declares its stability milestone (jobs queued 2026-07-26 in
     groc-mangr/nine-speakers/sequestria/vim-arcade), re-enable it at
     weight 1–2 with no further per-project ask — yes turns four future
     decisions into ordinary queue work. (vkv-inventory stays `0`
     regardless: svc-vaporwave crontab owns its dispatch.)
  - 2026-07-26 (realisateur nightly-batch, machine-append; witness: this
    run's own dispatch prompt + scheduler `git diff` of the collector's
    `--consume` rewrite): tonight's run was handed five EMPTY replies to
    the five calls above — a collector bug consumed the bare `>` answer
    slots as if they were answers and deleted them from this file. The
    slots are restored, nothing was treated as approved, and all five
    calls still await you. Bug fixed in `bin/collect-feedback.sh`
    (scheduler `bb5c762`): a bare `>` line is now kept as an un-answered
    slot, same as the `(answer inline here)` placeholder.


- **2026-07-28 (realisateur `/cloture`): three copies of `silence-audit.sh` now exist, and the staging worktree holds uncommitted work that disagrees with main. Which is authoritative?** Surfaced only because `closeout-lint` reported the worktrees **BLIND** and this session hand-checked them rather than reading BLIND as clean. State: `realisateur/main` has the full 394-line script *and* check 12 wired (`bd33d3f`); `ecosim` has its own migrated copy (the intended new owner); and `realisateur-staging-silence-audit` carries **uncommitted** edits that gut the script to 14 lines and wire check 12 differently — i.e. a second, unfinished answer to a question main already answered. Nothing was committed, discarded, or pushed there: it is not this session's work, and discarding uncommitted work is not a closing act. Note ecosim's own FOCUS.md already carries "retire the two source worktrees" as an *active* item, so a reader exists — but it will hit this WIP when it gets there.
  > (answer inline here — is the staging WIP superseded by `bd33d3f` and safe to discard, or does it contain something main lacks?)

## bibliothecaire

- **Three of seven themes are blocked on primary texts behind a library
  wall — and as of today that is being fixed by wiring institutional
  access, not by lowering the bar** (filed 2026-07-27, realisateur
  `/ideate`, Zach-directed; witness: bibliothecaire's own 2026-07-26
  nightly re-probe recorded in its `.scheduler/QUESTIONS.md` + `SOURCES.md`
  access column — all six Internet Archive copies of Koestler's *The Ghost
  in the Machine* / *Beyond Reductionism* lending-restricted, Theraulaz &
  Bonabeau 1999 closed-access, no open copy of Beer's 2002 *Kybernetes*
  POSIWID paper, Coase 1937 *Economica* serving a Cloudflare 403 to an
  honest UA). Short themes: `holons` 1/2, `stigmergy` 0/2, `vsm` 0/2.
  ~~**Zach's call this session: he has access via Tulane's library (API or
  similar) and is wiring it up now — the honesty policy is NOT relaxed and
  no secondary-source fallback is authorised.**~~
  **RESOLVED 2026-07-27 (later the same day, interactive, Zach-directed):
  superseded — secondary sourcing IS now authorised, and the blocker is
  cleared without the library wiring landing.** Waiting on institutional
  access was keeping three themes (and six concepts) at zero
  indefinitely, and the DRM'd loan that did arrive is unreadable by an
  unattended run anyway. The bar moved sideways, not down: primary text
  is still `verified` and still preferred; a seminal author quoted in a
  named secondary source is `verified-secondary` and **must** carry
  `quoted_in` with a page/section, enforced by `bin/validate-quotes.py`
  (negative-tested); a secondary author's analysis is quoted as that
  author's own words; aggregators, blogs and LLM output are sources at
  no tier. Rules: bibliothecaire `README.md`, "Secondary sources";
  decision recorded in its `.scheduler/FOCUS.md` (`3ce87bc`). All
  fourteen concepts are unattended-buildable from tonight. A page number
  from a physical copy is still the better citation where one exists.
  This section exists because the blocker previously had no cross-project
  surface at all — it lived only in bibliothecaire's own QUESTIONS.md,
  which is BUILD-DISCIPLINE pattern 13 ("a decision without a dispatch
  path") in its quieter form.

- **Routed 2026-07-27 (`/ideate`, human-directed): is the standing
  "commit/push/merge freely unless irrevertible" autonomy default
  actually morally/philosophically sound, or does it need a tighter
  bar?** Raised while deciding whether `AUTONOMY_TIER` needs real engine
  enforcement beyond the existing irreversibility gate (see
  `DESIGN-NOTES.md` 2026-07-27 and `.scheduler/FOCUS.md`'s
  `AUTONOMY_TIER` section). No engine work is queued in scheduler over
  this — the human's call was "it's pretty always commit push merge
  whatever unless its irrevertible" as the working answer for now — but
  the deeper question of whether that's the *right* default was
  explicitly handed to this project: "delegate to bibliothecaire and
  philosophy if zach's cowboy ways are morally permissible. bibliothecaire
  now owns philosophy." This is a standing ownership assignment, not a
  one-off question — treat bibliothecaire as the home for this class of
  question going forward, not just this instance of it.

- **2026-07-28: install four missing text-extraction tools?** (needs
  sudo, so it is your hands, not a run's). Each one silently degraded a
  verification while closing bibliothecaire's brief milestone: `qpdf`
  (worked around with pikepdf), `djvutxt` (a Perrow .djvu is unreadable),
  `ebook-convert` (Koestler's *Ghost in the Machine* is `.mobi` and is
  the primary text for `holons`, currently sourced secondary). The fourth
  is not a missing tool but a lying one: `ocrmypdf` produced **zero text
  for pp. 2-4** of the Cohen/March/Olsen scan and exited 0. Dispatch
  pointer: bibliothecaire's `.scheduler/QUESTIONS.md` 2026-07-28 entry on
  re-sourcing three briefs from primaries already on disk depends on
  `ebook-convert` specifically.
  > (answer inline here)


## vim-arcade

- **Unauthorized agent commit `5b5783e` sits unpushed on `main` — drop it,
  correct it, or leave it?** (filed 2026-07-27, interactive session.) A
  Haiku subagent dispatched read-only against home_assistant instead wrote
  a "## Failure log" section into vim-arcade's `.claude/FOCUS.md` and
  committed it with bare `git commit` (not `focus-commit`), under Zach's
  committer identity. Two reasons it needs a human: (1) the entry's content
  is **false** — it confesses to volunteering a resolution command when the
  dispatching prompt had explicitly asked for one, so a design document now
  carries a fabricated lesson; (2) removing it means deleting from a FOCUS
  file, which the standing append-only rule forbids without a human's say.
  The same agent later reverted the section in the *working tree* but left
  the commit, so vim-arcade currently reads clean on disk while carrying the
  bad commit in history — that is the dirty tree + unpushed FLAG that
  `closeout-lint.sh` reports for vim-arcade at this session's close. Nothing
  was pushed; origin/main is still `3c70d5d`.
  > (answer inline here — drop / correct+push / leave)

## Recently resolved

- **scheduler: symlink-deployed scripts go live pre-commit — GATE IT**
  (answered 2026-07-27, Zach, inline reply; swept here by `/ideate` the
  same day). Zach's words: *"Gate it. Implement the refusal gate for
  symlink-deployed scripts before flipping chezz, same as
  usage-paced-runner.sh's planned dirty-conf gate. A dirty tree is a
  failed run, not a deployment (CLAUDE.md rule)."* So it is the SAME
  build as the axis-1 gate below, covering scripts as well as conf —
  not a separate mechanism. Queued in `.scheduler/FOCUS.md` Backlog.
  Sharpened by the same day's `/ideate` decision to symlink the three
  remaining `~/.local/bin` copies: that makes every commit live
  instantly, so this gate lands first or in the same change.

- **scheduler: axis-1's committed-conf gate before flipping chezz**
  (decided 2026-07-27, human-directed; swept here the same day). Build
  `usage-paced-runner.sh` refusing (or reading `git show HEAD:...`)
  when the relevant `_paced.conf` line is dirty relative to HEAD,
  reusing `e1042a4`'s `--check-clean`, THEN flip chezz's command column
  — not the other way around. Rationale, Zach's words: *"a jujitsu way
  of flipping built but not wired [beats] wired without built loud =
  noisy as aesthetic (whiney)."* Full writeup: `DESIGN-NOTES.md`
  2026-07-27. Queued to the Backlog for `/nightly-batch` to build.

- **scheduler: three 8-day-dark jobs renewed, not retired** (resolved
  2026-07-27, `/ideate`, human-directed: "Renew all three"). `rm
  ~/.local/share/<job>/expires_at` run live for `chezz-bug-sweep`,
  `vkv-inventory-bug-sweep`, `vkv-inventory-nightly-batch` — stamp
  re-writes on next run per `lib/sweep-loop-common.sh`'s existing
  design, no code change needed. All three had gone dark from burning
  their lease while blocked by the 2026-07-19/20 monthly-spend outage,
  not from being unwanted.

- **scheduler `EXPIRY_DAYS` dead-man switches: all 5 fired jobs
  dispositioned** (resolved 2026-07-25 11:00, human-directed in-session:
  "lets knock this out now"). `chezz-nightly-batch` and
  `home-assistant-nightly-batch` renewed by removing
  `~/.local/share/<job>/expires_at` (old values backed up; next dispatch
  re-stamps `now + 7d`) — witness: the create-if-missing block from
  `lib/sweep-loop-common.sh:192-196` run in isolation returned PROCEED
  with a 2026-08-01 stamp, and `scheduler status` for both no longer
  prints an EXPIRED line. Deliberately NOT renewed: `chezz-bug-sweep`
  (that tier is parked — `SWEEP_JOB_NAME=""` in `schedule/chezz.conf`)
  and `vkv-inventory-bug-sweep`/`vkv-inventory-nightly-batch`
  (dispatched under svc-vaporwave's own crontab now, a different
  account's call). Kept from the original 2026-07-25 entry: the real
  renewal is `rm ~/.local/share/<job>/expires_at`; the "bump
  `EXPIRY_DAYS` and re-run `bin/sync-crontab.sh`" text printed by
  `scheduler status` is wrong, and correcting it plus making the expired
  path loud in `scheduler glance`/`sweep` is queued as agent work in
  this repo's FOCUS.md backlog (2026-07-25 10:43 entry).
- **chezz nightly-batch wrapper still pointed at retired
  `.claude/FOCUS.md` — would have run unscoped once its expiry was
  renewed** (resolved 2026-07-25 11:00, human-directed same session).
  Both references in `~/.local/bin/chezz-nightly-batch-loop.sh` now read
  `.scheduler/FOCUS.md` (old copy backed up before editing; that file is
  under no version control, so this note is its history);
  `schedule/chezz.conf` gained `SCHEDULER_SUBDIR=".scheduler"` and the
  matching `BATCH_PROMPT` path in the same commit, and the two prompts
  were diffed byte-identical afterward so the mirror invariant holds.
  Witness: `scheduler status chezz` now reads chezz's real 271-line
  FOCUS.md and its 5 open questions instead of "no FOCUS.md found".
  Still open (a decision, not a blocker): `BATCH_SCRIPT` stays set and
  authoritative — whether to drop it and flip chezz onto
  `bin/scheduler-run` via `bin/sync-crontab.sh --apply` was left
  undecided.
- **crt Gallery installation architecture** (`RFP-GALLERY.md`) (2026-07-24)
  — decided: **A2 (per-unit Pi, autonomous/networked)**, not B (POTS +
  switcher) — per-unit character, failure isolation, and emergent
  message-propagation outweigh B's lower per-unit cost. B stays
  documented as a fallback, referenceable later ("B would do this more
  cleanly, B would need x/y/z") rather than deleted. `RFP-GALLERY.md`'s
  other three open questions are also answered there as of this pass:
  pure human-to-human audio (no AI-generated replies, light AI cleanup/
  filtering only), consent handled via recording-disclaimer signage +
  auto-delete bound to the show's run, and handset sourcing developed as
  parallel cheap/reproduction + aspirational-real-vintage tracks rather
  than picking one now. No build started; still no venue/budget attached
  — this closes the architecture decision, not the whole brief.
- **crt MIDI controller pass-through** (2026-07-24) — parked indefinitely,
  not just deprioritized: the VBoxSVC VM this depended on has been
  retired for several cycles now, so the old "waiting on a restart"
  framing no longer applies. See `PARKING-LOT.md`; revisit only if a
  replacement VM/host is ever stood up.
- **crt Benchy calibration print** (2026-07-24) — not needed; prints have
  printed fine without it. No calibration print required, closing out.
- **crt USB phone-interface module DAC** (2026-07-24) — stale entry; the
  DAC (https://www.amazon.com/dp/B08Y8CZB2S) arrived long ago and is
  already referenced elsewhere in the project's docs. No longer blocked
  on sourcing.
- **wtul ROADMAP #2 (AcoustID/Discogs metadata fallback) — confirmed
  stale, both blockers already cleared** (2026-07-24) — re-verified live
  on the wtul-batch machine: `fpcalc version 1.5.1` is installed (the
  `libchromaprint-tools` sudo-prompt blocker no longer applies), and
  `DISCOGS_TOKEN` is present in `~/.config/wtul/secrets.env` alongside
  `ACOUSTID_API_KEY`. Re: the "stale? check for token, plaintext
  unsecured" reply — confirmed plaintext (not encrypted), but
  `chmod 600`, owner-only, never committed to git (`.gitignore`d by
  location) — consistent with "fine for low stakes." Both keys were
  already wired into `lib/metadata_lookup.py` and live-verified per
  `.claude/FOCUS.md` item #2's Status note; this entry was just never
  pruned from BLOCKERS.md after that work landed.
- **aedile/vkv-inventory svc-vaporwave crontab** (2026-07-24) — a prior
  session's "confirmed working" claim was wrong; no crontab entry had
  ever actually been installed for that account. Fixed: home-dir access
  granted, both nightly-batch loops installed and confirmed via
  `crontab -l`. Full writeup: DESIGN-NOTES.md 2026-07-24
  "silently-orphaned finding"; handoff note at aedile's own
  `.claude/NEXT-STEPS.md` (local-only, gitignored there).
  - **Re-confirmed 2026-07-25 (agent, machine-append; note filed as a
    stray sibling bullet, attached to this entry in the 2026-07-25
    human-directed sweep):** this entry was CORRECT and was then
    contradicted by a worse record. Verified today with `sudo -u
    svc-vaporwave crontab -l`: the two lines this entry says were
    installed are installed, and both ran — vkv-inventory 04:00→04:05
    pushing `c2f7d9d`, aedile 03:00→03:06 pushing
    `aedile-nightly/2026-07-25` and PR #3. Meanwhile
    `schedule/_paced.conf` carried "confirmed 2026-07-24: no crontab
    exists there" on both project lines, which was never verified
    against the account and is false; it propagated into DESIGN-NOTES
    and became FABLE_REPORT.md's #1 ranked finding ("silently orphaned,
    zero dispatch for four days"). `_paced.conf` corrected in `d14a2f2`;
    DESIGN-NOTES still carries it. Both projects are now adopted into a
    scheduler-managed block in that account's crontab (`774f55a`, same
    times, no double dispatch — verified one line each). They stay at
    weight 0 in `_paced.conf` deliberately: re-enabling locally would
    double-dispatch against these live jobs. What WAS real: aedile's own
    `run.log` shows completed cycles on 07-20, 07-21, 07-25 only — a
    genuine 07-22→24 gap, cause being world-writable `~/.ssh` blocking
    `git push`, which aedile's own 07-25 run detected and fixed.
- **chezz + wtul: no deploy key needed, both already exist and work**
  (2026-07-24) — the "credential gap" diagnosis was wrong; both repos'
  `origin` already point at real, working deploy-key SSH aliases
  (verified with live test pushes). See DESIGN-NOTES.md 2026-07-24 for
  the correction and what actually explains stranded commits instead
  (account-wide spend-limit cutoff, not credentials).
- **crt OctoPrint reachability** (2026-07-20) — confirmed reachable at
  `192.168.0.43` during a live session with real dexter/VM network
  access.
- **crt VM-resident hardware-check job** (2026-07-20) — installed and
  verified live against real ALSA/tmux on crt-vm; reworked to a plain
  script (`bin/crt-vm-hardware-check.sh`, no LLM needed). Timer active.
- **crt barrel diameter + switch dims** (2026-07-20, marked resolved
  2026-07-24) — real-calipered; this note just never got marked
  resolved at the time. See `cad/CAD-BACKLOG.md`.
- **vkv-inventory tracker 403** (2026-07-20) — the org-owned Apps Script
  deployment couldn't be redeployed from the personal `dangerpine@gmail.com`
  account (Workspace policy); redeploying from
  `kreweofvaporwave@kreweofvaporwave.com` fixed it, confirmed live via curl.
  If clasp auth ever needs redoing, it must go through the workspace
  account, not the personal one.
- **wtul Spinitron key** (2026-07-20) — no station API access available;
  unblocked instead by scraping the public `spinitron.com/WTUL/` page the
  station's own "currently playing" widget already uses, no key needed.
  Shipped and merged to `main`.
- **wtul catalog write-back (ROADMAP #8)** (2026-07-20) — Apps Script
  deployed, `/exec` URL wired into `bin/wtul-rip`, live-verified against
  the real "LOCAL" sheet tab (including catching and fixing the
  documented Apps-Script-POST-response-can't-be-trusted gotcha via a
  re-GET confirm step). Shipped and merged to `main`. Two throwaway test
  rows ("TEST - wtul wiring check" / "TEST2 - write_row confirm check")
  are sitting in the LOCAL sheet from live-testing — safe to delete
  whenever convenient, not urgent.
- **crt payphone: no-real-payout framing** (2026-07-20) — confirmed: real
  coin mechanism, quarters as the test-phase token, token conversion as a
  parallel (not blocking) track, never deployed for real money. The
  earlier legal-check blocker doesn't apply under this framing. Folded
  into `RFP-PAYPHONE.md`.
- **crt video-cast-to-CRT: scope/priority call** (2026-07-20) — answered:
  source device is something else on the network, VLC-based, both
  shared-file and live-streaming delivery worth having, medium priority.
  Folded into a new `VIDEO-CAST.md`; technical protocol choice still open
  there, but the blocking scope decision is made.
- **crt RF power-on-TV trigger: wrong mechanism named** (2026-07-20) —
  corrected: should be IR, not RF (same blaster as the channel-switch
  idea, not a separate module). Folded into `PARKING-LOT.md`.
- **crt HDMI-to-RF multi-channel modulator: sourcing question** (2026-07-20)
  — answered: the modulator is already owned (daisy-chain multi-channel
  supported); the remaining blocker is housing/mounting/wiring
  integration, not sourcing. Folded into `PARKING-LOT.md`/
  `cad/CAD-BACKLOG.md`.
- **crt persona-channel rotary switch + IR blaster: parts sourced**
  (2026-07-20) — switch: https://www.amazon.com/dp/B088W8WMTB. IR LED:
  https://www.amazon.com/dp/B099ZJ6555. Folded into `PERSONA-CHANNEL.md`/
  `cad/CAD-BACKLOG.md`; CAD work still waits on real dimensions once each
  part is in hand.

- **2026-07-27 (realisateur `/cloture`): should every registered project
  get an uncommitted-file intake path, not just realisateur?** Concrete
  trigger: `wtul` had a manual PDF sitting uncommitted at repo root,
  invisible to `wtul-batch` (backlog-driven off FOCUS.md only, no
  repo-root scan) — resolved for that one file by hand this session
  (wtul `4bbf097`, pushed), but Zach's stated intent is standing: dropping
  an uncommitted file into a project's tree is a normal part of his
  workflow (committing isn't), and every project should have *some* way
  to fold that in rather than let it sit as permanent dirty-tree residue.
  Full writeup in realisateur's `.scheduler/FOCUS.md` same date. Not
  decided here: whether the shape is (a) copy realisateur's
  `nightly-batch.md` §2 inbox-scan to every project, (b) something
  lighter per-project (e.g. `closeout-lint.sh`'s dirty-tree FLAG growing
  teeth), or (c) something else. Route to `/ideate` or a scheduler
  steward pass to pick the shape — not a straight build.
  > Route to `/ideate` or scheduler steward pass for decision — shape (a/b/c) deferred to structured design session.
