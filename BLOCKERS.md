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
	Note: dangerpine@gmail.com cannot deploy from browser (and presumably also in cli). kreweofvaporwave@kreweofvaporwave.com can deploy. Could be a workspace thing since dangerpine is private. 
	Who has access was already set to "Anyone" but has now been redeployed at the AKfycbx deployment again as of 22:41. Deploying the 4:05pm version 27. 
%%NOTE confirmed live 2026-07-20 00:xx via curl: HTTP 200, ?scope=sweep-status returns non-HTML ("null") -- the redeploy from kreweofvaporwave@kreweofvaporwave.com fixed it. Verify sweep-status posting works end to end and resume normal tracker operation. Future deploys from this account must go through the workspace account, not dangerpine@gmail.com -- note this in tools/deploy.sh or README if clasp auth ever needs redoing.

## wtul
- **Spinitron wiring needs a real API key.** Built and unit-tested
  (`SPINITRON_API_KEY` env var, silent no-op until set) but never called
  against the live API, and the branch (`spinitron-priority-matching`)
  isn't merged into the real `~/Documents/wtul` working copy yet either.
  Get the key from Spinitron → Settings → API for the station, decide
  where it lives (env var vs. a gitignored config file — flagged as an
  open choice in `.claude/QUESTIONS.md`), and merge the branch in.
	I will continue looking for API access. Right now I have web access to my show (recurring) https://spinitron.com/WTUL/show/309405/Local. The WTUL website also uses spinitron to show currently playing. The radio stream itself could be compared against audio being ripped to see if recent plays match. Confirming I don't have access to API. Would need to social engineer access from the station managers.
%%QUESTION no station API key in hand and getting one needs going through station managers (not guaranteed). Two alternatives exist without one: (1) scrape https://spinitron.com/WTUL/show/309405/Local for the user's own recurring show only -- narrower than the full station feed the current code expects, or (2) compare ripped audio against the station's public "currently playing" page instead of the API. Don't build either unprompted -- this is a real scope/approach fork (station-wide vs. own-show-only, API vs. scrape vs. audio-compare), needs a human pick before more code goes in on top of the current API-shaped design.
