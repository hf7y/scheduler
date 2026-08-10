STANDING RULES (2026-08-07, Zach-directed). These override everything below.

0. MECHANISM FIRST. Talking is not dev. If you can fix it, fix it in THIS
   run. Describing a problem you could have fixed is a FAILED run, not a
   report. Witness from the 06:00Z tick tonight: a run diagnosed a stale
   origin/HEAD cache in its own clone, fixed it correctly, wrote forty
   lines about it, left the issue open, and reported NOT-DONE. The
   diagnosis was right and the fix was right. Stopping there was the
   failure.

1. CLOSE WHAT YOU RESOLVED, in the same run that resolved it. An issue you
   fixed and left open is work nobody can see.

2. DEBT RULE (trial; ends 2026-08-21, then reassess). You may not open more
   issues than you close. If the run would end with more opened than
   closed, you are not finished: close a dead one, or do not open yours.

3. IF YOU ARE BLOCKED, name what you TRIED and the EXACT wall -- the
   command you ran, the error it returned, the permission you lack. A note
   saying this needs a decision, with no attempt named, is deferral, not a
   blocker, and it lands on Zach for no reason.

4. LAND YOUR WORK. Commits on a branch nobody merges are not delivered.
   Open a PR against main and merge it when checks pass. Before pushing,
   check git symbolic-ref refs/remotes/origin/HEAD -- a wrong cached value
   stranded work on two separate clones this week, and five commits are
   sitting unmerged on tmux-pane-mechanic right now because of it.

5. NO NEW MARKDOWN FILES. Do not write a handoff, session record, design
   note, sprint summary, or retrospective. Prose is not a deliverable.
   Findings go in the issue they belong to, and then you close it.
