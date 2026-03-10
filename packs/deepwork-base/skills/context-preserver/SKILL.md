# Context Preserver Skill

Automatically preserve session context, learnings, and work history across AI sessions.

## Overview

The Context Preserver skill ensures no knowledge is lost between sessions by:
- Auto-saving context summaries before session end
- Recording learnings for future reference
- Maintaining a work log for tracking
- Creating handoff notes for context compaction

## Quick Start

```bash
# Initialize memory directory
mkdir -p ~/.gt-memory

# Save current context
gt-memory-save-context

# Record a learning
gt-memory-save-learning "Fixed race condition in async handler"

# View recent learnings
gt-memory-show-learnings
```

## Memory Files

| File | Purpose | Update Frequency |
|------|---------|------------------|
| `context-summary.md` | Current work state | Every session end |
| `learnings.md` | Accumulated insights | When learning occurs |
| `work-log.md` | Completed work record | When work completes |
| `handoff-notes.md` | Context handoff | On compaction only |

## Commands

### Save Context Summary

```bash
gt-memory-save-context
```

Creates/updates `~/.gt-memory/context-summary.md` with:
- Active bead and branch
- Current status
- Key decisions
- Blockers
- Next steps

### Record Learning

```bash
gt-memory-save-learning "<learning description>"
```

Appends to `~/.gt-memory/learnings.md` with timestamp and context.

### Show Learnings

```bash
gt-memory-show-learnings [n]
```

Displays last `n` learnings (default: 10).

### Create Handoff

```bash
gt-memory-handoff
```

Creates comprehensive handoff notes for context compaction.

## Session Integration

### At Session Start

```bash
# Load previous context
if [ -f ~/.gt-memory/context-summary.md ]; then
    echo "=== Previous Context ==="
    cat ~/.gt-memory/context-summary.md
fi
```

### Before Session End

```bash
# Auto-save
gt-memory-save-context
```

### On Context Compaction

```bash
# Create handoff
gt-memory-handoff

# Notify coordinator
gt mesh send gt-local "Context handoff created" \
  "See ~/.gt-memory/handoff-notes.md for session state"
```

## Format Examples

### Context Summary

```markdown
# Context Summary - 2026-03-09T14:30:00Z

## Current Work
- Active bead: cnt-ch4
- Branch: gt/gasclaw-1/cnt-ch4-case-study
- Status: in-progress

## Key Decisions Made
- Using technical case study format
- Target length: 2000-3000 words

## Blockers/Issues
- None

## Next Steps
1. Complete metrics section
2. Add executive summary
```

### Learning Entry

```markdown
## 2026-03-09T14:30:00Z - Race condition fix in async handler

**Context:** Debugging flaky test in planogram API
**Learning:** Always await async cleanup in beforeEach hooks
**Application:** Apply to all test files with async setup
```

## Implementation

This skill is implemented as shell functions sourced in `.bashrc`:

```bash
# Add to ~/.bashrc
source /workspace/gt/gt-mesh/packs/deepwork-base/skills/context-preserver/context-preserver.sh
```

## See Also

- [Persistent Memory Protocol](/CLAUDE.md#persistent-memory-protocol)
- [GT Mesh Skills](/skills/gt-mesh/SKILL.md)
