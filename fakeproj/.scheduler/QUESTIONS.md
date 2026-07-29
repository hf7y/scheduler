# Questions for the user

Created by `scheduler ask`. Entries are generated, not hand-typed:
the question comes first because that is the part summary views show.
`bin/questions-lint.sh` FLAGs hand-written entries in `scheduler sweep`.

Answer inline, on a new line starting with `> ` directly under the
question. How an answer binds (rules A-D, 2026-07-29 -- full text in
scheduler's `examples/QUESTIONS.md.template`):

- **A. Direction, not instruction.** A reply states standing intent;
  whoever acts re-derives the concrete action from CURRENT state, not
  from the state the question described. So a reply never goes stale.
- **B. Re-probe the premise.** An instruction carries state claims;
  re-probe them. Premise false + action reversible -> act on the intent
  and flag the correction. Premise false + action irreversible -> stop
  and surface.
- **C. Extract standing direction silently.** A reply that generalizes
  past its question is folded into FOCUS.md, quoted and dated, without
  asking first.
- **D. No clean-check reports.** A re-probe that confirms the human was
  right produces no output at all.

## Open

- **does ask still work when the repo path is real**  `q-8a2d43` 2026-07-29, via positive-path probe
