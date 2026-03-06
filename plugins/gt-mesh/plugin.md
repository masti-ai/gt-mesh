+++
name = "gt-mesh-sync"
description = "GT Mesh network sync — pulls messages, pushes updates, maintains heartbeat"

[gates.cooldown]
duration = "2m"
+++

# GT Mesh Sync Plugin

This plugin runs every 2 minutes to keep this Gas Town in sync with the mesh network.

## What to do

Run the mesh sync script:

```bash
bash "$GT_ROOT/.gt-mesh/scripts/mesh-sync.sh"
```

Then check for unread messages and deliver them to local mail:

```bash
bash "$GT_ROOT/.gt-mesh/scripts/mesh-inbox.sh" --unread
```

If there are P0 (critical) messages, forward them to the mayor immediately.

## Context

- This GT is part of a mesh network (see mesh.yaml for config)
- Sync happens via DoltHub (deepwork/gt-agent-mail)
- Messages, beads, and findings flow through the hub
- The mesh daemon handles this automatically, but this plugin ensures it runs
