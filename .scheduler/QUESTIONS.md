# Questions — retired 2026-08-15, migrated to GitHub issues

**Open questions now live at https://github.com/hf7y/scheduler/issues.**
This file is a pointer, not a second source of truth. Do not append here —
file an issue.

This retires the `scheduler ask <project> "<question>"` intake, the
`q-xxxxxx` id stamp, and the inline `> ` reply protocol along with the
file. Answer a question by commenting on its issue.

Retired by [#66](https://github.com/hf7y/scheduler/issues/66) (2026-08-07),
which killed every markdown feedback surface estate-wide; the sweep across
the other repos is
[hf7y/realisateur#230](https://github.com/hf7y/realisateur/issues/230).
`bin/questions-lint.sh` and `bin/collect-feedback.sh` are retired with the
rest of the machinery by [#193](https://github.com/hf7y/scheduler/issues/193).

## Where the open questions went

Eight entries were open. Each was re-probed against `main` rather than
trusted.

| Question | Now |
|---|---|
| `q-586b67` — should the paced runner escalate a sustained gate ERROR? | [#191](https://github.com/hf7y/scheduler/issues/191) — **confirmed still live** at `bin/usage-paced-runner.sh:553-557` |
| `q-ba2045` — do svc-vaporwave's aedile/vkv-inventory wrappers carry their own engine copy? | already open as [hf7y/senechal#162](https://github.com/hf7y/senechal/issues/162), which owns that account's dispatch |

## What was NOT migrated, and why

- **`q-756f82` — wrap `sweep-loop-common.sh`'s notify-send calls in
  `timeout`?** **Done.** Re-read 2026-08-14: `lib/sweep-loop-common.sh:246`
  is `timeout 5 notify-send "$@"`, with a `WARNING: notify-send timed out
  after 5s … notification DROPPED` line logged on rc≠0. The entry's
  instruction not to close it by observing that it had not hung in practice
  was honoured — it was closed by the fix, not by the absence of the
  symptom.
- **`q-ebc2d2` — is bar item 1 "install the schedule system on dexter"
  genuinely `[x]` when `scheduler` is not on PATH there?** Superseded. The
  `scheduler` monolith is sunset in favour of its verb set
  ([#34](https://github.com/hf7y/scheduler/issues/34)), the `focus/` and
  `questions/` symlink farms the question is about are retired
  ([#32](https://github.com/hf7y/scheduler/issues/32)), and dexter is no
  longer the dispatch host — self-dev moved to `monkey` on 2026-08-03.
- **`q-b8fc9f` — was building `bin/rotation-lint.sh` inside the bootstrap
  turn an overstep?** Moot. It asks which reading of a 2026-07-29 bootstrap
  brief should stand; that bootstrap never ran to completion and its host
  went dark. `bin/rotation-lint.sh` is on `main` and clean.
- **`q-13a017` — what happens to the editor-opening verbs `-p/-f/-q/-b`
  under the three-printable-views milestone?** Superseded by
  [#34](https://github.com/hf7y/scheduler/issues/34): the whole CLI those
  flags belong to is being sunset, so there is no printable-views fold to
  exempt them from.
- **`q-f75d57` — does `scheduler resolve <project> <id>` get an exemption
  from the ACCRETION FREEZE?** Superseded twice over. The verb was to write
  a drop directory into bibliothecaire's repo; bibliothecaire is reaped and
  agentless, and resolved questions now go nowhere because questions are
  issues.
- **`q-741cda`** was already answered inline by bibliothecaire on
  2026-07-28, and **the "Consumed / resolved" section** (ten one-line
  entries, 2026-07-24 to 2026-07-27) was already a changelog. Git is one.

Full history is in git before this commit.
