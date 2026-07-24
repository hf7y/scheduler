# Questions for the user

Running log for this directory itself (the scheduler design/tooling, not
any one project's batch job). This project isn't itself under an
automated nightly/batch job -- it's maintained by hand -- so entries here
come from whoever's working on it directly, human or agent, whenever
something bigger than a routine edit comes up. Clear an entry by deleting
its line once you've actually read and dealt with it.

- **2026-07-23 (via /ideate): account-segregation tooling.** Right now
  zach-personal vs svc-vaporwave usage is split only by reactive
  account-hopping (log into whichever hasn't capped — currently vaporwave,
  for crt dev). This muddies any burndown/pacing estimate and means the
  vision-clearing jobs (scheduler, realisateur) draw from whichever
  account you're camped on. Decide + build the deliberate-split mechanism:
  which jobs pin to which account, how `usage-gate.sh` probes each account
  (it reads only the currently-logged-in creds today), and whether
  realisateur is allowed to run under vaporwave for vision work or must
  stay on zach. User flagged this as a discipline gap to address soon
  (2026-07-23 "tonight"). See DESIGN-NOTES.md 2026-07-23 vision-burndown
  entry for the full analysis.
