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

## vkv-inventory
- **Tracker `/exec` returns HTTP 403 Access Denied** (confirmed live
  2026-07-19). `appsscript.json` already declares `access:
  ANYONE_ANONYMOUS`, so this is the deployment's actual access setting
  having drifted from the manifest, not a code problem. Fix: Apps Script
  editor (`https://script.google.com/d/1fHrPbq6XNhvHWhEDCIWR8LHChJqKSlr29SXKuSUXMimnZnR-LeVAGJfQ/edit`)
  → Deploy → Manage deployments → edit the `AKfycbxBBxoknH6...` deployment
  → set "Who has access" to Anyone → Save. Then `tools/deploy.sh` to push
  current code on top and verify.

## wtul
- **Spinitron wiring needs a real API key.** Built and unit-tested
  (`SPINITRON_API_KEY` env var, silent no-op until set) but never called
  against the live API, and the branch (`spinitron-priority-matching`)
  isn't merged into the real `~/Documents/wtul` working copy yet either.
  Get the key from Spinitron → Settings → API for the station, decide
  where it lives (env var vs. a gitignored config file — flagged as an
  open choice in `.claude/QUESTIONS.md`), and merge the branch in.
