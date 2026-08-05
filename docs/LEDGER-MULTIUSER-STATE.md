# The run ledger on a shared host — read state from `/var/lib`, not `$HOME`

*Design note, 2026-08-05. Written after `scheduler` on mandark printed BLIND
rows for four projects that had already migrated to monkey, and `scheduler`
on monkey printed an all-dashes table for thirteen. Both outputs were
truthful about what the running account could see and misleading about the
estate. Zach-directed: "the lying ledger points to a new way of displaying
status on the shared host. don't look in .local/share but something more
canonically multi-user unix."*

Every command output quoted here was captured on 2026-08-05 on the host named.

---

## 1. What was actually observed

**On mandark** (`scheduler`, run ledger section):

```
bibliothecaire  BLIND  -  runs as bibliothecaire; cannot read /.local/share/bibliothecaire-research (sudo -n -u bibliothecaire failed)
chezz           BLIND  -  runs as chezz; cannot read /.local/share/chezz-nightly-batch (sudo -n -u chezz failed)
ecosim          BLIND  -  runs as ecosim; cannot read /.local/share/ecosim-nightly-batch (sudo -n -u ecosim failed)
vim-arcade      BLIND  -  runs as vim-arcade; cannot read /.local/share/vim-arcade-nightly-batch (sudo -n -u vim-arcade failed)
```

**On monkey**, as `zach`: all thirteen projects, every `LAST RUN` / `ETA` /
`NEXT UP` cell a dash. `zach@monkey` has no `~/.local/share` at all —
verified: `ls: cannot access '/home/zach/.local/share': No such file or
directory`.

Meanwhile the four jobs had all dispatched and completed that same day, at
14:24 UTC, under their own accounts on monkey. The estate was healthy; both
glances said otherwise.

## 2. Two distinct defects, not one

**(a) `state_home` returns empty for an account that does not exist here.**

`bin/scheduler`:

```sh
state_home() {
  local acct="$1"
  if [ -z "$acct" ]; then printf '%s' "$HOME"
  else getent passwd "$acct" | cut -d: -f6
  fi
}
```

mandark has no `bibliothecaire` account — those users live on monkey
(`getent passwd` on mandark returns only `zach` and `svc-vaporwave`). So
`getent` prints nothing, and `dir="$(state_home "$acct")/.local/share/$job"`
renders as `/.local/share/bibliothecaire-research`: a leading slash and no
home. The malformed path is visible in the output above and is the tell.

The message then blames `sudo -n -u bibliothecaire failed`. That is true but
not the cause. `sudo` failed because **there is no such user on this host**,
not because permission was refused. The ledger diagnosed an access problem
where the real fact was a topology one.

**(b) The ledger ignores `CRON_HOST`.**

`schedule/<p>.conf` has carried `CRON_HOST` since `d92b8fa` ("confs: set
CRON_ACCOUNT/CRON_HOST for the four monkey projects"). `last_run_verdict`
reads `CRON_ACCOUNT` and never reads `CRON_HOST`. So mandark probes for the
local state of jobs it knows are registered to another host.

This was verified **not** to be a stale-clone problem, which is the usual
cause and was checked first: mandark's clone is `0 0` against `origin/main`
and contains `d92b8fa`.

## 3. Why `~/.local/share` + `sudo -n` cannot be the read path

The current design reads another account's state by `sudo -n -u <acct>`. On a
shared self-dev host that is the wrong primitive, for reasons that are
structural rather than incidental:

- **It requires the reader to be a sudoer.** Per `MONKEY.md` §2, project
  users deliberately get **no sudo** — "a self-dev user needs nothing outside
  `$HOME`". So `ecosim` can never read `chezz`'s ledger, and no project
  account can ever render a full table. Only `zach` can, and only because
  `zach` happens to hold sudo.
- **It reads through a `0700` home.** `MONKEY.md` specifies `home 0700` for
  project users. Group-readability inside `$HOME` is not available without
  weakening that, which is the wrong trade.
- **It makes an ordinary status read a privilege escalation.** Rendering a
  table should not require becoming four other users.
- **It conflates three different answers into one word.** "Not readable",
  "runs elsewhere", and "never ran" all surface as BLIND.

Per-user `$HOME` is the correct place for a user's *own* data. A run ledger
is not that: it is **estate state that several accounts must read and exactly
one writes**. Unix already has a canonical location for that.

## 4. The proposal — `/var/lib/scheduler/<job>/`

FHS 3.0 §5.5: `/var/lib` holds "state information … data that programs modify
while they run … persistent between invocations". That is precisely a run
ledger. Logs proper (`run.log`, `sweep.log`) are arguably `/var/log`, but they
are read as state by the ledger and keeping one directory per job avoids a
split-brain between two trees; `/var/lib` is the honest single home.

**Layout, one directory per job — same basenames as today:**

```
/var/lib/scheduler/                      root:scheduler   2775
├── ecosim-nightly-batch/                ecosim:scheduler 2775
│   ├── run.log                          ecosim:scheduler 0664
│   ├── sweep.log
│   └── expires_at
├── chezz-nightly-batch/                 chezz:scheduler  2775
├── scheduler-paced-runner/              (per writing account)
└── scheduler-registry/
```

- A group `scheduler`; every project account and `zach` is a member.
- Directories `2775` — **setgid**, so files created inside inherit group
  `scheduler` regardless of the writer's umask. This is the load-bearing bit;
  without setgid a project account's `0022` umask yields `ecosim:ecosim` files
  and the group read silently stops working for exactly the reason it was
  introduced.
- Files `0664`. The owning account writes; everyone in `scheduler` reads.

**What this buys:**

- `state_run` / `sudo -n` leaves the read path entirely. `cat` suffices.
- Any account can render the **full** table — including project accounts with
  no sudo, which today can render nothing.
- BLIND stops being the normal case and becomes what it was designed to be:
  a genuine, rare finding.

## 5. Three states where today there is one

`last_run_verdict` should distinguish:

| condition | render | meaning |
|---|---|---|
| `CRON_HOST` unset or `== $(hostname -s)`, state readable | the real verdict | as today |
| `CRON_HOST` set and `!= $(hostname -s)` | `ELSEWHERE@<host>` | not this host's business |
| `CRON_HOST` is this host, state unreadable | `BLIND` | a real finding |

`ELSEWHERE@monkey` is what mandark should have printed for all four projects.
It is shorter than the BLIND line it replaces, and true.

**This does not weaken the existing non-negotiable rule** stated above
`state_account` — never fall back to `$HOME`'s path and print it as another
account's state. `ELSEWHERE@<host>` is not a fallback; it is a refusal to
guess, which is what that rule protects.

A cross-host ledger — mandark rendering monkey's actual run state — is
explicitly **out of scope** here. That needs a transport and a trust story.
`ELSEWHERE@<host>` names the gap honestly rather than papering it; anything
more is a separate sprint.

## 6. Migration, and how it fails loud

`/var/lib/scheduler` needs root to create once per host. That is machine-wide
config, so per the ecosystem protocol it is `notify-senechal`'s business the
moment it lands on any host.

1. **Provision** (root, once per host): create the group, the tree, add each
   project account to `scheduler`, set `2775`.
2. **Write both, read new-then-old** for one full rotation. The writer tees to
   `/var/lib/scheduler/<job>/` and `~/.local/share/<job>/`; the reader prefers
   `/var/lib` and falls back to `$HOME`, logging **which** it used.
3. **Verify** against a real dispatch, not a dry run: after one 6-hourly tick,
   `scheduler` run as a **project account** (not `zach`) must render a full
   table with no BLIND rows. That is the human-sense witness for this change —
   an exit code proves nothing here, since today's broken path also exits 0.
4. **Drop the fallback**, and make a missing `/var/lib/scheduler/<job>` on a
   host that owns the job a loud failure rather than a silent `nolog`.

Step 3 is the acceptance test. Until it has run on monkey under a non-sudo
account, this document describes an intention and should not be cited as a
capability — `THE-FLOOR.md` opens with a correction about exactly that error.

## 7. Status

**Not built.** This is the design note only. No code in `bin/scheduler` has
been changed, no `/var/lib/scheduler` exists on any host, and no account has
been added to any new group as of 2026-08-05.
