#!/usr/bin/env bash
# Regenerate services/<project>/ -- a plain-text, browsable audit view of
# every registered service: what each job is TOLD to do, WHEN it runs, and
# what it LAST did. Open the folder in a file manager (or `cat` any file)
# and read it; nothing here needs a running process to inspect.
#
# Everything under services/ is GENERATED or SYMLINKED from the real
# sources -- never edit it by hand, edit the source and re-run this:
#   - schedule + knobs .... schedule/<project>.conf + the wrapper script
#   - task / prompt ....... the wrapper's PROMPT + the .claude/commands file
#   - status (live) ....... symlink to ~/reports/<project>/LATEST.md
#   - questions (live) .... symlink to <repo>/.claude/QUESTIONS.md
#
# Read-only w.r.t. everything except services/ (which it owns and rebuilds
# from scratch each run). Never touches crontab, wrappers, or reports.
#
# Run after any schedule/*.conf or wrapper change:  bin/build-services-view.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICES="$DIR/services"
REPORTS_DIR="$HOME/reports"
STATE_ROOT="$HOME/.local/share"
CRON="$(crontab -l 2>/dev/null || true)"

# --- helpers ---------------------------------------------------------------

# Best-effort cron -> English. Always prints; falls back to the raw expr.
humanize_cron() {
  local min="$1" hour="$2" dom="$3" mon="$4" dow="$5"
  local days=""
  case "$dow" in
    '*') ;;
    *) local out="" d; for d in ${dow//,/ }; do
         case "$d" in 0|7) out+="Sun,";; 1) out+="Mon,";; 2) out+="Tue,";;
           3) out+="Wed,";; 4) out+="Thu,";; 5) out+="Fri,";; 6) out+="Sat,";;
           *) out+="$d,";; esac; done
         days=" on ${out%,}";;
  esac
  if [[ "$min" == "*/"* ]]; then
    local n="${min#*/}" hr="$hour"
    case "$hour" in
      '*') echo "every ${n} min, all day${days}";;
      *,*) echo "every ${n} min, hours ${hour}${days}";;
      *-*) echo "every ${n} min, ${hour%-*}:00-${hour#*-}:00${days}";;
      *) echo "every ${n} min, hour ${hour}${days}";;
    esac
    return
  fi
  if [[ "$min" =~ ^[0-9]+$ && "$hour" =~ ^[0-9]+$ && "$dom" == "*" && "$mon" == "*" ]]; then
    printf "%s at %02d:%02d\n" "${days:+day(s)}${days:-daily}" "$hour" "$min"
    return
  fi
  echo "(see raw expression)"
}

# Pull a single-line scalar assignment (VAR="x" or VAR=x) from a wrapper.
scalar() { sed -n "s/^$2=\"\{0,1\}\([^\"#]*\)\"\{0,1\}.*/\1/p" "$1" | head -1; }

# Extract the multi-line PROMPT="..." body from a wrapper, quotes stripped.
extract_prompt() {
  awk '
    /^PROMPT="/ { s=$0; sub(/^PROMPT="/,"",s);
                  if (s ~ /"[[:space:]]*$/){ sub(/"[[:space:]]*$/,"",s); print s; exit }
                  print s; f=1; next }
    f { if ($0 ~ /"[[:space:]]*$/){ sub(/"[[:space:]]*$/,"",$0); print; exit } print }
  ' "$1"
}

# Slash command a wrapper invokes, e.g. /bug-sweep
prompt_cmd() { sed -n 's|^PROMPT="\(/[a-z][a-z-]*\).*|\1|p' "$1" | head -1; }

# Last run line from a job's log.
last_run() {
  local log="$STATE_ROOT/$1/sweep.log"
  [ -f "$log" ] || { echo "never run"; return; }
  local done_line; done_line="$(grep -E '^=== (done|FAILED|skipped)' "$log" | tail -1)"
  [ -n "$done_line" ] && echo "$done_line" || echo "started, no completion logged yet"
}

emit_tier() { # $1 conf-tier (SWEEP/BATCH) $2 label $3 project $4 repo
  local T="$1" label="$2" project="$3" repo="$4" outdir="$5"
  local jn cr sc; eval "jn=\${${T}_JOB_NAME:-}"; eval "cr=\${${T}_CRON:-}"; eval "sc=\${${T}_SCRIPT:-}"
  [ -z "$jn" ] && return 0

  # Resolve the live cron expression (auto-batched BATCH_CRON is only known
  # from the crontab, not the conf), preferring what's actually installed.
  local live; live="$(printf '%s\n' "$CRON" | grep "scheduler:${project}:${T}" | awk '{print $1,$2,$3,$4,$5}')"
  local expr="${live:-$cr}" incron="no"; [ -n "$live" ] && incron="yes"
  read -r mi ho dm mo dw <<<"$expr"

  {
    echo "### ${label} — ${jn}"
    echo "- when:     ${expr:-<unset>}  ($(humanize_cron "$mi" "$ho" "$dm" "$mo" "$dw"))"
    echo "- in crontab: ${incron}"
    echo "- last run: $(last_run "$jn")"
    echo "- script:   ${sc}"
  } >> "$outdir/schedule.txt"

  # task.md section
  local cmd cmdname cmdfile mt at br mo
  cmd="$(prompt_cmd "$sc")"; cmdname="${cmd#/}"
  cmdfile="$repo/.claude/commands/${cmdname}.md"
  mt="$(scalar "$sc" MAX_TURNS)"; [ -n "$mt" ] || mt="40 (engine default)"
  at="$(scalar "$sc" ALLOWED_TOOLS)"; [ -n "$at" ] || at="Bash,Read,Write,Edit,Glob,Grep (engine default)"
  br="$(scalar "$sc" BRANCH)"; [ -n "$br" ] || br="main (engine default)"
  # Model is the biggest per-token cost lever (Opus ~5x Sonnet), so surface
  # it in the audit. A legacy wrapper sets MODEL inline; a scheduler-run tier
  # sets <TIER>_MODEL in the conf (already sourced into scope here). Unset in
  # both means no --model flag -> the run inherits ~/.claude/settings.json.
  mo="$(scalar "$sc" MODEL)"; [ -n "$mo" ] || eval "mo=\${${T}_MODEL:-}"
  [ -n "$mo" ] || mo="unset — inherits CLI default (~/.claude/settings.json)"
  {
    echo "## ${label}  (${jn})"
    echo
    echo "Runs \`claude -p\` with:"
    echo "  - command:       ${cmd:-?}   (full instructions: ./command-${cmdname}.md)"
    echo "  - model:         ${mo}"
    echo "  - max turns:     ${mt}"
    echo "  - allowed tools: ${at}"
    echo "  - branch:        ${br}"
    echo "  - repo:          $(scalar "$sc" REPO_URL)"
    echo
    echo "Prompt handed to the agent:"
    echo '```'
    extract_prompt "$sc"
    echo '```'
    echo
  } >> "$outdir/task.md"

  # symlink the detailed command file so it's browsable in-folder
  if [ -f "$cmdfile" ] && [ -n "$cmdname" ]; then
    ln -sfn "$cmdfile" "$outdir/command-${cmdname}.md"
  fi
}

# --- build -----------------------------------------------------------------

rm -rf "$SERVICES"
mkdir -p "$SERVICES"
INDEX="$SERVICES/README.md"
{
  echo "# Services — what each registered job is doing"
  echo
  echo "_Generated by bin/build-services-view.sh from schedule/*.conf, the"
  echo "wrapper scripts, and each project's .claude/. Do not edit by hand —"
  echo "edit the source and re-run the generator. Regenerated: $(date -Is)._"
  echo
  echo "| Service | Tiers | Open a folder below |"
  echo "|---|---|---|"
} > "$INDEX"

shopt -s nullglob
for conf in "$DIR"/schedule/*.conf; do
  [ "$(basename "$conf")" = "_batch.conf" ] && continue
  ( # subshell so each conf's vars don't leak into the next
    unset PROJECT PROJECT_REPO_PATH SWEEP_JOB_NAME SWEEP_CRON SWEEP_SCRIPT \
          BATCH_JOB_NAME BATCH_CRON BATCH_SCRIPT
    # shellcheck disable=SC1090
    . "$conf"
    project="${PROJECT:?}"; repo="${PROJECT_REPO_PATH:-}"
    outdir="$SERVICES/$project"; mkdir -p "$outdir"

    printf '# %s — schedule\n\n' "$project" > "$outdir/schedule.txt"
    printf '# %s — what it is told to do\n\n' "$project" > "$outdir/task.md"

    tiers=""
    emit_tier SWEEP "Tier 1 · bug-sweep"     "$project" "$repo" "$outdir" && [ -n "${SWEEP_JOB_NAME:-}" ] && tiers+="sweep "
    emit_tier BATCH "Tier 2 · nightly-batch" "$project" "$repo" "$outdir" && [ -n "${BATCH_JOB_NAME:-}" ] && tiers+="batch "

    # live symlinks: status + questions
    latest="$REPORTS_DIR/$project/LATEST.md"
    ln -sfn "$latest" "$outdir/status.md"   # self-populates once a run writes LATEST.md
    [ -f "$latest" ] || echo "(no report yet — status.md will resolve once this service's first run writes ~/reports/$project/LATEST.md)" > "$outdir/status-PENDING.txt"
    if [ -n "$repo" ] && [ -e "$repo/.claude/QUESTIONS.md" ]; then
      ln -sfn "$repo/.claude/QUESTIONS.md" "$outdir/questions.md"
    fi

    printf '| **%s** | %s | `services/%s/` |\n' "$project" "${tiers:-—}" "$project" >> "$INDEX"
  )
done

echo "Built services view at: $SERVICES"
echo
find "$SERVICES" -maxdepth 2 -printf '%y  %p\n' | sed "s|$SERVICES|services|" | sort