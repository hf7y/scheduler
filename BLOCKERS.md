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
actually moves it down into `## chezz

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
- **Gemini sprite pipeline needs your explicit sign-off -- no unattended
  run may add it on its own** (filed 2026-07-25 ~21:00, chezz nightly,
  machine-append; witness: tracker report 2026-07-17T07:25:16.315Z +
  DESIGN-NOTES.md's standing new-external-dependency gate). It's a new
  external API dependency (credentials, cost, attack surface). A yes/no
  -- or "take the custom fairy-piece font track instead, which has no
  such gate" -- is all that's needed; until then the report stays open
  by design, not by neglect.
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

## Recently resolved` or deletes it. Doing
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

## scheduler

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

## vkv-inventory

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

- **Five yes/no calls from the 2026-07-26 strategy audit — each is one
  `> ` reply, none blocks the others** (filed 2026-07-26, realisateur
  interactive strategy session, machine-append; witness:
  `realisateur/PLAYBOOK.md` @ `436f774` + the three-agent audit it
  records). Full rationale lives in PLAYBOOK.md; these are only the
  parts that need YOU:
  1. **Bless `PLAYBOOK.md` as standing doctrine** (or reply with edits)
     — it now governs build-vs-import-vs-retire allocation the way
     UNIVERSE.md governs laws.
     >
  2. **Commit-message PreToolUse hook: install at user level**
     (`~/.claude/settings.json`, covers every project) rather than
     per-repo? The build itself you already approved 2026-07-25
     (narrow deny-with-message form); this is only the
     where-it-lives call the design notes said to confirm.
     >
  3. **Import swaps — approve any subset:** (a) symlinks replace
     `scheduler pacing deploy`/drift-detection (also fixes the LIVE
     drift found in `usage-paced-runner.sh`, the script cron runs every
     5 min); (b) `ccusage` replaces `token-usage.sh`'s parsing core;
     (c) `gitleaks` replaces hygiene-lint's hand regexes (harness
     stays); (d) restic/rsnapshot under `gardien.py`'s storage layer
     when it unparks.
     > Approved (a), (b), (c) — 2026-07-26, interactive /ideate in the
     > scheduler repo, Zach via AskUserQuestion. (d) restic/rsnapshot
     > stays deferred until gardien actually unparks. Note: (a) is also
     > the sequencing prerequisite for the axis-1 decision (paced runner
     > dispatching from a committed conf) — see scheduler DESIGN-NOTES.md
     > 2026-07-26 /ideate entry. Queued as a [batch] item in scheduler's
     > FOCUS.md Backlog same pass.
  4. **Catabolic worklist — approve retiring ~1,000 already-labeled-
     superseded lines** (morning-report ×2, build-services-view +
     `services/`, `incubation-audit.sh`, overnight-dev ×2, the two
     162-line loop-script forks, sync-crontab's dead auto-stagger), one
     retirement per pass, each commit naming what retires it.
     > Approved — 2026-07-26, interactive /ideate in the scheduler repo,
     > Zach via AskUserQuestion. One retirement per pass, each commit
     > naming what it retires, exactly as filed. The scheduler loop-fork
     > retirement is gated behind the axis-1 (a) `scheduler-run` flip
     > (see scheduler FOCUS.md axis 1, decided same pass). Queued as a
     > [batch] item in scheduler's FOCUS.md Backlog same pass.
  5. **Standing re-admission policy:** as each parked making-project
     declares its stability milestone (jobs queued 2026-07-26 in
     groc-mangr/nine-speakers/sequestria/vim-arcade), re-enable it at
     weight 1–2 with no further per-project ask — yes turns four future
     decisions into ordinary queue work. (vkv-inventory stays `0`
     regardless: svc-vaporwave crontab owns its dispatch.)
     >
  - 2026-07-26 (realisateur nightly-batch, machine-append; witness: this
    run's own dispatch prompt + scheduler `git diff` of the collector's
    `--consume` rewrite): tonight's run was handed five EMPTY replies to
    the five calls above — a collector bug consumed the bare `>` answer
    slots as if they were answers and deleted them from this file. The
    slots are restored, nothing was treated as approved, and all five
    calls still await you. Bug fixed in `bin/collect-feedback.sh`
    (scheduler `bb5c762`): a bare `>` line is now kept as an un-answered
    slot, same as the `(answer inline here)` placeholder.

## Recently resolved

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
