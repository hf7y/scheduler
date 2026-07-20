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

`bin/collect-feedback.sh <file>` scans a file for tags and prints a
structured block (keyword + section + anchor + text) for every one found;
exits 1 with no output if there are none. The shared engine
(`lib/sweep-loop-common.sh`) runs this automatically against
`~/reports/<project>/LATEST.md` right before invoking `claude`, and -- if
anything was found -- prepends it to that run's prompt as "human feedback
on the previous report, act on this first." The scheduler's own two
bespoke wrappers (`scheduler-nightly-batch-loop.sh`,
`scheduler-dev-cycle.sh`) do the same against their own report file.

No separate "mark as read" step is needed: each run overwrites
`LATEST.md` with its own fresh report, so a tag naturally disappears once
the run that acted on it finishes (or persists, and gets re-collected, if
the run fails before writing a new report -- which is the right behavior:
retry until it's actually acted on).

## Editing reports in vim

`~/.vimrc` defines buffer-local mappings (active on files under
`~/reports/**/*.md` and this repo's `focus/` and `questions/` symlink
dirs) that insert a tag on a new line below the cursor and drop straight
into insert mode:

| Mapping | Inserts |
|---|---|
| `<leader>a` | `%%ACTION ` |
| `<leader>b` | `%%BLOCKER ` |
| `<leader>q` | `%%QUESTION ` |
| `<leader>n` | `%%NOTE ` |
| `<leader>y` | `%%APPROVE` |
| `<leader>r` | `%%REJECT ` |

## Reusing this elsewhere

The tag syntax has no dependency on reports specifically -- `%%TAG text`
in any file is collectible by `collect-feedback.sh <that file>`. A
project could, for example, collect tags out of its own FOCUS.md before
each run instead of (or in addition to) LATEST.md.
