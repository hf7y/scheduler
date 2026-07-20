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
blockquote replies** (added 2026-07-20 -- see "A real near-miss" below)
and prints a structured block (keyword or `REPLY` + section + anchor +
text) for every one found; exits 1 with no output if there are none.
Consecutive `> ` lines merge into one `REPLY` block, not one per physical
line, so a wrapped paragraph reads as a single reply. The shared engine
(`lib/sweep-loop-common.sh`) runs this automatically against
`~/reports/<project>/LATEST.md` right before invoking `claude`, and -- if
anything was found -- prepends it to that run's prompt as "human feedback
on the previous report, act on this first." The scheduler's own two
bespoke wrappers (`scheduler-nightly-batch-loop.sh`,
`scheduler-dev-cycle.sh`) do the same against their own report file.

**A real near-miss that motivated the `> ` support:** a human reply
written directly into a report's `LATEST.md` (using the same `> `
convention `QUESTIONS.md`'s own contract documents) was, before this
change, invisible to this script -- only `%%TAG` lines were recognized.
Since `LATEST.md` gets wholly overwritten on the project's next run, that
reply was one dispatch away from being silently destroyed, having never
been read by anything. Recovered by hand that one time (copied into the
project's own `QUESTIONS.md`/`FOCUS.md`, where the reply mechanism
actually is wired); this fix closes the gap so it can't recur. Two
distinct file/mechanism pairs, easy to conflate since the vim editing
experience looks identical on both — worth remembering:
- **`QUESTIONS.md`**: `> ` replies read directly by `/nightly-batch`'s own
  prompt instructions (not by this script at all) — durable, append-only,
  the one built for judgment calls.
- **`LATEST.md`/`BLOCKERS.md`**: `> ` replies (now) AND `%%TAG` lines both
  read by this script before the prompt is built. `LATEST.md` itself is
  ephemeral (overwritten wholesale each run) — a reply there only survives
  long enough to be read ONCE, on the very next dispatch; it is not a
  durable record the way a `QUESTIONS.md` entry is.

No separate "mark as read" step is needed: each run overwrites
`LATEST.md` with its own fresh report, so a tag naturally disappears once
the run that acted on it finishes (or persists, and gets re-collected, if
the run fails before writing a new report -- which is the right behavior:
retry until it's actually acted on).

## Editing reports in vim

`~/.vimrc` defines buffer-local mappings (active on files under
`~/reports/**/*.md`, this repo's `focus/` and `questions/` symlink dirs,
and `BLOCKERS.md`) that insert a tag on a new line below the cursor and
drop straight into insert mode:

| Mapping | Inserts |
|---|---|
| `<leader>a` | `%%ACTION ` |
| `<leader>b` | `%%BLOCKER ` |
| `<leader>q` | `%%QUESTION ` |
| `<leader>n` | `%%NOTE ` |
| `<leader>y` | `%%APPROVE ` |
| `<leader>r` | `%%REJECT ` |

## Auto-timestamp + signature on save (added 2026-07-20)

Any `%%TAG` line or `> ` reply, wherever it's typed from (the mappings
above or freehand), gets `[YYYY-MM-DDTHH:MM zach]` inserted right after
its marker automatically when the file is saved — the human doesn't need
to type it, and doesn't need to remember to. Motivation: since the paced
governor moved projects off a fixed nightly rhythm, day-level dates in
existing conventions are ambiguous (a project can now genuinely run more
than once in a calendar day) — an agent reading a reply needs to know
*when, to the minute* and *who* wrote it, especially as more sessions
(human or agent, on this machine or elsewhere) touch these shared files.

Mechanics (`~/.vimrc`, `SchedulerFeedbackAutoStamp` augroup): on
`BufRead`/`BufNewFile` the buffer's on-disk lines are snapshotted; on
`BufWritePre`, any tag/reply line that is BOTH unstamped AND new-or-changed
relative to that snapshot gets stamped. A line untouched since opening —
including every pre-existing unstamped reply already in a file from before
this feature existed — is left exactly as-is, so opening an old
report/QUESTIONS.md and saving it (e.g. to fix an unrelated typo) never
fabricates today's date onto yesterday's answers. Already-stamped lines
are never re-stamped (checked directly, not just via the snapshot diff, so
this holds even across separate vim sessions). Verified with a scripted
headless-vim test: a new tagged line and a new freehand `> ` reply both
got stamped correctly; an old, already-answered `> ` line was untouched;
re-saving an already-stamped line left its timestamp unchanged.

**Multi-line replies stamp once, on their first line only** (fixed
2026-07-20 after a real multi-line reply in the wild got the same
timestamp repeated on all six of its wrapped lines): a `> ` line is only
a stamp candidate if the line immediately above it is NOT itself a `> `
line — a continuation of an already-started reply never gets its own
stamp. Re-verified with a scripted three-line reply: only line one got
`[timestamp zach]`, lines two and three stayed plain.

The signer is hardcoded `zach`, not derived from `$USER` — this is a
personal dotfile answering "did zach write this or someone/something
else," not a general multi-user attribution system. `collect-feedback.sh`
needs no changes: its tag regex only matches on the `%%KEYWORD` prefix, so
a bracketed stamp immediately after is just more of the tag's own text,
visible to whatever reads it.

## Auto-commit on save (added 2026-07-20)

Every save of one of these scoped files also triggers a `git add` +
`git commit` of just that one file, so a human's edit is never left
sitting only in the working tree where it could get silently swept into
an unrelated commit (this happened once, for real, before this existed —
a batch of edits to `BLOCKERS.md` got bundled into an unrelated automated
commit via `git add -A` and had to be split back out by hand afterward).
This replaces "remember to commit your own edits" with "it's already
done" — a discipline problem solved by automation instead of a habit to
build.

**Commits into whichever repo actually owns the file, not necessarily
this one.** `focus/*.md` and `questions/*.md` are symlinks into other
projects' own repos (chezz's `FOCUS.md`, etc.) — editing one and saving
resolves the symlink, finds the REAL owning repo via `git rev-parse
--show-toplevel`, and commits there. `BLOCKERS.md` and this project's own
`.scheduler/FOCUS.md`/`QUESTIONS.md` commit into the scheduler repo
itself. Files with no owning repo at all (`~/reports/**/*.md` —
deliberately uncommitted, lives outside git by design) are silently
skipped — confirmed directly against the real `~/reports` directory, not
assumed.

**Fully backgrounded so vim never blocks**, using `setsid` plus full
stdin/stdout/stderr detachment — some projects' pre-commit hooks are
genuinely slow (chezz's runs a full Playwright suite, 2+ minutes), and a
save must never hang the editor on that. Only the single saved file is
staged (never `-A`), so this can never sweep in unrelated uncommitted
work already sitting in that repo. The commit message is always prefixed
`Human edit via scheduler vim hook:` so it's never mistaken for a
hand-crafted one.

Verified end-to-end in a sandboxed pair of throwaway repos linked by a
symlink (mirroring the real `focus/*.md` setup) before touching the real
`~/.vimrc`: committing through the symlink lands only in the external
repo, the local one stays untouched; committing `BLOCKERS.md` directly
lands locally; both return control to vim near-instantly. A naive first
attempt (background the command with a bare `&`, no `setsid`/detachment)
was confirmed to hang vim indefinitely — the tested form here is what
avoids that.

## One cross-project file: BLOCKERS.md

`BLOCKERS.md` (repo root) lists human-owned action items across every
project, one `## <project_key>` section each. `collect-feedback.sh`
supports two extra flags for this case:

- `--section "<project_key>"` -- only collect tags anchored under a
  heading matching that text (case-insensitive, `#`s/whitespace ignored),
  so one shared file can be scanned separately per project without
  leaking another project's tags into the wrong run.
- `--consume` -- after collecting, rewrite the file removing the matched
  `%%TAG` lines in place. Use this for `BLOCKERS.md` (and any other
  persistent, hand-maintained file) since -- unlike `LATEST.md` -- nothing
  else naturally clears an acted-on tag from it.

`lib/sweep-loop-common.sh` and the scheduler's own two bespoke wrappers
all check `BLOCKERS.md --section "$PROJECT_KEY" --consume` right after
the `LATEST.md` check, prepending it to the prompt the same way. The
blocker's plain-text description line is untouched by `--consume` --
delete that by hand once the underlying problem is actually resolved.

## Reusing this elsewhere

The tag syntax has no dependency on reports specifically -- `%%TAG text`
in any file is collectible by `collect-feedback.sh <that file>`. A
project could, for example, collect tags out of its own FOCUS.md before
each run instead of (or in addition to) LATEST.md.
