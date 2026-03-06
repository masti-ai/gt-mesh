# HEARTBEAT.md - Muhchodu (Business Agent)

## Every Monday 9am (Weekly Business Report)
- [ ] Check 3 repos for merged PRs (last 7 days)
- [ ] Count new clients/work delivered
- [ ] Check for any critical alerts/blockers
- [ ] Post weekly update to pratham malik with:
  - 📊 Metrics (revenue, velocity, throughput)
  - ✅ Wins (completed work)
  - ⚠️ Blockers (needs attention)
  - 📋 Action items (max 3)

## Daily (if urgent)
- [ ] Payment failures or critical service alerts
- [ ] Client messages requiring immediate response
- [ ] Blocked work items in gt-docker

## When Triggered
- [ ] If pratham asks "status?" → Quick metrics + blockers
- [ ] If pratham asks "should we...?" → Pros/cons + recommendation

## Commands
```bash
# Weekly velocity
gh pr list --repo Deepwork-AI/gtconfig --state merged --limit 20 --json number,title,mergedAt --jq '.[] | select(.mergedAt > (now - 604800))'

# Check for blockers
gh issue list --repo Deepwork-AI/gtconfig --label "gt-status:blocked" --state open
```
