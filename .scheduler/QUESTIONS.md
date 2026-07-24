# Questions for the user

Running log for this directory itself (the scheduler design/tooling, not
any one project's batch job). This project isn't itself under an
automated nightly/batch job -- it's maintained by hand -- so entries here
come from whoever's working on it directly, human or agent, whenever
something bigger than a routine edit comes up. Clear an entry by deleting
its line once you've actually read and dealt with it.

- **2026-07-24 (via /ideate): verify svc-vaporwave cron credential
  refresh.** Under the new account model (primary = Max, always logged
  in; svc-vaporwave = nonprofit only, for its batch jobs + nonprofit
  interactive), primary's CLI creds stay fresh so personal jobs stop
  hitting "Not logged in." Confirm the same holds for svc-vaporwave:
  does your nonprofit *interactive* use actually refresh the SAME creds
  its cron jobs (aedile, vkv-inventory) read, or can that account still
  lapse mid-week? If it can lapse, that account needs its own refresh
  ritual. See DESIGN-NOTES.md 2026-07-24 entry.
