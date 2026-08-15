# Blockers — retired 2026-08-15, migrated to GitHub issues

**This was the cross-project, human-owned blocker board**: one file where
every registered project's "this needs YOU, not an unattended run" items
sat under a per-project `##` heading, answered inline with `> ` replies.
2,080 lines at retirement.

It is retired by [#66](https://github.com/hf7y/scheduler/issues/66)
(2026-08-07), which killed every markdown feedback surface estate-wide.
The sweep across the other repos is
[hf7y/realisateur#230](https://github.com/hf7y/realisateur/issues/230).
**Do not append here — file an issue on the owning project's repo.**
`bin/blockers-append.sh` and the rest of the readers/writers are retired
by [#193](https://github.com/hf7y/scheduler/issues/193).

Why it had to go, in one line from #66: `BLOCKERS.md` was not
documentation of the freeze, it *was* the freeze — one uncommitted copy,
dirtied by the engine's own `--consume`, blocked vim-arcade's clone from
pulling for seven commits ([#29](https://github.com/hf7y/scheduler/issues/29),
[#61](https://github.com/hf7y/scheduler/issues/61)).

## Where the open items went

Every item was re-derived against the owning repo's code, `git log` and
issues rather than trusted — the file's own claims were stale by
construction.

| Was, and under which `##` heading | Now |
|---|---|
| `scheduler` — `installe` must adopt a verb build before a dev clone can leave mandark | already open as [hf7y/realisateur#181](https://github.com/hf7y/realisateur/issues/181) |
| `scheduler` — retire `lib/sweep-loop-common.sh` (Zach, "urgent", 2026-08-07) | [#192](https://github.com/hf7y/scheduler/issues/192) |
| `aedile` — svc-vaporwave's `gh` PAT expires 2027-07-20, over-scoped, registered nowhere | [hf7y/senechal#279](https://github.com/hf7y/senechal/issues/279) (Zach's own inline answer routed it to senechal) |
| `crt` — the 3-pin hookswitch decision | [hf7y/crt#37](https://github.com/hf7y/crt/issues/37) |
| `crt` — dexter has none of the four ecosystem guard commands | [hf7y/realisateur#281](https://github.com/hf7y/realisateur/issues/281) |
| `realisateur` — "a guard that fails safe but never clears" as a BUILD-DISCIPLINE row | [hf7y/realisateur#283](https://github.com/hf7y/realisateur/issues/283) |
| `realisateur` — widen the one-source-of-truth row beyond config | [hf7y/realisateur#284](https://github.com/hf7y/realisateur/issues/284) |
| `realisateur` — no CI in eight repos; roll it out, and a BUILD-DISCIPLINE row? | [hf7y/realisateur#285](https://github.com/hf7y/realisateur/issues/285) |
| `vim-arcade` — self-dev accounts have no permissions scaffolding | [hf7y/realisateur#282](https://github.com/hf7y/realisateur/issues/282) |
| 2026-07-31 reap — `bibscan` + 1.4 GB of scans still on mandark | [hf7y/bibliothecaire#35](https://github.com/hf7y/bibliothecaire/issues/35) |
| `realisateur` §5 / `groc-mangr` / `ecosim` — re-admit parked participants, at what weight | already open as [#100](https://github.com/hf7y/scheduler/issues/100) and [#156](https://github.com/hf7y/scheduler/issues/156) |
| `vkv-inventory` + `scheduler` — svc-vaporwave's two dead-man switches and its fixed-cron jobs | already open as [hf7y/senechal#162](https://github.com/hf7y/senechal/issues/162) |
| `realisateur` — a GitHub App identity for agents | already open as [hf7y/realisateur#86](https://github.com/hf7y/realisateur/issues/86) |
| `chezz` (whole section) | **not migrated** — Zach is handling chezz interactively |

## What was NOT migrated, and why

- **Most of it was already answered.** The file kept answered entries in
  place by its own append-only policy, so the `> ` replies from Zach and
  the dated `RESOLVED` / `RETRACTED` / `CORRECTION` machine-appends stayed
  inline forever. The `## Recently resolved` section alone was ~200 lines,
  and roughly half the "active" entries carried a resolution note under
  them. Those decisions live in the code and in git.
- **The 2026-07-29 "THE PLAY" block (four entries) was superseded
  wholesale** by the monkey migration — a fact the file itself records in
  a 2026-08-11 machine-append. `_paced.dexter.conf`, mandark self-dev, the
  freeze release, the 60-turn ceiling and `scheduler-dev-cycle.sh` are all
  about a host that no longer dispatches.
- **The `dexter` office questions** (isolation boundary, how root happens,
  gardien's nightly backup) were answered by events on 2026-08-03 and the
  file says so: a VM with users inside, built as `monkey`; no root needed
  on dexter; the backup lives on mandark as `garde-nightly.timer`.
- **Two items have no `hf7y` repo to receive them** and are recorded here
  rather than filed — see the finding below.
- **`bin/decide.sh`'s seven remediations** lived on a
  `research/ecosystem-cybernetics` branch in a linked worktree that no
  longer exists (worktrees reaped, [hf7y/realisateur#154](https://github.com/hf7y/realisateur/issues/154),
  [#69](https://github.com/hf7y/realisateur/issues/69)). Items 3 and 7 of
  that list were separately retracted or shipped.
- **Several entries were re-probed and found already fixed:** the
  `PROJECT_REPO_PATH` `$HOME` bug ([hf7y/realisateur#73](https://github.com/hf7y/realisateur/issues/73),
  [#143](https://github.com/hf7y/realisateur/issues/143)),
  `closeout-lint`'s worktree blindness (built as `cf1a1a9`),
  `check-project-busy --not-a-real-flag` (now exits 2, not 0),
  `ecosystem-survey.sh` (deleted), the subagent-pushes-`main` guard (`main`
  is now protected with `enforce_admins`), and `bashify emit`'s purge guard
  (realisateur PR #4, merged).

## Two things with nowhere to file

Both belong to `media-arts-collective`, not `hf7y`:

1. **Two personnel documents for `office` exist** — `HANDBOOK.md`
   (`f63ce49`, in force) and `bibliothecaire/briefs/office-v0-personnel-manual.md`
   (a draft that declares itself not in force). Which governs, and who owns
   the merge, was never decided. bibliothecaire is now agentless, so the
   draft has no maintainer.
2. **`claude` on `nomac` is installed but not authenticated** (2.1.220,
   node v24.18.1, verified 2026-07-29). Auth is interactive and therefore
   human-only. The office cannot execute a work order until it happens.

A third has no repo either: `vkv-inventory`'s home-testing instance. Zach
ran `clasp create` and pasted the script id inline
(`1mkI4QL-KrQYxZoEuDJnLgrxiGaIFtO_3F0yTId0WmdvpfLdrcmDhnevg`); nothing ever
picked it up for `home/deploy-home.sh`.

Full history — every entry, every `> ` reply, every correction — is in git
before this commit.
