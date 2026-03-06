# Shared Knowledge — Deepwork-AI Mesh

## GitHub Labels (Multi-GT Coordination)

| Label | When to Use |
|-------|-------------|
| `gt-task` | Any cross-GT work assignment |
| `gt-from:<id>` | Which GT created the task |
| `gt-to:<id>` | Which GT should pick it up |
| `gt-status:pending` | Waiting for pickup |
| `gt-status:claimed` | Work in progress |
| `gt-status:done` | Delivered (PR created) |
| `needs-review` | PR needs parent review |
| `priority:p0/p1/p2` | Urgency levels |

## Branch Naming

```
gt/<instance-id>/<issue-number>-<short-description>
```

## PR Body Template

```markdown
Closes #<issue-number>

## Changes
- Bullet points

## Testing
- How you tested
```

## Pro Tips

1. Always `gh auth status` before GitHub work
2. Claim issues before starting (`gt-status:claimed`)
3. Mark done after PR (`gt-status:done`)
4. Never push directly to dev/main
5. Use `gt prime` after session start for full context
6. Update memory files when you learn something new
7. When idle, ask: "Any beads or work I should pick up?"

## Communication Style

- Short, direct messages
- No fluff or unnecessary context
- Code speaks louder than descriptions
