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

## wtul
- **ROADMAP #2 (AcoustID/Discogs metadata fallback) needs two self-serve
  keys** an unattended run can't obtain: an AcoustID API key
  (acoustid.org) and a Discogs personal access token. Both free, both a
  five-minute signup. Once you have them, decide where they live (same
  question #1's Spinitron key already raised — env var vs. gitignored
  config file) and drop them in; the next `/wtul-batch` can wire the
  fallback logic itself once the keys exist.
- **ROADMAP #8 (catalog spreadsheet write-back) needs a deployed Apps
  Script URL**, not Cloud Console credentials anymore (revised
  2026-07-20 — OAuth/service-account was overkill). The script itself is
  written and checked in at `wtul/gas/catalog-writeback.gs.js` — paste it
  into the sheet's own Extensions > Apps Script, Deploy > New deployment >
  Web app (execute as Me, access Anyone), then send the `/exec` URL back.
  Same "which account" gotcha vkv-inventory hit below may apply if this
  sheet is workspace-owned rather than personal — deploy from whichever
  account actually owns/edits it.

## crt
Moved here 2026-07-20 from crt's own `FOCUS.md` "Deferred" list — these are
all genuinely hands-on-hardware items an unattended run can never clear,
so they belong here rather than cluttering that file's code-shaped scope.
- **MIDI controller pass-through stuck.** Root cause found (Windows had
  the MiniLab's MIDI interface disabled, fixed via `Enable-PnpDevice`),
  but `VBoxManage usbattach` still fails ("busy with a previous request")
  even after that fix and a full VM power-cycle — needs a VBoxSVC/
  VirtualBox host service restart on dexter (a process-kill action an
  unattended run won't take on its own).
- **Physical hookswitch build needs real measurements.** `cad/params.scad`
  ships generic placeholder dimensions — measure the actual handset
  barrel diameter and the actual microswitch's body/hole spacing, edit
  `params.scad` (or hand the numbers to a session and it'll do the edit),
  then `cad/export_stl.sh` + print + assemble.
- **OctoPrint** needs hands on the spare Raspberry Pi (OctoPi SD already
  flashed on mandark, just needs to be put in the Pi and powered up).
- **Benchy calibration print** needs the Ender 3's SD card path verified
  and someone to actually run the print (3DBenchy STL already downloaded
  on mandark).
- **USB phone-interface module** (bare-metal Compute Stick target) is
  blocked on a DAC arriving — nothing to do until it ships.
- **VM-resident hardware-check job isn't installed.** Written this
  session (`VM-JOBS.md`, `systemd/crt-vm-hardware-check.{service,timer}`)
  but needs the manual `systemctl enable --now` steps run ON crt-vm —
  exact commands are in `VM-JOBS.md`.

### crt deep-vision (PARKING-LOT.md / RFP docs) — added 2026-07-20
Two different kinds of blocker here, worth telling apart: pure decisions
(answerable from anywhere, right now, no hardware/on-site access needed
at all) vs. sourcing calls (need a purchase, but the *decision* and the
*ordering* can both happen remotely — it's only installing/using the part
that needs on-site hands, and isn't listed again here since it'd just
duplicate the hardware items above once something ships).

**Pure decisions — answerable right now:**
- **Gallery installation** (`RFP-GALLERY.md`): centralized backend vs.
  fully independent units. Named in that doc as the single
  highest-leverage call — it changes the entire bill of materials, and
  nothing else about that concept is worth planning until it's made.
- **Payphone installation** (`RFP-PAYPHONE.md`): confirm the no-real-payout
  framing (tokens/print-outs/bonus time instead of coin return), or say
  a real-payout version is actually wanted — if the latter, that doc is
  explicit it needs real legal advice for the specific venue before any
  more work happens on it.
- **Video-cast-to-CRT**: not designed at all yet (`DEVELOPMENT-
  WORKFLOW.md` just named the shape of the problem). Needs a scope/
  priority call before it's even a real backlog item — what source
  device, how urgent relative to everything else.

**Sourcing calls — a purchase decision, doable remotely, but nothing to
build until the part is chosen/ordered:**
- **Persona-channel rotary switch** (`PERSONA-CHANNEL.md`): mechanism is
  decided (a real detented switch, not a servo/LED display) — needs an
  actual commodity part picked before the faceplate CAD can be drawn.
- **RF power-on-TV trigger module** (`PARKING-LOT.md`'s "lift the handset
  powers the TV on" idea) — needs an RF transmitter module chosen/sourced;
  no design work possible before that.
- **HDMI-to-RF multi-channel modulator** (`PARKING-LOT.md`'s multi-persona
  TV-channel idea) — same, needs real hardware sourced first.
- **IR blaster** (`cad/ir_blaster_mount.scad`, already stubbed) — needs an
  actual IR LED in hand and the real TV sensor position measured; the
  mount geometry is pure placeholder until then.

Currently no other open blockers. Recently resolved:
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
