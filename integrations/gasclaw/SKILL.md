---
name: gt-mesh-sync
description: 'GT Mesh network sync — keeps this Gas Town connected to the mesh. Pulls messages, pushes updates, and maintains heartbeat with DoltHub backbone. Runs automatically every 2 minutes.'
---

# GT Mesh Sync Skill (for gasclaw)

This skill integrates GT Mesh into gasclaw's OpenClaw skill system.

## Installation

Copy this directory to your OpenClaw skills:

```bash
cp -r gt-mesh/integrations/gasclaw/ ~/.openclaw/skills/gt-mesh-sync/
```

## What to do

Run the mesh sync and inbox scripts:

```bash
GT_ROOT="${GT_ROOT:-/workspace}" bash "$GT_ROOT/.gt-mesh/scripts/mesh-sync.sh"
GT_ROOT="${GT_ROOT:-/workspace}" bash "$GT_ROOT/.gt-mesh/scripts/mesh-inbox.sh" --unread
```

## When to run

- Every 2 minutes (via cron or daemon)
- On startup (ensure mesh connection)
- When user asks to check mesh status

## Requirements

- GT Mesh installed (`.gt-mesh/` directory)
- Dolt CLI installed
- mesh.yaml at workspace root
