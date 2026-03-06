---
name: gt-mesh
description: 'Operate a GT Mesh network — create, join, and manage collaborative Gas Town meshes. Use when asked to "start a mesh", "invite someone to the mesh", "check mesh status", "send a mesh message", "list mesh peers", or any cross-GT coordination task. This skill teaches AI agents how to operate in a federated Gas Town network.'
---

# GT Mesh — Network Operations Skill

This skill enables any AI agent running inside a Gas Town to operate as a
participant in a GT Mesh network — a federated collaborative coding platform.

## When to Use This Skill

Use when the user or system asks to:
- Start or initialize a mesh network
- Invite someone to join the mesh
- Join an existing mesh with an invite code
- Send messages to other Gas Towns
- Check mesh status, peers, or activity
- Create or claim shared beads
- Review incoming contributions
- Check the mesh feed
- Manage access control

## Prerequisites

- GT Mesh plugin installed (`.gt-mesh/` directory exists)
- DoltHub credentials configured (`dolt creds ls` shows active key)
- Gas Town running with mayor and daemon

## Core Concepts

### Roles
| Role | Description |
|------|-------------|
| **owner** | Mesh creator. Full control over rules, access, deletion |
| **admin** | Reviewer. Can merge PRs, approve/reject, manage write/read |
| **write** | Contributor. Can create beads, claim work, create PRs |
| **read** | Observer. Can view everything, send messages, cannot modify |

### Data Flow
All mesh data syncs through a shared DoltHub database (hub-and-spoke model).
Each GT syncs every 2 minutes. Messages, beads, claims, and findings flow
through the hub — never directly between GTs.

### Key Tables
| Table | Purpose |
|-------|---------|
| messages | Cross-GT mail |
| peers | Mesh registry (who's connected) |
| shared_beads | Work items visible across the mesh |
| claims | Who's working on what (race prevention) |
| invites | Invite codes and their status |
| access | Permission grants per GT per rig |
| mesh_rules | Governance rules |
| feed_events | Activity stream |

## Command Reference

### Initialization

```bash
# Create a new mesh (you become owner/coordinator)
gt mesh init --role coordinator

# Join an existing mesh
gt mesh join MESH-XXXX-YYYY
```

### Invites & Access

```bash
# Invite someone
gt mesh invite --role write --rigs project_a --expires 7d
# Output: MESH-K9XP-4LMN (share this code)

# List access
gt mesh access list

# Change someone's role
gt mesh access set <gt-id> --role admin

# Revoke access
gt mesh revoke <gt-id>

# Set up auto-approval for trusted worker
gt mesh auto-approve <gt-id> --rigs project_a --max-lines 100
```

### Communication

```bash
# Send cross-GT message
gt mesh send <gt-id> "subject" "body"

# Check inbox
gt mesh inbox

# Read a message
gt mesh read <message-id>
```

### Shared Work

```bash
# Create shared bead (visible across mesh)
bd create --mesh --rig project_a "Add dark mode"

# List shared beads
bd list --mesh
bd list --mesh --unclaimed

# Claim a bead (prevents others from taking it)
bd claim <bead-id>
```

### Review Gate

```bash
# View pending contributions from other GTs
gt mesh contributions

# Accept a contribution (becomes a normal bead, polecats can work it)
gt mesh accept <bead-id>

# Reject with reason
gt mesh reject <bead-id> --reason "Out of scope for this sprint"
```

### Mesh Feed

```bash
# View activity stream
gt mesh feed
gt mesh feed --since 1h
gt mesh feed --gt gt-docker
gt mesh feed --type claims
```

### Status & Management

```bash
# Mesh dashboard
gt mesh status

# List connected peers
gt mesh peers
gt mesh peers --online

# Mesh rules
gt mesh rules list
gt mesh rules set max_concurrent_claims 5  # owner only

# Force sync
gt mesh sync
```

## Workflow Patterns

### Pattern 1: Coordinator receives contribution

```
1. Mesh feed shows: "gt-friend created bead on project_a"
2. Run: gt mesh contributions
3. Review the bead details
4. Run: gt mesh accept <bead-id>
5. Run: gt sling <bead-id> <rig>  (polecat picks it up)
6. When done, contributor gets notified via mesh mail
```

### Pattern 2: Worker auto-claims work

```
1. Coordinator creates bead on shared rig
2. Worker's daemon detects unclaimed bead
3. Worker auto-claims (if auto_claim enabled in mesh.yaml)
4. Worker's mayor slings polecat
5. PR created, status syncs to mesh
6. Coordinator reviews and merges
```

### Pattern 3: Sending work to a specific GT

```
1. Run: gt mesh send gt-docker "Work: implement feature X" "Details..."
2. Or create bead and assign:
   bd create --mesh --rig project_a "Feature X"
   bd assign <bead-id> gt-docker
3. gt-docker sees assignment on next sync
```

## Configuration

Mesh config lives in `mesh.yaml` at the GT root. Key sections:
- `instance`: Your identity (id, name, role, owner)
- `dolthub`: DoltHub connection (org, database, sync interval)
- `rules`: Governance rules (branch format, review requirements)
- `access_control`: Permission hierarchy and auto-approve
- `shared_rigs`: Which rigs are visible on the mesh
- `context`: Shared findings/memory settings
- `feed`: Activity stream configuration
- `daemon`: Background sync settings

Full spec: `spec/mesh.yaml.reference` in the gt-mesh repo.

## Error Handling

| Error | Solution |
|-------|----------|
| "Not in a mesh" | Run `gt mesh init` or `gt mesh join` |
| "Permission denied" | Check your role with `gt mesh access list` |
| "Bead already claimed" | Another GT claimed first. Find unclaimed: `bd list --mesh --unclaimed` |
| "Invite expired" | Ask coordinator for new invite |
| "Sync failed" | Check DoltHub creds: `dolt creds ls`. Force sync: `gt mesh sync` |
| "Peer offline" | They haven't synced in >10 min. Check `gt mesh peers` |
