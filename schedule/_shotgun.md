SHOTGUN RULES. You are not one worker. You are a dispatcher with N workers,
and these rules are what keep them from working the same issue twice.

1. SHARD BEFORE YOU FAN OUT. Read the open queue ONCE, yourself, and assign
   each subagent an explicit, DISJOINT list of issue numbers. Never tell a
   subagent to "pick an issue" -- two that both run `gh issue list` pick the
   same top issue and open competing PRs, which is worse than working serially.

   Rank what you hand out: milestone issues first (rule 6 above already lists
   them), then `bin/next-issue.sh hf7y/<repo>` for the rest -- oldest-first,
   skipping anything whose own body names a still-open "Depends on #N".

2. ONE CLONE PER SUBAGENT. Each subagent's FIRST act is

     git clone <this repo's URL> "$HOME/.local/share/<job>/shard/<n>"

   and it works only there. You share a working directory with every subagent
   you launch; two of them editing one checkout collide, and their git
   operations race. Never `git worktree add` -- banned estate-wide
   (hf7y/scheduler#49), and a clone is the sanctioned replacement.

3. ONE BRANCH AND ONE PR PER ISSUE, branch `shotgun/<n>/<issue>`. The shard
   number is in the branch name so two subagents cannot collide on it. Never
   push to main.

4. RETURN CLEAN OR DO NOT RETURN. Commit, push, and open the PR BEFORE you
   finish. A subagent that stops with its own files uncommitted is blocked by
   the SubagentStop closeout gate, and unpushed commits and host-only branches
   are caught too. Landing beats leaving: commits on a branch nobody merges
   are not delivered.

5. CLOSING COUNTS. An issue whose premise expired should be CLOSED with a
   comment naming what expired it. Closing three dead issues beats
   half-building a fourth, and triage parallelises better than building does.

6. STAY IN YOUR SHARD. A subagent that finishes early STOPS. It does not pick
   up work it noticed in passing -- another subagent is probably on it.

7. REPORT PER SHARD: issues closed, PRs opened, and for anything not done, the
   exact wall -- the command, the error, the permission lacked. "Ran out of
   time" is not a wall.
