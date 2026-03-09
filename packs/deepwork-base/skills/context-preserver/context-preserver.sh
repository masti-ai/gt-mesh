#!/bin/bash
# Context Preserver - Auto-save session context and learnings
# Source this file in ~/.bashrc for persistence

GT_MEMORY_DIR="${GT_MEMORY_DIR:-$HOME/.gt-memory}"

# Ensure memory directory exists
_gt_memory_init() {
    mkdir -p "$GT_MEMORY_DIR"
}

# Save current context summary
gt-memory-save-context() {
    _gt_memory_init
    
    local timestamp
    timestamp=$(date -Iseconds)
    
    local summary="# Context Summary - ${timestamp}

## Current Work
- Active bead: ${GT_ACTIVE_BEAD:-unknown}
- Branch: $(git branch --show-current 2>/dev/null || echo 'N/A')
- Status: ${GT_WORK_STATUS:-unknown}

## Key Decisions Made
${GT_DECISIONS:-<!-- No decisions recorded -->}

## Blockers/Issues
${GT_BLOCKERS:-<!-- No blockers -->}

## Next Steps
${GT_NEXT_STEPS:-<!-- No next steps defined -->}

---
*Last updated: ${timestamp}*
"
    
    echo "$summary" > "$GT_MEMORY_DIR/context-summary.md"
    echo "✓ Context saved to $GT_MEMORY_DIR/context-summary.md"
}

# Record a learning
gt-memory-save-learning() {
    _gt_memory_init
    
    local learning="$1"
    local context="${2:-$GT_ACTIVE_BEAD}"
    local timestamp
    timestamp=$(date -Iseconds)
    
    if [ -z "$learning" ]; then
        echo "Usage: gt-memory-save-learning '<learning description>' [context]"
        return 1
    fi
    
    local entry="
## ${timestamp} - ${learning:0:50}

**Context:** ${context}
**Learning:** ${learning}
**Application:** <!-- TODO: When to apply this -->

"
    
    echo "$entry" >> "$GT_MEMORY_DIR/learnings.md"
    echo "✓ Learning recorded"
}

# Show recent learnings
gt-memory-show-learnings() {
    _gt_memory_init
    
    local n="${1:-10}"
    
    if [ ! -f "$GT_MEMORY_DIR/learnings.md" ]; then
        echo "No learnings recorded yet."
        return 0
    fi
    
    echo "=== Last $n Learnings ==="
    # Extract last n learning entries (each starts with ##)
    grep -n "^## " "$GT_MEMORY_DIR/learnings.md" | tail -$n | head -1 | cut -d: -f1 | {
        read start_line
        if [ -n "$start_line" ]; then
            tail -n +$start_line "$GT_MEMORY_DIR/learnings.md"
        else
            cat "$GT_MEMORY_DIR/learnings.md"
        fi
    }
}

# Record completed work
gt-memory-log-work() {
    _gt_memory_init
    
    local description="$1"
    local bead="${2:-$GT_ACTIVE_BEAD}"
    local pr="${3:-N/A}"
    local timestamp
    timestamp=$(date -Iseconds)
    
    local entry="- ${timestamp} | ${bead} | ${pr} | ${description}"
    echo "$entry" >> "$GT_MEMORY_DIR/work-log.md"
    echo "✓ Work logged"
}

# Create handoff notes (for context compaction)
gt-memory-handoff() {
    _gt_memory_init
    
    local timestamp
    timestamp=$(date -Iseconds)
    
    local handoff="# Context Handoff - ${timestamp}

## Session State
- Node: ${GT_NODE_ID:-unknown}
- Active bead: ${GT_ACTIVE_BEAD:-none}
- Work status: ${GT_WORK_STATUS:-unknown}

## Current Branch
\`\`\`
$(git status 2>/dev/null || echo 'Not in git repo')
\`\`\`

## Work In Progress
${GT_WIP_DESCRIPTION:-<!-- No WIP description -->}

## Decisions Made This Session
${GT_DECISIONS:-<!-- No decisions -->}

## Open Questions
${GT_OPEN_QUESTIONS:-<!-- No open questions -->}

## Recommended Next Actions
${GT_NEXT_STEPS:-<!-- No next steps -->}

## Files Modified (Uncommitted)
\`\`\`
$(git status --short 2>/dev/null || echo 'N/A')
\`\`\`

---
*Handoff created at: ${timestamp}*
*Next session: Review this file with \`cat ~/.gt-memory/handoff-notes.md\`*
"
    
    echo "$handoff" > "$GT_MEMORY_DIR/handoff-notes.md"
    echo "✓ Handoff notes created at $GT_MEMORY_DIR/handoff-notes.md"
    
    # Also save context summary
    gt-memory-save-context
}

# Load previous context at session start
gt-memory-load-context() {
    _gt_memory_init
    
    if [ -f "$GT_MEMORY_DIR/context-summary.md" ]; then
        echo "=== Previous Session Context ==="
        cat "$GT_MEMORY_DIR/context-summary.md"
        echo ""
    fi
    
    if [ -f "$GT_MEMORY_DIR/handoff-notes.md" ]; then
        echo "=== Handoff Notes Available ==="
        echo "Run: cat ~/.gt-memory/handoff-notes.md"
        echo ""
    fi
}

# Auto-save before exit (call this in EXIT trap)
gt-memory-auto-save() {
    # Only save if we have active work
    if [ -n "$GT_ACTIVE_BEAD" ]; then
        gt-memory-save-context
        gt-memory-log-work "Session ended" "$GT_ACTIVE_BEAD" "N/A"
    fi
}

# Show all memory status
gt-memory-status() {
    _gt_memory_init
    
    echo "=== GT Memory Status ==="
    echo "Memory directory: $GT_MEMORY_DIR"
    echo ""
    
    for file in context-summary.md learnings.md work-log.md handoff-notes.md; do
        if [ -f "$GT_MEMORY_DIR/$file" ]; then
            local size
            size=$(wc -l < "$GT_MEMORY_DIR/$file")
            local mtime
            mtime=$(stat -c %y "$GT_MEMORY_DIR/$file" 2>/dev/null | cut -d' ' -f1)
            echo "✓ $file ($size lines, last modified: $mtime)"
        else
            echo "✗ $file (not created)"
        fi
    done
}

# Initialize on source
_gt_memory_init

# Optional: Load context on shell start (uncomment to enable)
# gt-memory-load-context
