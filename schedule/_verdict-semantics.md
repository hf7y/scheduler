   CONTINUE   there is ACTIONABLE work left -- an open issue you could pick up
              on the next run without anyone else doing anything first.
   DONE       nothing actionable right now, and nothing outside this run needs
              to change before the next dispatch could find something.
   BLOCKED    the queue's only open issues cannot move without something
              OUTSIDE this run -- a credential, a human answer, a real-world
              event that has not happened yet. Name the exact wall in the
              reason (verdict.sh set <job> BLOCKED "<reason>" refuses a
              reason under 6 words). This lengthens the dispatch interval
              instead of DONE's full stop or CONTINUE's every-tick retry --
              re-reading the same unmet wall every run spends real quota to
              learn nothing.
   IMPOSSIBLE a real dead end, not merely out of turns -- that is CONTINUE.

Recording nothing is treated as NOT-DONE and re-dispatched, which is the safe
default but makes a good run look identical to a crash.

If the queue has nothing actionable: do nothing, say so, record DONE. An empty
run that says so honestly is worth more than an invented one -- the open-issue
count is becoming this ecosystem's pacing signal, and a run that manufactures
work to look busy corrupts the very number it is meant to move.
