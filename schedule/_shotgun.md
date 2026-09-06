SHOTGUN RULES. You are a dispatcher with N workers, and these stop them working
the same issue twice.

1. SHARD BEFORE YOU FAN OUT. Read the open queue ONCE, yourself, and hand each
   subagent an explicit, DISJOINT list of issue numbers. Never tell a subagent
   to "pick an issue": two that both run `gh issue list` pick the same top one
   and open competing PRs, which is worse than working serially. Rank what you
   hand out -- milestone issues first (rule 6 above lists them), then
   `bin/next-issue.sh hf7y/<repo>`, which is oldest-first and skips anything
   whose body names a still-open "Depends on #N".
2. ONE CLONE PER SUBAGENT. Its first act is `git clone <this repo>
   "$HOME/.local/share/<job>/shard/<n>"`, and it works only there. You share a
   working directory with every subagent you launch, so two editing one
   checkout collide and their git operations race. Never `git worktree add`:
   banned estate-wide (hf7y/scheduler#49), and a clone is the replacement.
3. ONE BRANCH AND ONE PR PER ISSUE, branch `shotgun/<n>/<issue>` -- the shard
   number is in the name so two subagents cannot collide on it. Never push main.
4. RETURN CLEAN OR DO NOT RETURN. Commit, push and open the PR BEFORE you
   finish. A subagent stopping with its own files uncommitted is blocked by the
   SubagentStop gate, and unpushed commits and host-only branches are caught
   too. Commits on a branch nobody merges are not delivered.
5. CLOSING COUNTS. An issue whose premise expired should be CLOSED, naming what
   expired it. Three dead issues closed beats a fourth half-built.
6. STAY IN YOUR SHARD. A subagent that finishes early STOPS. It does not take
   up work it noticed in passing -- another subagent is probably on it.
7. REPORT PER SHARD: issues closed, PRs opened, and for anything not done the
   exact wall -- the command, the error, the permission lacked. "Ran out of
   time" is not a wall.
