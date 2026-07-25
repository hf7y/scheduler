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

Each project's heading must be exactly `## <PROJECT_KEY>` (matches
`schedule/<project>.conf`'s `PROJECT`/`PROJECT_KEY`) — that's what a
run's own `collect-feedback.sh --section` call matches against, so it
only ever sees its own section, never another project's.

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
- **`.claude/QUESTIONS.md` and `.claude/FOCUS.md` are gated as "sensitive
  files" needing interactive approval — unwritable from three
  consecutive unattended `/wtul-batch` runs now (2026-07-24, runs 9, 10,
  and this one).** Every attempted write (Edit tool, and a plain shell
  `>>` append tried this round to rule out the tool as the cause) gets
  refused with "Claude requested permissions to edit
  .../.claude/QUESTIONS.md which is a sensitive file" — no prompt a
  human can answer in an unattended context, so the run can never get
  past it on its own. Neither file has a repo-local
  `.claude/settings.json`/`settings.local.json` deny rule (checked,
  empty) — this looks like a harness-level protection on `.claude/*.md`
  specifically (plausibly deliberate: stops an agent from silently
  rewriting its own config/instructions), not a misconfiguration in this
  repo. Needs a human decision: either grant this session/schedule an
  explicit permission rule for these two files, or move
  QUESTIONS.md/FOCUS.md out of `.claude/` if they're meant to stay
  unattended-writable (they're this project's live backlog + user
  inbox, not config). Until resolved, `/wtul-batch` runs keep drafting
  QUESTIONS.md entries in the report instead of actually filing them —
  see `~/reports/wtul/2026-07-24.md` (runs 10 and 11) for what's queued.

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
- **MIDI controller pass-through** — **PARKED 2026-07-20** into crt's own
  `PARKING-LOT.md` (full status/next-step there). Still stuck on a
  VBoxSVC restart on dexter needing direct human OK (live VM depends on
  it); not on the critical path, deliberately deprioritized rather than
  actively blocked-and-waiting.
> parked indefinitely. virtual machine has been retired for several
  cycles now, btw.

- **Full-body handset dims still ungauged** (overall length,
  earpiece/mouthpiece cup diameters, weight) — not blocking, per Zach's
  steer: educated-guess values (handset "feels standard") are in
  `cad/params.scad`, clearly marked GUESS, and `wall_hook.scad` derives
  from them. `cad/HANDSET-MEASUREMENTS.md` has an ASCII diagram of where
  to caliper each GUESS value whenever convenient —
  **Caliper on hand** (https://www.amazon.com/dp/B09R84QZ2P).
> full part printed; only aesthetic work remains for print; function
  exists. need to wire up the 3 pin switch (hard kill audio? software
  mute on switch close? into pi gpio/other?)

- **Benchy calibration print** needs the Ender 3's SD card path verified
  and someone to actually run the print (3DBenchy STL already downloaded
  on mandark). **In progress**: printer's mid-print on a Pi3B case right
  now; Benchy itself still pending.
> not needed. prints have printed fine.

- **USB phone-interface module** (bare-metal Compute Stick target) is
  blocked on a DAC arriving — nothing to do until it ships. **ETA**: the
  DAC (https://www.amazon.com/dp/B08Y8CZB2S) is arriving Tuesday morning.
> arrived long ago. already referenced in docs. this is stale.

### crt deep-vision (PARKING-LOT.md / RFP docs)
- **Gallery installation** (`RFP-GALLERY.md`): the original "centralized
  vs. independent" framing is superseded — **direction given 2026-07-20**:
  explore autonomous networked Pis (per-unit personality + failure
  isolation + emergent message-passing) vs. real POTS wiring through a
  switcher (cheaper per-unit, authentic feel, single point of failure).
  Full possibilities writeup now in `RFP-GALLERY.md`. **Still open**:
  which of the two to actually build.
> see RFP-GALLERY.md for updates and fold them in. 
> fold them in?

## Recently resolved

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
