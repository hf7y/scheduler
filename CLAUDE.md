# CLAUDE.md

## Landing work (2026-08-30, reaped: this granted what the remote refuses, #417)

Open a pull request and let the checks land it; never commit to local `main`.
Direct pushes are refused here for everyone, this repo's own automation
included. The 2026-07-22 grant this replaces licensed exactly what the server
already rejected, so agents found out by failing. What gates a merge is not
restated here, because it moves — ask:

```
gh api repos/hf7y/scheduler/branches/main/protection \
  --jq '{admins: .enforce_admins.enabled, checks: .required_status_checks.contexts}'
```



## Ecosystem protocols

When a change reaches outside this repo, three verbs are the interface. Each
prints its own contract; none of it is restated here, and none of it is a
checklist to recite from memory.

- `notify-senechal <door> <field>=<value>` — file a crontab, device or
  footprint change on senechal's registry. Standing policy for any change to
  crontabs, dotfiles, systemd units or WM config. `--doors` lists the doors.
- `check-project-busy <project>` — before writing DIRECTLY into another
  project's files. Front-door writes carry their own regulator.
- `consulte` — read the estate's own prose.

`discipline` and `BUILD-DISCIPLINE.md` were deleted by hf7y/realisateur#687:
the rows a mechanism already enforced are enforced by that mechanism, and the
rest were unenforced prose. Do not reinstate either here.
