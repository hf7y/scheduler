# Migrating a project onto `scheduler-run`

Older projects ran each job through a hand-written wrapper at
`~/.local/bin/<project>-<tier>-loop.sh` that set a few variables and sourced
`lib/sweep-loop-common.sh`. That wrapper's config now lives in
`schedule/<project>.conf`, and the generic `bin/scheduler-run` reads it — so
the wrapper is redundant. This is the one-time move to retire it.

**Nothing about this is urgent or a flag day.** A tier keeps using its legacy
wrapper for exactly as long as its `*_SCRIPT` line is set. You migrate one
tier at a time, whenever, and the generated crontab only changes for the tier
you actually touched.

## The move (per tier)

1. **Copy the wrapper's config into the conf.** Open the wrapper
   (`~/.local/bin/<project>-<tier>-loop.sh`) and the project's
   `schedule/<project>.conf` side by side. For each variable the wrapper set,
   put it in the conf:

   | Wrapper variable | Conf field |
   |---|---|
   | `REPO_URL` | `REPO_URL` (project-level) |
   | `REPO_SUBDIR` | `REPO_SUBDIR` (project-level) |
   | `PROJECT_KEY` | `PROJECT_KEY` (project-level) |
   | `SECRETS_SRC_DIR` / `SECRETS_DEST_SUBDIR` | same (project-level) |
   | `PROMPT` | `SWEEP_PROMPT` or `BATCH_PROMPT` |
   | `MAX_TURNS` | `SWEEP_MAX_TURNS` / `BATCH_MAX_TURNS` |
   | `MODEL` | `SWEEP_MODEL` / `BATCH_MODEL` |
   | `PRECHECK_CMD` | `SWEEP_PRECHECK_CMD` / `BATCH_PRECHECK_CMD` |
   | `ALLOWED_TOOLS` | `SWEEP_ALLOWED_TOOLS` / `BATCH_ALLOWED_TOOLS` |
   | `EXPIRY_DAYS` | `SWEEP_EXPIRY_DAYS` / `BATCH_EXPIRY_DAYS` |
   | `BRANCH` | `SWEEP_BRANCH` / `BATCH_BRANCH` |

   `JOB_NAME`, `SWEEP_CRON`/`BATCH_CRON` are already in the conf. `TIER` is
   set automatically (`bug-sweep` / `nightly-batch`).

2. **Delete the `*_SCRIPT` line** (or comment it out) in the conf. That is the
   switch: with `SWEEP_SCRIPT`/`BATCH_SCRIPT` gone, `sync-crontab.sh` points
   cron at `scheduler-run <project> <tier>` instead of the wrapper.

3. **Preview and verify.** `bin/sync-crontab.sh` (no `--apply`) — the line for
   that tier should now read `.../bin/scheduler-run <project> <tier>` instead
   of the wrapper path. Everything else stays identical.

4. **Apply.** `bin/sync-crontab.sh --apply`.

5. **Retire the wrapper** once a real run has succeeded through
   `scheduler-run` (check `~/.local/share/<JOB_NAME>/sweep.log`): delete
   `~/.local/bin/<project>-<tier>-loop.sh`. Its state dir
   (`~/.local/share/<JOB_NAME>/`) is unchanged — `JOB_NAME` is the same, so
   the clone, lock, expiry, and heartbeat all carry over untouched.

## Why it's safe

- **No behavior change until step 2.** While `*_SCRIPT` is set it wins and the
  runtime fields are ignored — `scheduler-run` even refuses to run that tier
  if called directly, to prevent a double-config.
- **Same `JOB_NAME`, same state dir.** The dedicated clone, lock file, expiry
  marker, and heartbeat are keyed on `JOB_NAME`, which doesn't change. The job
  resumes exactly where it was.
- **One tier at a time.** Migrating Tier 1 doesn't touch Tier 2, and each
  project is independent.

## Projects still on legacy wrappers

As of 2026-07-18, all live tiers still set `*_SCRIPT` and run through their
wrappers (crontab verified byte-identical after the `scheduler-run` mechanism
landed). To migrate: `chezz`, `vkv-inventory` (both tiers), `home-assistant`,
`wtul` (Tier 2). `scheduler` itself is special — it does **not** use the
shared engine (local-only repo, worktree/review-gate wrapper) — and stays on
its own script.
