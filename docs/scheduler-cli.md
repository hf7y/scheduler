# scheduler(1) — the scheduler CLI, explained

The maintained man page for `bin/scheduler`, viewable any time with
`scheduler man` (or read this file directly).

**Maintenance contract:** the terse per-command reference deliberately
stays in ONE place — `scheduler --help` (the `usage()` function in
`bin/scheduler`) — and is not retyped here, so the two can't drift. This
page owns everything `--help` is too terse for: what the glance columns
mean, where each number comes from, the conventions (`*`, `> ` replies,
`%%TAG`s), and which files back it all.

## SYNOPSIS

    scheduler                      # the glance (see below)
    scheduler <project>            # status deep-dive (bare-name shorthand)
    scheduler <command> [args]     # see `scheduler --help` for the full list
    scheduler man                  # this page

## DESCRIPTION

`scheduler` is a thin, offline-first wrapper over `~/reports/<project>/`, the
paced runner's logs, and (for a project with `ANSWER_CHANNEL=issues`) that
project's GitHub issues. It is not a parser or database: subcommands mostly
open the real file in `$EDITOR` or print a screen assembled by `grep`/`awk`.
Nothing here spends an AI call unless you explicitly ask (`status --claude` /
`--interactive`) — see `docs/offline-first-checks.md` for the pattern.

## THE GLANCE (no arguments)

One screen: every registered project (from `schedule/*.conf`), one row
each, **sorted by open question count descending** — whatever most
needs a human floats to the top; registration/conf-file order is
deliberately not used. Below the table, footer lines appear only when
they have something to say (see FOOTER LINES).

### Columns

- **PROJECT** — the registered name (`schedule/<project>.conf`).

- **QUESTIONS** — `unanswered/total` open questions, for a project with
  `ANSWER_CHANNEL=issues` in its conf: read live from that project's GitHub
  issues (`gh`). `-` = none open. Every other project defaults to the local
  `questions/<project>.md` mirror `sync-crontab.sh` used to symlink here —
  retired whole by #244, no replacement read path — so those render `?`
  (BLIND: not read, not "nothing open"). See `docs/feedback-tags.md` for how
  replies round-trip on the issues channel.

- **LAST RUN** — age of `~/reports/<project>/LATEST.md` (the same file
  `scheduler report <project>` opens): a proxy for "last completed run"
  (its mtime only moves when a run actually writes a report), not a
  scheduler-tracked dispatch timestamp.

- **ETA** and **NEXT UP** — meant to read a project's FOCUS.md backlog (size
  × average recent dispatch gap for ETA; top bulleted item for NEXT UP), the
  same way QUESTIONS above used to read `questions/<project>.md` directly.
  Both symlinks came from the same retired mirror (#244), and nothing has
  replaced the FOCUS.md read path, so both columns always render `?` (BLIND)
  today, for every project.

### Conventions

- **`*` prefix** (QUESTIONS) — meant to mean "changed since you last
  opened it via this tool", by comparing `questions/<project>.md`'s mtime
  against a "last opened" timestamp in
  `~/.local/share/scheduler-glance/seen.tsv`. That file is the same #244
  casualty as the QUESTIONS column above, so on the surviving issues
  channel this never fires today — no `*` is not a signal either way.
- On the issues channel, "answered" comes from a provenance stamp (the
  last comment on the issue), not a markdown-format heuristic — see
  `lib/provenance.sh`.

### Footer lines (each appears only when nonempty)

- **est. time to burn down every project's backlog** — the largest
  single-project ETA above. Never prints today: it needs at least one
  real ETA, and ETA is unconditionally `?` (see above).
- **stranded local commits** — some project's dedicated clone
  (`~/.local/share/<job>/repo`) has commits ahead of origin: its run
  committed but the push silently failed or never ran (e.g. a
  credential gap or a mid-run usage cutoff). `scheduler sweep` gives
  the per-run detail, including a `push reason:` diagnosis.
- **branches awaiting review** — branches beyond `main`/`master` (local
  or on origin) in the scheduler repo or any dedicated clone, with
  commit counts ahead of that repo's default branch — e.g. a finished
  `nightly/<date>`/`paced/<date>` cycle nobody merged. Read-only:
  merging stays a human action.

### The run ledger (always printed, sprint step 3 — 2026-07-28)

Unlike the footer lines above, this block prints **every time, including
when everything is fine.** A surface that only appears when something is
wrong cannot be told apart from a surface that is broken.

- Each row's verdict comes from that job's **own run log**
  (`~/.local/share/<job>/sweep.log`, or the older `run.log` dialect), not
  from the `LAST RUN` column above — that column is
  `~/reports/<p>/LATEST.md`'s mtime, which is a proxy for the last
  *success*, because a failed run writes no report.
- Verdicts: `ok` `FAILED` `skipped` `running` `nolog` `nojob`, and
  `BLIND` for a `CRON_ACCOUNT` job whose state this account cannot read
  (it names the account and path rather than reading `$HOME`'s and
  reporting that as the job's state). A record older than 5 days is
  prefixed `stale-` and says so: an orphaned job's old FAILED is not
  evidence of an outage, and rendering it as one is how a sensor earns
  being ignored.
- Only non-`ok` rows are listed; the count of clean jobs is always
  printed, so "nothing listed" and "nothing checked" cannot look alike.
- A standing **`BLIND:`** line states the one thing nothing on disk
  records — whether a dispatch was *due* and did not fire. It is
  unconditional on purpose; dropping it on a quiet night would read as
  "nothing was missed."
- **last actual dispatch** — how long since the paced runner last
  reported a `DONE` line, or `BLIND` if its log is missing.

`bin/unprinted-facts.sh` is the measurement this block was designed
against: which facts the machinery records and which views print them.

## DATA SOURCES / FILES

- `schedule/*.conf` — the project registry (one conf per project;
  `_paced.conf`/`_runner.conf`/`_paced.<host>.conf` are engine config,
  not projects).
- **The rotation this host runs** — `schedule/_paced.<short-hostname>.conf`
  if that file exists, otherwise the shared `schedule/_paced.conf`. Every
  rotation-facing command (`next`, `run`, `paced`/`-p`) resolves
  it through `lib/paced-conf.sh`, the same rule `bin/usage-paced-runner.sh`
  applies when it actually dispatches — so what `scheduler` reports and
  what runs here are the same file, on any host. `scheduler next` prints
  the resolved path and why it was chosen.
- **Which projects the paced system OWNS** — a *different* question, and
  deliberately not the same answer. `bin/sync-crontab.sh` suppresses a
  project's fixed nightly `BATCH` cron line when that project is listed in
  **any** host's rotation (`lib/paced-conf.sh`'s `paced_membership_set`,
  the union across `_paced.conf` and every `_paced.<host>.conf`), because a
  fixed line for a project *another* host's runner dispatches is
  cross-host double dispatch. "Does it dispatch *here*, as this account,
  right now?" stays host-resolved — that is what the foreign-`CRON_ACCOUNT`
  guard checks. See `tests/sync-crontab-paced-witness.sh`.
- The CLI resolves the same host-scoped rotation for every rotation-facing
  command, rather than always reading the shared `_paced.conf` — so on
  `dexter` (which owns `_paced.dexter.conf`), `run <p>` dispatches against
  dexter's rotation, not mandark's. Set `PACED_CONF` to override, or
  `PACED_HOST` to ask what another host would resolve.
- A project's GitHub issues (`ANSWER_CHANNEL=issues` only) — read live via
  `gh`, no local file. Every other project has no read path at all: the
  `focus/<project>.md`/`questions/<project>.md` symlinks this used to be are
  the mirror #244 retired.
- `~/reports/<project>/LATEST.md` — each project's newest report.
- `~/.local/share/scheduler-paced-runner/run.log` — the paced runner's
  dispatch log (feeds ETA and `scheduler next`).
- `~/.local/share/scheduler-glance/seen.tsv` — the `*`-marker "last
  opened" timestamps.
- `~/.local/share/<job>/repo` — dedicated per-job clones the unattended
  runs actually execute in.

## COMMANDS

Run `scheduler --help` — the authoritative, terse list lives there (one source,
not retyped here). The non-obvious ones: `status <project>` (or a bare project
name) is the offline per-project
deep-dive — for a conf setting `CRON_ACCOUNT` it reads "last scheduled run"
from THAT account's home via `sudo -n -u <acct>`, saying `BLIND` with the
account and path if that read fails rather than falling back to `$HOME` and
calling a job that ran fine never-run; `sweep` is the read-mostly repo-state
backstop; `-i <project> "idea"` files one GitHub issue on that project's repo,
writing nothing locally (omit "idea" for `$EDITOR`); `next` prints the real
upcoming rotation order; `pacing` shows the live usage-gate verdict and
bin-drift check.

## SEE ALSO

`docs/feedback-tags.md` (the `%%TAG` / `> ` reply conventions),
`docs/offline-first-checks.md` (the no-AI-by-default pattern),
`README.md` (architecture + per-script table).
