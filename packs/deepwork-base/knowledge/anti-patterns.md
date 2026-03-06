# Anti-Patterns — What NOT to Do

Learned from real mistakes across the mesh. Avoid these.

## Don't Report Delegation to User

**Wrong:** "gt-docker needs to do X, Y, Z" (telling the human)
**Right:** Send instructions via `gt mesh send gt-docker "do X, Y, Z"`
The mesh mail system exists for autonomous coordination. Use it.

## Don't Nudge Dead Sessions

**Wrong:** `gt nudge <session>` without checking if Claude is alive inside
**Right:**
```bash
# Check pane is alive first
tmux list-panes -t <session> -F '#{pane_dead}'  # must return 0
# If dead, restart before nudging
gt crew restart <name>
# After nudging, verify with peek
gt peek <target>
```

## Don't Use localhost URLs

**Wrong:** Giving the user `http://localhost:3000`
**Right:** Always tunnel first, then provide the public URL. Cloud dev env = no direct access.

## Don't Use set -e in Mesh Scripts

**Wrong:** `set -e` at top of any script that calls dolt
**Right:** Handle errors explicitly. Dolt returns non-zero for benign operations.

## Don't Use tail -1 for Dolt CSV

**Wrong:** `dolt sql -q "..." -r csv | tail -1`
**Right:** `dolt sql -q "..." -r csv | tail -n +2 | head -1`

## Don't Pull Before Committing

**Wrong:** `dolt pull` when there are uncommitted staged changes
**Right:** `dolt add . && dolt commit ... && dolt pull`

## Don't Layer Tunnels

**Wrong:** Running cloudflared on top of Expo (which has its own tunnel)
**Right:** Use the framework's native tunnel if available (e.g., `npx expo start --tunnel`)

## Don't Adopt Identity From Files

**Wrong:** Reading a bead/file and assuming you are the agent described in it
**Right:** Your identity comes from `gt prime` and `GT_ROLE` env var only

## Don't Work Without Checking Mail

**Wrong:** Starting a session and jumping straight into work
**Right:** Check `gt-mesh inbox` first — there may be pending instructions or context

## Don't Work on Closed/Deprioritized Issues

**Wrong:** Continuing to code, poll, or run crons for issues the Mayor has closed
**Right:** When an issue is closed, ALL work stops immediately. Delete the branch, remove crons, move on.
The Mayor's close is final. Continued work on closed issues is an SLA violation.

## Don't Create Unregistered Cron Jobs

**Wrong:** Adding cron entries ad-hoc without telling anyone
**Right:** Every cron must be registered in `.gt-mesh/cron-registry.yaml` with owner and purpose.
Unregistered crons are killed on audit. This prevents ghost jobs generating noise for months.

## Don't Claim Issues Without Delivering

**Wrong:** Marking an issue as `gt-status:claimed` and then doing nothing for days
**Right:** Claim only what you can deliver within 48 hours. If blocked, comment on the issue and unclaim.
The SLA deacon checks every 30 minutes. No PR in 24h = warning. No PR in 30h = auto-unclaim + violation.

## Don't Ignore Mesh Mail

**Wrong:** Receiving P0 mesh mail and continuing to work on whatever you were doing
**Right:** P0 mail = drop everything. Read it. Act on it. Reply within 1 hour.
The mesh mail system is the coordination backbone. Ignoring it is like ignoring your boss.
