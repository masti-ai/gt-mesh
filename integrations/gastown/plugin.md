+++
name = "gt-mesh-sync"
description = "GT Mesh network sync — pulls messages, pushes updates, maintains heartbeat"

[gates.cooldown]
duration = "2m"
+++

# GT Mesh Sync Plugin (for steveyegge/gastown)

This plugin integrates GT Mesh into the original Gas Town daemon/dog system.

## Installation

Copy this file to your Gas Town plugins directory:

```bash
cp gt-mesh/integrations/gastown/plugin.md ~/gt/plugins/gt-mesh-sync/plugin.md
```

The daemon will auto-discover it and run it every 2 minutes via an idle dog.

## What to do

1. Run mesh sync:
```bash
GT_ROOT="$HOME/gt" bash "$HOME/gt/.gt-mesh/scripts/mesh-sync.sh"
```

2. Check for and deliver unread messages:
```bash
GT_ROOT="$HOME/gt" bash "$HOME/gt/.gt-mesh/scripts/mesh-inbox.sh" --unread
```

3. If critical (P0) messages found, send them to mayor's inbox:
```bash
gt mail send mayor/ -s "[mesh] <subject>" -m "<body>"
```

## Requirements

- GT Mesh installed at `~/.gt-mesh/` or `~/gt/.gt-mesh/`
- Dolt CLI installed
- DoltHub credentials configured (`dolt creds ls`)
- mesh.yaml exists at GT root
