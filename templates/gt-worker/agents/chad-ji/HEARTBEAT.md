# HEARTBEAT.md - Chad Ji's Checks

## Every 30 Minutes
- [ ] Run `gt status` — check Gastown health
- [ ] Run `ais ls` — check active agent sessions
- [ ] Check for rate limits: `ais accounts`

## Every 3 Hours (Poll for Work)
- [ ] Check GitHub for `gt-to:gt-docker,gt-status:pending` issues:
  - gtconfig repo
  - alc-ai-villa repo
  - ai-planogram repo
- [ ] If work found: claim it, notify pratham
- [ ] If no work: consider creating "request for work" issue

## Every 3 Days (Report to pratham malik)
- [ ] Post update in designated Telegram groups:
  - Issues picked up
  - PRs created
  - Work in progress
  - Blockers or escalations

## Weekly
- [ ] Review MEMORY.md — update with learnings
- [ ] Clean up old beads: `bd close` completed issues
- [ ] Check disk space on /workspace

## Commands Quick Reference
```bash
# Gastown health
cd /workspace/gt && gt status

# Poll for work (WORKER role)
gh issue list --repo Deepwork-AI/gtconfig --label "gt-to:gt-docker,gt-status:pending"
gh issue list --repo Deepwork-AI/alc-ai-villa --label "gt-to:gt-docker,gt-status:pending"
gh issue list --repo Deepwork-AI/ai-planogram --label "gt-to:gt-docker,gt-status:pending"

# Claim work
gh issue edit <number> --repo Deepwork-AI/<repo> \
  --remove-label "gt-status:pending" --add-label "gt-status:claimed"

# Beads list
bd list | head -20
```
