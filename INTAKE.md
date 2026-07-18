# Web intake contract

The standard shape a project's tracker backend implements so it can plug
into the shared bug-sweep/nightly-batch tooling without special-casing.
Not new — this generalizes what `chezz`'s `leaderboard/Code.gs` and
`vkv-inventory`'s `src/Bugs.gs` already independently converged on (their
docstrings say as much: "same BugReports shape and doGet/doPost contract").
chezz's version is currently the more complete one (it added
`sweep-status`, described below, that vkv-inventory hasn't adopted yet).
Any future project's backend — Apps Script, or anything else that can
answer plain HTTP GET/POST with JSON — should implement this same shape.

## Read: `GET ?scope=bugs&status=&type=&limit=`

- `status`: `open` (default) | `resolved` | `all`. A routine sweep should
  never have to re-read reports already dealt with.
- `type`: `bug` (default) | `feature` | `all`. This is where "the running
  list of features" actually lives — **not a separate file**. A `type=
  feature` report IS a feature-backlog entry; querying with `type=all` (or
  `type=feature`) is how a nightly-batch job reads the accumulated
  feature ideas. Keeping this in one place (the tracker) instead of a
  second markdown file avoids the two ever drifting out of sync.
- `limit`: default 20.
- Response: `[{timestamp, name, url, description, status, note, type}, ...]`

## Write: `POST` with `Content-Type: text/plain`, body a JSON string

- **File a report**: `{"type":"bug"|"feature", "name", "url", "description"}`
- **Resolve / reclassify / reopen**: `{"type":"resolve", "timestamp":
  "<exact timestamp string from the read above>", "status":"resolved"|
  "open", "note":"...", "reportType":"bug"|"feature" (optional, to
  reclassify)}`. `timestamp` is the row's natural key (already unique,
  ms-precision) — there's no separate id column to keep in sync.
- **Record a sweep/batch run** (chezz has this; vkv-inventory does not
  yet — see "Gap" below): `{"type":"sweep-status", "fetched":N, "fixed":F,
  "reclassified":R, "leftOpen":L}`. One overwritten record (Script
  Properties, not a growing sheet — nothing needs history, just the
  latest), `timestamp` stamped **server-side** so it can't drift from
  whatever clock the runner happens to have. Posted every run, even one
  that fixed nothing — the point is proof-of-life, not just a log nobody's
  watching. Read back with `GET ?scope=sweep-status` → `{timestamp,
  fetched, fixed, reclassified, leftOpen}` or `null` if nothing's ever
  reported in.

## The one gotcha every implementation needs to handle the same way

**Never trust the raw HTTP response from a POST against an Apps-Script-
backed endpoint.** The redirect chain (`/exec` → `googleusercontent.com/
macros/echo` → back) can show a false "Page Not Found" or error on a write
that actually succeeded. Always confirm by re-fetching (`GET
?scope=bugs&status=...`) afterward and checking the report's actual
state, never the POST's own response body/status.

## Gap: vkv-inventory hasn't adopted `sweep-status` yet

chezz's live page shows "Bug sweep last ran Xm/h/d ago · N fixed", read
from `GET ?scope=sweep-status`. vkv-inventory's `src/Bugs.gs` has no
equivalent — `.claude/commands/bug-sweep.md` for that project doesn't
post one, and there's no UI reading one back. Adding it means: a
`sweep-status` case in `doPost`/`doGet` (copy chezz's `recordSweepStatus_`/
`getSweepStatus_`, ~15 lines), a step in `bug-sweep.md` posting it every
run, and somewhere in the app's own UI that reads it back — that last
part is a real (small) feature, not just plumbing, so it's listed here as
a gap, not fixed unilaterally.
