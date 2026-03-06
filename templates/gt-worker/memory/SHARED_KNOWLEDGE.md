# SHARED_KNOWLEDGE.md — GT Network Tips & Tricks

_This file is shared across ALL GT instances in the Deepwork-AI network._

## Quick Reference

### GitHub Labels (Multi-GT Coordination)

| Label | When to Use |
|-------|-------------|
| `gt-task` | Any cross-GT work assignment |
| `gt-from:gt-local` | Parent created this |
| `gt-to:gt-docker` | For this specific worker |
| `gt-status:pending` | Waiting for pickup |
| `gt-status:claimed` | Work in progress |
| `gt-status:done` | Delivered (PR created) |
| `needs-review` | PR needs parent review |
| `priority:p0/p1/p2` | Urgency levels |

### Branch Naming

```
gt/<instance-id>/<issue-number>-<short-description>

Examples:
- gt/gt-docker/15-fix-auth-bug
- gt/gt-docker/23-add-dashboard
- gt/gt-worker-002/5-update-config
```

### PR Body Template

```markdown
Closes #<issue-number>

## Changes
- Bullet point 1
- Bullet point 2

## Testing
- How you tested this
- What you verified

## Notes
Any additional context
```

## Pro Tips

### 1. Always Check `gh auth status`

Before doing ANY GitHub work:
```bash
gh auth status
# Should show: repo, read:org scopes
```

### 2. Poll for Work Smart

Don't just poll issues. Also check:
```bash
# Your assigned issues
gh issue list --repo Deepwork-AI/gtconfig --label "gt-to:gt-docker,gt-status:pending"

# Notifications (mentions, comments)
gh api notifications | jq '.[] | select(.reason == "mention")'

# Comments on your claimed issues
gh issue view <number> --comments
```

### 3. Claim Before You Work

**ALWAYS** change label to `gt-status:claimed` before starting:
```bash
gh issue edit <number> --remove-label "gt-status:pending" --add-label "gt-status:claimed"
```

### 4. Mark Done After PR

After creating PR:
```bash
gh issue edit <number> --remove-label "gt-status:claimed" --add-label "gt-status:done"
```

### 5. Use `gt prime`

After restart, always run:
```bash
cd /workspace/gt && gt prime
```

This loads your role context from the environment.

### 6. Keep MEMORY.md Updated

This is YOUR long-term memory. Update it with:
- Decisions made
- Context learned
- Preferences of pratham malik

### 7. Ask for Work When Idle

If no pending issues for 24h, create a "request for work" issue:
```bash
gh issue create --repo Deepwork-AI/gtconfig \
  --title "Request: Work assignment" \
  --label "gt-task,gt-to:gt-local" \
  --body "@gt-local I'm idle and ready for work."
```

## Agent-Specific Knowledge

### Chad Ji (Master)
- Routes messages to specialists
- Maintains orchestration
- Reports to pratham malik every 3 days

### Muhchodu (Business)
- Weekly reports every Monday
- Metrics-focused
- Use for: status updates, decisions, business analysis

### GigaGirl (Content)
- Brainstorms on demand
- Template creation
- Use for: content ideas, writing, creative work

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `gt` command not found | `cd /workspace/gt` first |
| Dolt connection failed | Check `dolt sql-server` is running |
| Can't claim issue | Check you have `repo` scope: `gh auth status` |
| PR creation fails | Ensure branch pushed: `git push -u origin <branch>` |

## Communication Style

Pratham malik prefers:
- Short texts over long walls
- Hinglish when natural
- Direct, no-BS communication
- Human-sounding, not robotic

---
**Network:** Deepwork-AI GT Network  
**Last Updated:** 2026-03-06
