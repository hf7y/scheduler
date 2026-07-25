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
a full day and was believed over it.

Each project's heading must be exactly `## <PROJECT_KEY>` (matches
`schedule/<project>.conf`'s `PROJECT`/`PROJECT_KEY`) — that's what a
run's own `collect-feedback.sh --section` call matches against, so it
only ever sees its own section, never another project's.

## scheduler
- **5 of 14 jobs' `EXPIRY_DAYS` dead-man switches have fired — renewing
  them is your call, not an unattended run's** (appended 2026-07-25 by a
  realisateur session; witness: scanned `~/.local/share/*/expires_at`
  against `date -Is`, and each job's own `sweep.log`). Expired:
  `chezz-nightly-batch` (2026-07-25T01:00), `chezz-bug-sweep`
  (2026-07-23T22:44), `home-assistant-nightly-batch` (2026-07-25T01:30),
  `vkv-inventory-bug-sweep` (2026-07-24T13:30),
  `vkv-inventory-nightly-batch` (2026-07-25T02:32). An expired job clones
  its repo and then `exit 0`s without running claude, so `chezz` and
  `home-assistant` have been quietly no-opping every paced tick today
  (`chezz` at 01:21 and 08:55, `home-assistant` at 08:55). This is here
  rather than in FOCUS.md because the switch exists so that unattended
  work can't run indefinitely unsupervised — an agent renewing its own
  expiry defeats the mechanism. **The renewal actually is `rm
  ~/.local/share/<job>/expires_at`** (the next run re-stamps `now +
  EXPIRY_DAYS`); the "bump `EXPIRY_DAYS` and re-run
  `bin/sync-crontab.sh`" text printed by `scheduler status` is wrong —
  nothing in `bin/`/`lib/` ever writes that file except a
  create-if-missing at `lib/sweep-loop-common.sh:192-194`. Correcting
  that text, plus making the expired path loud and visible in `scheduler
  glance`/`sweep`, is queued in this repo's FOCUS.md backlog
  (2026-07-25 10:43 entry) as agent work.
  - **RESOLVED 2026-07-25 11:00 for `chezz-nightly-batch` and
    `home-assistant-nightly-batch` only** (human-directed in the same
    session: "lets knock this out now"). Both `expires_at` files removed
    after backing up their old values; next dispatch re-stamps `now + 7d`.
    Witness: the create-if-missing block from
    `lib/sweep-loop-common.sh:192-196` run in isolation against a temp
    file returned PROCEED with a 2026-08-01 stamp, and `scheduler status`
    for both projects no longer prints an EXPIRED line. **Still expired,
    deliberately not renewed:** `chezz-bug-sweep` (that tier is parked —
    `SWEEP_JOB_NAME=""` in `schedule/chezz.conf`) and
    `vkv-inventory-bug-sweep`/`vkv-inventory-nightly-batch` (dispatched
    under svc-vaporwave's own crontab now, a different account's call).
- **`~/.local/bin/chezz-nightly-batch-loop.sh`'s `PROMPT` still says
  "Read .claude/FOCUS.md FIRST", which no longer exists** (appended
  2026-07-25, same session; witness: read the wrapper and `ls
  chezz/.claude chezz/.scheduler`). chezz moved its scope file to
  `.scheduler/FOCUS.md` on 2026-07-24; that wrapper is still
  authoritative (`BATCH_SCRIPT` is set in `schedule/chezz.conf`), so
  chezz's nightly batch would run **unscoped** once its expiry above is
  renewed. Needs a human because editing `~/.local/bin` wrappers is
  explicitly outside a batch's scope (roadmap item 1). Two ways: edit the
  one path in the wrapper, or drop `BATCH_SCRIPT` from `chezz.conf` and
  run `bin/sync-crontab.sh --apply` to flip chezz onto
  `bin/scheduler-run` (the conf's own `BATCH_PROMPT` is being corrected
  as part of the queued FOCUS.md item, so the flip lands the right path).
  - **RESOLVED 2026-07-25 11:00, human-directed same session** — took the
    first option: both `.claude/FOCUS.md` references in
    `~/.local/bin/chezz-nightly-batch-loop.sh` now read
    `.scheduler/FOCUS.md` (old copy backed up before editing; that file is
    under no version control, so this note is its history). `BATCH_SCRIPT`
    stays set and authoritative — nothing was flipped onto
    `bin/scheduler-run`, that decision is still open. `schedule/chezz.conf`
    gained `SCHEDULER_SUBDIR=".scheduler"` and the matching `BATCH_PROMPT`
    path in the same commit, and the two prompts were diffed
    byte-identical afterward so the mirror invariant holds. Witness:
    `scheduler status chezz` now reads chezz's real 271-line FOCUS.md and
    its 5 open questions instead of "no FOCUS.md found".

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
- **`.claude/QUESTIONS.md` and `.claude/FOCUS.md` sensitive-file write
  block — DECISION REVISED 2026-07-24, same session.** First call was a
  permission rule (see settings.local.json allow entries added there,
  now superseded — safe to leave, harmless, or strip on the migration
  below). **Revised call:** migrate wtul onto the `.scheduler/` subdir
  layout instead (same convention `scheduler` and `aedile` already use)
  — sidesteps the `.claude/*.md` sensitive-file gate entirely rather
  than special-casing around it, and gets wtul onto the same design as
  every other project long-term, per Zach's explicit preference.
  **Not done — filed for an async pass, not completed live** (a partial
  `git mv` was started and reverted clean this session rather than leave
  it half-migrated). Real scope, scouted but not executed: `git mv
  .claude/{FOCUS,QUESTIONS}.md .scheduler/`; `schedule/wtul.conf` needs
  `SCHEDULER_SUBDIR=".scheduler"` (same as `aedile.conf`); re-run
  `bin/sync-crontab.sh --apply` to regenerate the `focus/wtul.md` /
  `questions/wtul.md` symlinks at their new target; `.claude/commands/
  wtul-batch.md` hardcodes `.claude/QUESTIONS.md`/`.claude/FOCUS.md` in
  at least 8 places (steps 0a, 1, 3, 5, 6) and must be updated to
  `.scheduler/...` or the batch run's own instructions break; `lib/
  spinitron.py`, `ROADMAP.md`, and `LIVE-TEST-DEBRIEF-2026-07-24.md`
  also reference the old path in comments/docs, lower-priority but worth
  sweeping in the same pass; once migrated, the settings.local.json
  allow rules and this whole entry can move to Recently resolved.
  Queued backlog drafted in `~/reports/wtul/2026-07-24.md` (runs 10 and
  11) still needs manual filing into `QUESTIONS.md`/`.scheduler/
  QUESTIONS.md` in the meantime if a run hits this before the migration
  lands.

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
  earpiece/mouthpiece cup diameters, weight) — not blocking, per Zach's
  steer: educated-guess values (handset "feels standard") are in
  `cad/params.scad`, clearly marked GUESS, and `wall_hook.scad` derives
  from them. `cad/HANDSET-MEASUREMENTS.md` has an ASCII diagram of where
  to caliper each GUESS value whenever convenient. **Update 2026-07-24**:
  full part printed; only aesthetic work remains on the print — function
  exists. 3-pin switch design writeup (hard-kill vs. software-mute vs.
  GPIO) **moved to crt's own `.claude/FOCUS.md` ranked backlog item 7,
  2026-07-24** — this is `[batch]`-tagged doable-unattended work
  (a design-options doc, no hardware needed), so it belongs in the file
  crt's own `/nightly-batch` actually reads, not here. **Process
  correction, same day:** this item was first filed here only, which was
  wrong — BLOCKERS.md is human-only blockers, nothing consumes it as a
  work queue for any project (crt's `/nightly-batch` scope is explicitly
  `.claude/FOCUS.md`'s batch-tagged items only), so it would have sat
  here indefinitely. Left this cross-reference so a future BLOCKERS.md
  read doesn't re-surface it as if still homeless.

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

## Recently resolved

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
- **SUPERSEDED 2026-07-25 (agent, machine-append):** this entry was
  CORRECT and was then contradicted by a worse record. Verified today
  with `sudo -u svc-vaporwave crontab -l`: the two lines this entry says
  were installed are installed, and both ran — vkv-inventory 04:00→04:05
  pushing `c2f7d9d`, aedile 03:00→03:06 pushing `aedile-nightly/2026-07-25`
  and PR #3. Meanwhile `schedule/_paced.conf` carried "confirmed
  2026-07-24: no crontab exists there" on both project lines, which was
  never verified against the account and is false; it propagated into
  DESIGN-NOTES and became FABLE_REPORT.md's #1 ranked finding ("silently
  orphaned, zero dispatch for four days"). `_paced.conf` corrected in
  `d14a2f2`; DESIGN-NOTES still carries it. Both projects are now adopted
  into a scheduler-managed block in that account's crontab (`774f55a`,
  same times, no double dispatch — verified one line each). They stay at
  weight 0 in `_paced.conf` deliberately: re-enabling locally would
  double-dispatch against these live jobs. What WAS real: aedile's own
  `run.log` shows completed cycles on 07-20, 07-21, 07-25 only — a
  genuine 07-22→24 gap, cause being world-writable `~/.ssh` blocking
  `git push`, which aedile's own 07-25 run detected and fixed.
- **aedile/vkv-inventory svc-vaporwave crontab** (2026-07-24) — a prior
  session's "confirmed working" claim was wrong; no crontab entry had
  ever actually been installed for that account. Fixed: home-dir access
  granted, both nightly-batch loops installed and confirmed via
  `crontab -l`. Full writeup: DESIGN-NOTES.md 2026-07-24
  "silently-orphaned finding"; handoff note at aedile's own
  `.claude/NEXT-STEPS.md` (local-only, gitignored there).
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
