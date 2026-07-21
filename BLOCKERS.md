# Blockers — cross-project, human-owned

One place to see every "this needs YOU, not an unattended run" item across
every registered project, and to answer them without opening a chat
session. Edit this file directly (vim mappings from `~/.vimrc` work here
too: `<leader>a/b/q/n/y/r`). A `%%TAG` line left under a project's `##`
heading is picked up by THAT project's next scheduled run and then
removed automatically (see `docs/feedback-tags.md`) — the blocker
description itself stays until you delete it by hand once it's actually
resolved.

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
- **ROADMAP #2 (AcoustID/Discogs metadata fallback) — AcoustID done,
  Discogs still pending.** AcoustID key obtained and wired 2026-07-20
  (`lib/metadata_lookup.py`, offered as a suggestion at the `fix <discid>`
  prompt). Still needs: **a Discogs personal access token** (free,
  self-serve at discogs.com) for the fallback path, built and tested but
  a silent no-op without it; and **`fpcalc`** (Chromaprint) actually
  installed so a real fingerprint match can be live-verified —
  `sudo apt install -y libchromaprint-tools` needs an interactive sudo
  prompt no unattended run can supply.
  > Discogs token hopefully: user "localshow" : cHvFpfwlzgMgELLGiBqGkcaorBLehdunZEmwGaSE
  > libchromaprint-tools installed = CLEARED

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
- **MIDI controller pass-through stuck.** Root cause found (Windows had
  the MiniLab's MIDI interface disabled, fixed via `Enable-PnpDevice`),
  but `VBoxManage usbattach` still fails ("busy with a previous request")
  even after that fix and a full VM power-cycle — needs a VBoxSVC/
  VirtualBox host service restart on dexter (a process-kill action an
  unattended run won't take on its own). **Direction**: develop it
  dexter/Windows-side for now, with the explicit intent it merges back
  into the bare-metal Linux distro eventually — keep it portable, don't
  lean on anything Windows-only.
  > Still accurate as of jul 20, 13:00. 

- **Physical hookswitch build needs real measurements.** `cad/params.scad`
  ships generic placeholder dimensions — measure the actual handset
  barrel diameter and the actual microswitch's body/hole spacing, edit
  `params.scad` (or hand the numbers to a session and it'll do the edit),
  then `cad/export_stl.sh` + print + assemble. **Caliper on hand**
  (https://www.amazon.com/dp/B09R84QZ2P) — measurements not taken yet.
  > attempt to make an educated guess based on other information. handset
  > feels "standard" in size. perhaps an existing stl of a similar phone
  > handset can be used for development while exact measurements await.
  > also make a note of where exactly measurments should be taken, with
  > graphical indications, to make it easy for Zach to report requested
  > measurements. but develop this based on educated guess; don't let
  > missing exact measurements block.

- **OctoPrint** needs hands on the spare Raspberry Pi (OctoPi SD already
  flashed on mandark, just needs to be put in the Pi and powered up).
  **Already on the network** — check next time mandark joins.

- **Benchy calibration print** needs the Ender 3's SD card path verified
  and someone to actually run the print (3DBenchy STL already downloaded
  on mandark). **In progress**: printer's mid-print on a Pi3B case right
  now; Benchy itself still pending.

- **USB phone-interface module** (bare-metal Compute Stick target) is
  blocked on a DAC arriving — nothing to do until it ships. **ETA**: the
  DAC (https://www.amazon.com/dp/B08Y8CZB2S) is arriving Tuesday morning.

- **VM-resident hardware-check job isn't installed.** Written this
  session (`VM-JOBS.md`, `systemd/crt-vm-hardware-check.{service,timer}`)
  but needs the manual `systemctl enable --now` steps run ON crt-vm —
  exact commands are in `VM-JOBS.md`. No update yet.

### crt deep-vision (PARKING-LOT.md / RFP docs)
- **Gallery installation** (`RFP-GALLERY.md`): the original "centralized
  vs. independent" framing is superseded — **direction given 2026-07-20**:
  explore autonomous networked Pis (per-unit personality + failure
  isolation + emergent message-passing) vs. real POTS wiring through a
  switcher (cheaper per-unit, authentic feel, single point of failure).
  Full possibilities writeup now in `RFP-GALLERY.md`. **Still open**:
  which of the two to actually build.
  > see RFP-GALLERY.md for updates and fold them in.

## Recently resolved

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
