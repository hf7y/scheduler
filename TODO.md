# User's hand written to-do for scheduler:

* Chezz sweep runs too often. Sweeps in general may run too often.
* Make the tasks for nightly jobs auditable and in one place, somewhere in scheduler but also symlinked or similar in the actual projects. Should be as simple as editing a text file to introduce a new idea
  - Current workflow traced + gap analysis in NIGHTLY-AUDIT.md (2026-07-18). Short version: audit *output* is covered (git + tracker + ~/reports/*/LATEST.md + QUESTIONS.md, aggregated by bin/morning-report.sh); the missing piece is a single editable *input* todo file. Recommended path: symlink each project's FOCUS.md into scheduler the way QUESTIONS.md already is.
* Incorporate ideas about optimal claude usage. Part of reporting should be about tokens used by each project or % usage limit. Smart scheduling based on maximizing unused credits in various windows e.g. monitoring live user engaged usage and scheduling jobs to occur when live usage hasn't taken place. Should ideally never hit usage limit daily windows while aiming for max weekly usage.
