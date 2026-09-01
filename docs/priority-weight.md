# Priority/pace weight: currently inert everywhere it's read

`schedule/_paced*.conf` supports an optional `weight` field
(`name|enabled|weight|command`, omitted defaults to 1). Where
`bin/usage-paced-runner.sh` still parses it (account mode, reading a conf
file directly) it would repeat a weight-N participant N times in the
rotation pool — but as of 2026-09-01 every enabled row in every
`schedule/_paced*.conf` in this tree is weight 1, so no dispatch anywhere
is actually being differentiated by it. In host mode, dispatching off
`schedule/ROSTER` (the liveness authority, #364), it can't even be
expressed: `roster_rows` emits weight 1 for every row regardless of what a
conf says (see `schedule/_paced.conf`'s own header). #55 explored dropping
the field outright and closed on a different question being moot instead.

The intended split, unexercised so far: scheduler would only be a
mechanical enforcement point ("run this number more often"), and
realisateur — which has the cross-project view scheduler deliberately
lacks — would be the one to actually set non-default values, weighing
which ideas are converging on something real against which are still
likely to morph before anything built on them survives. Nothing has set a
non-default value on a live row yet.
