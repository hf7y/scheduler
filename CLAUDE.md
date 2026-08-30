# CLAUDE.md

## Push permission (2026-08-30, reaped: main is a protected branch)

`main` is protected (`required_status_checks: ["suites"]`,
`enforce_admins: true`), so a direct push is rejected for everyone —
admins and this repo's own automation included. Open a pull request;
never commit to local `main`. The 2026-07-22 grant said the opposite;
realisateur reaped the identical line on 2026-08-14 after it cost 5
failed runs and 15 stranded salvage branches.



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
