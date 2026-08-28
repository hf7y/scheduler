# CLAUDE.md

## Push permission (2026-07-22, human-directed)

Claude may push committed changes directly to `origin/main` without
asking each time, for ordinary work in this repo. Flag every such push in
the next report/summary (what was pushed, why, and how to revert it —
`git revert <sha>`). This does not license skipping review of what goes
into a commit in the first place, only the push step itself.



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
