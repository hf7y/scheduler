# scheduler(1) — the scheduler CLI, explained

The maintained man page for `bin/scheduler`, viewable any time with
`scheduler man` (or read this file directly). Started 2026-07-25 per the
FOCUS.md backlog ask ("start developing and maintaining a man page for
scheduler that explains its use"; also where the glance view's former
in-screen explanation text moved — the glance now carries a one-line
legend and points here).

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

`scheduler` is a thin, offline-first wrapper over the scheduler repo's
own tracking files (`focus/`, `questions/`, `BLOCKERS.md`,
`~/reports/<project>/`) and the paced runner's logs. It is not a parser
or database: subcommands mostly open the real file in `$EDITOR` or print
a screen assembled by `grep`/`awk`. Nothing here spends an AI call
unless you explicitly ask (`status --claude` / `--interactive`) — see
`docs/offline-first-checks.md` for the pattern.

## THE GLANCE (no arguments)

One screen: every registered project (from `schedule/*.conf`), one row
each, **sorted by open question count + blocker count descending** —
whatever most needs a human floats to the top; registration/conf-file
order is deliberately not used. Below the table, footer lines appear
only when they have something to say (see FOOTER LINES).

### Columns

- **PROJECT** — the registered name (`schedule/<project>.conf`).

- **QUESTIONS** — `unanswered/total` open questions in that project's
  `questions/<project>.md`. *Total* includes questions you've already
  replied to inline (a real `> ` reply) but whose project run hasn't
  consumed yet; *unanswered* is the count still waiting on you. Bullets
  marked RESOLVED/ACKNOWLEDGED are excluded entirely. `-` = none open.
  See `docs/feedback-tags.md` for how replies round-trip.

- **BLOCKERS** — open bullets under this project's `## <project>`
  section of `BLOCKERS.md`, excluding ones marked RESOLVED/PARKED
  inline. `-` = none.

- **LAST RUN** — age of `~/reports/<project>/LATEST.md` (the same file
  `scheduler report <project>` opens): a proxy for "last completed run"
  (its mtime only moves when a run actually writes a report), not a
  scheduler-tracked dispatch timestamp.

- **ETA** — FOCUS.md backlog size × that project's own average recent
  gap between paced dispatches (measured from
  `usage-paced-runner.sh`'s log). A rough projection off real history,
  NOT a promise: it assumes one backlog item clears per cycle, the
  backlog size stays fixed, and recent pace holds. `no history` =
  fewer than 2 recorded dispatches yet for that project.

- **NEXT UP** — `1/N: <top item's title>`, where N is the bulleted
  backlog size in that project's FOCUS.md. This is just what the next
  run reads first — it may reprioritize instead of clearing the top
  item, and paced projects run whenever `usage-gate.sh` has spare
  quota, not on a fixed clock, so this is not an ETA either.

### Conventions

- **`*` prefix** (QUESTIONS/BLOCKERS) — that file/section changed since
  you last opened it via this tool (`scheduler questions <project>`,
  `scheduler status <project>`, …). Approximate — file mtime (or a
  per-project section hash, for BLOCKERS.md) against a "last opened"
  timestamp in `~/.local/share/scheduler-glance/seen.tsv` — not a real
  read-receipt. No `*` means an open count you've already seen and just
  haven't gotten to.
- Counts come from format-convention heuristics (dated `- **` bullets,
  `> ` replies, RESOLVED/PARKED markers), not a real parser — an entry
  that ignores the usual conventions can miscount.

### Footer lines (each appears only when nonempty)

- **est. time to burn down every project's backlog** — the largest
  single-project ETA above (they burn concurrently under the rotation,
  so the max, not the sum, bounds the total). Projects showing
  `no history` aren't in the estimate, and the line says so.
- **`-> scheduler blockers`** — shown when any project has open
  blockers.
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
  rotation-facing command (`next`, `run`, `weight`, `paced`/`-p`) resolves
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
  guard checks. **This was broken until 2026-07-29**: `sync-crontab.sh`
  read only the shared file, so commenting out mandark's `scheduler|1|3`
  line to make its self-dev dark *armed* an auto-staggered nightly
  `scheduler-dev-cycle.sh` for the next `--apply`. See
  `tests/sync-crontab-paced-witness.sh`.
- **This was broken until 2026-07-29** (the CLI half): these commands
  hardcoded the shared file, so on `dexter`
  (which owns `_paced.dexter.conf`) they described — and `weight <p> <n>`
  *wrote into* — `mandark`'s rotation. Set `PACED_CONF` to override, or
  `PACED_HOST` to ask what another host would resolve.
- `focus/<project>.md`, `questions/<project>.md` — symlinks into each
  project's own scheduler-owned files (usually `.scheduler/` or
  `.claude/` in that project's repo).
- `BLOCKERS.md` — cross-project items needing a human, one `##
  <project>` section each.
- `~/reports/<project>/LATEST.md` — each project's newest report.
- `~/.local/share/scheduler-paced-runner/run.log` — the paced runner's
  dispatch log (feeds ETA and `scheduler next`).
- `~/.local/share/scheduler-glance/seen.tsv` — the `*`-marker "last
  opened" timestamps.
- `~/.local/share/<job>/repo` — dedicated per-job clones the unattended
  runs actually execute in.

## COMMANDS

Run `scheduler --help` — the authoritative, terse list lives there (one
source, not retyped here). The non-obvious ones in brief: `explain`
narrates how the whole system works; `status <project>` (or a bare
project name) is the offline per-project deep-dive — for a project whose
conf sets `CRON_ACCOUNT`, its "last scheduled run" state is read from
THAT account's home via `sudo -n -u <acct>`, and if that read fails the
line says `BLIND` naming the account and path rather than falling back to
`$HOME` (which would report a job that ran fine as never-run); `sweep` is the
read-mostly repo-state backstop; `-i <project> "idea"` drops a
timestamped idea into that project's backlog (omit "idea" to open
`$EDITOR` on a pre-populated placeholder instead); `next` prints the real
upcoming rotation order; `pacing` shows the live usage-gate verdict and
bin-drift check.

## SEE ALSO

`docs/feedback-tags.md` (the `%%TAG` / `> ` reply conventions),
`docs/offline-first-checks.md` (the no-AI-by-default pattern),
`docs/priority-weight.md` (`scheduler weight` semantics),
`README.md` (architecture + per-script table).
