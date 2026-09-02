# Inline feedback tags

A plain-text convention for leaving reviewer comments directly inside a
report (or FOCUS.md/QUESTIONS.md, or any other tracked file) in an ordinary
editor -- no separate review app, no re-typing feedback into a chat box.
The next scheduled run for that project reads them and acts on them first.

## Format

A tag is a line starting with `%%`, immediately followed by one of six
keywords, a space, and free text:

```
%%ACTION do this specific thing next
%%BLOCKER can't proceed until X happens
%%QUESTION which of these two options did you mean
%%NOTE fyi, no action needed, just context
%%APPROVE
%%REJECT reason it's a no
```

`%%APPROVE` and `%%REJECT` may stand alone (no text) or carry a reason.
Put the tag on its own line, wherever makes sense -- typically right after
the paragraph/bullet/section it comments on. Multiple tags in one file are
fine; each is collected independently.

## Anchoring

A tag attaches to two pieces of context, both inferred automatically, not
written by hand:
- **Section** -- the nearest preceding markdown heading (`#`, `##`, ...).
- **Re:** -- the nearest preceding non-blank, non-tag line (quoted verbatim).

This is why tags should go close to what they're commenting on -- the
anchor is positional, not a manually-typed reference.

## Collection

`bin/collect-feedback.sh <file>` scans a file for tags **and plain `> `
blockquote replies** and prints a structured block (keyword or `REPLY` +
section + anchor + text) for every one found; exits 1 with no output if
there are none. Consecutive `> ` lines merge into one `REPLY` block, not
one per physical line, so a wrapped paragraph reads as a single reply.
The shared engine (`lib/sweep-loop-common.sh`) runs this automatically
against `~/reports/<project>/LATEST.md` right before invoking `claude`,
and -- if anything was found -- prepends it to that run's prompt as
"human feedback on the previous report, act on this first." Scheduler's
own self-dev goes through the same path as every other project
(`.scheduler/schedule.conf`'s `BATCH_PROMPT`).

Two distinct file/mechanism pairs, easy to conflate since the vim editing
experience looks identical on both:
- **`QUESTIONS.md`**: `> ` replies read directly by `/nightly-batch`'s own
  prompt instructions (not by this script at all) — durable, append-only,
  the one built for judgment calls.
- **`LATEST.md`**: `> ` replies AND `%%TAG` lines both read by this
  script before the prompt is built. Ephemeral (overwritten wholesale each
  run) — a reply there only survives long enough to be read ONCE, on the
  very next dispatch; it is not a durable record the way a `QUESTIONS.md`
  entry is.

No separate "mark as read" step is needed: each run overwrites
`LATEST.md` with its own fresh report, so a tag naturally disappears once
the run that acted on it finishes (or persists, and gets re-collected, if
the run fails before writing a new report -- which is the right behavior:
retry until it's actually acted on).

## Editing reports in vim

`~/.vimrc` defines buffer-local mappings (active on files under
`~/reports/**/*.md`) that insert a tag on a new line below the cursor and
drop straight into insert mode.

| Mapping | Inserts |
|---|---|
| `<leader>a` | `%%ACTION ` |
| `<leader>b` | `%%BLOCKER ` |
| `<leader>q` | `%%QUESTION ` |
| `<leader>n` | `%%NOTE ` |
| `<leader>y` | `%%APPROVE ` |
| `<leader>r` | `%%REJECT ` |

## Auto-timestamp + signature on save

Any `%%TAG` line or `> ` reply, wherever it's typed from (the mappings
above or freehand), gets `[YYYY-MM-DDTHH:MM zach]` inserted right after
its marker automatically when the file is saved — the human doesn't need
to type it. Dates alone are ambiguous since a project can run more than
once a day, so a reply needs to say *when, to the minute* and *who* wrote
it.

Mechanics (`~/.vimrc`, `SchedulerFeedbackAutoStamp` augroup): on
`BufRead`/`BufNewFile` the buffer's on-disk lines are snapshotted; on
`BufWritePre`, any tag/reply line that is BOTH unstamped AND new-or-changed
relative to that snapshot gets stamped. A line untouched since opening is
left exactly as-is, so opening an old report/QUESTIONS.md and saving it
(e.g. to fix an unrelated typo) never fabricates today's date onto
yesterday's answers. Already-stamped lines are never re-stamped, checked
directly rather than only via the snapshot diff, so this holds even
across separate vim sessions.

**Multi-line replies stamp once, on their first line only**: a `> ` line
is only a stamp candidate if the line immediately above it is NOT itself
a `> ` line — a continuation of an already-started reply never gets its
own stamp.

The signer is hardcoded `zach`, not derived from `$USER` — this is a
personal dotfile answering "did zach write this or someone/something
else," not a general multi-user attribution system. `collect-feedback.sh`
needs no changes: its tag regex only matches on the `%%KEYWORD` prefix, so
a bracketed stamp immediately after is just more of the tag's own text.

## Auto-commit on save

**Trigger scope is every `*.md`, anywhere** — not a fixed list of
scheduler-tracking files. The mappings and auto-stamp are harmless no-ops
on a file that never uses the `%%TAG`/`> ` syntax, so this costs nothing.

**The one consequential action — the actual commit — has its own
separate gate**, so the broad trigger can never turn into "auto-commit
every markdown file on this machine": a save only actually commits if
the file's repo is the scheduler repo itself, or is listed as a
`PROJECT_REPO_PATH` in some `schedule/*.conf`. A personal note or an
unrelated, non-registered project's markdown resolves to a repo
scheduler has never heard of and is silently skipped.

Every save of one of these files also triggers a `git add` + `git commit`
of just that one file, so a human's edit is never left sitting only in
the working tree where it could get silently swept into an unrelated
commit. This replaces "remember to commit your own edits" with "it's
already done."

**Commits into whichever repo actually owns the file, not necessarily
this one** — resolving a symlink to its real owning repo via `git
rev-parse --show-toplevel` if the saved path is one. Files with no owning
repo at all (`~/reports/**/*.md` — deliberately uncommitted, lives outside
git by design) are silently skipped.

**Fully backgrounded so vim never blocks**, using `setsid` plus full
stdin/stdout/stderr detachment — some projects' pre-commit hooks are
genuinely slow (chezz's runs a full Playwright suite, 2+ minutes), and a
save must never hang the editor on that. Only the single saved file is
staged (never `-A`). The commit message is always prefixed `Human edit
via scheduler vim hook:` so it's never mistaken for a hand-crafted one.

## The retired cross-project channel: BLOCKERS.md

`collect-feedback.sh`'s `--section`/`--consume` flags (documented in its
own header comment) existed for `BLOCKERS.md`, the former cross-project blocker
board. `lib/sweep-loop-common.sh` no longer calls them: BLOCKERS.md is
retired (#66, 2026-08-07 -- human-owned items moved to GitHub issues) and
nothing wires this file into a prompt anymore. The per-report `%%TAG`
channel above (reading `~/reports/<proj>/LATEST.md`) is unaffected.

## Reusing this elsewhere

The tag syntax has no dependency on reports specifically -- `%%TAG text`
in any file is collectible by `collect-feedback.sh <that file>`. A
project could, for example, collect tags out of its own FOCUS.md before
each run instead of (or in addition to) LATEST.md.
