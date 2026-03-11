# GT Mesh

**The collaboration protocol for Gas Town.**

GT Mesh connects multiple [Gas Town](https://github.com/steveyegge/gastown) instances into a federated coding network. Built on [DoltHub](https://www.dolthub.com/) (Git for data) and inspired by the [Wasteland](https://github.com/steveyegge/wasteland) federation protocol, GT Mesh gives every Gas Town a sovereign identity, a shared work board, and cryptographically attributable contributions.

[![Release](https://img.shields.io/github/v/release/Deepwork-AI/gt-mesh?include_prereleases)](https://github.com/Deepwork-AI/gt-mesh/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## Why GT Mesh?

Gas Town is powerful for solo developers. But real software is built by teams. GT Mesh makes it so multiple people — each running their own Gas Town — can work together without sharing credentials, filesystem access, or API keys.

**The key idea:** Your Gas Town is sovereign. You keep full control. When someone joins your mesh, they can see your project and suggest work — but your agents execute it, on your terms.

### What sets GT Mesh apart

| Feature | GT Mesh | Git + GitHub | Slack + Jira |
|---------|---------|-------------|-------------|
| AI agents coordinate automatically | Yes | No | No |
| Contributor never needs your credentials | Yes | Partial (PATs) | No |
| Work flows through a review gate | Yes | Yes (PRs) | No |
| Reputation is cryptographically attributable | Yes (via Wasteland stamps) | No | No |
| Time-limited access with invite tokens | Yes | No | No |
| Config-driven behavioral roles | Yes | No | No |

---

## How It Works

```
You (coordinator)                         Friend (contributor)
     │                                          │
  gt mesh init                             gt mesh join MESH-A7K9
     │                                          │
  gt mesh invite ──► MESH-A7K9 ──────────► Pastes code
     │                                          │
     │                                    Creates beads (tasks)
     │                                          │
  Mayor reviews ◄── DoltHub sync ─────── "Add dark mode"
     │
  Accepts → polecat builds it
     │
  "PR merged" ──── DoltHub sync ────────► Gets notified
```

All communication flows through a shared DoltHub database. No direct connections between Gas Towns. No firewall rules. No VPNs.

---

## Network Access (Tailscale)

| Service | Tailscale URL |
|---------|--------------|
| Gitea | http://100.108.196.44:3300 |
| LiteLLM | http://100.108.196.44:4000 |
| Command Center | http://100.108.196.44:3100 |
| Planogram Dashboard | http://100.108.196.44:3000 |
| Planogram API | http://100.108.196.44:8003 |
| ALC AI Dashboard | http://100.108.196.44:3006 |
| ALC AI API | http://100.108.196.44:8006 |

## Quick Start

### Install

```bash
# One command (from inside your Gas Town)
curl -fsSL https://raw.githubusercontent.com/Deepwork-AI/gt-mesh/dev/install.sh | bash

# Or clone manually
git clone https://github.com/Deepwork-AI/gt-mesh.git .gt-mesh && bash .gt-mesh/install.sh
```

The installer auto-detects your platform:
- **steveyegge/gastown** → installs daemon plugin (`plugins/gt-mesh-sync/plugin.md`)
- **gasclaw** (any variant) → installs OpenClaw skill (`skills/gt-mesh-sync/SKILL.md`)
- **Generic GT** → installs scripts only

### Initialize

```bash
gt mesh init --role coordinator --github your-username
```

This creates `mesh.yaml` (your mesh identity), connects to DoltHub, and registers your Gas Town as a peer.

### Invite someone

```bash
gt mesh invite --role contributor --expires 7d
# Output: MESH-A7K9-XPLN (share this code)
```

Invites are **time-limited tokens**. When they expire, access is revoked automatically. You can create:
- **Permanent tokens** — `--expires never` (for trusted long-term collaborators)
- **Session tokens** — `--expires 4h` (for a single pairing session)
- **Sprint tokens** — `--expires 14d` (for a development sprint)

### Join (friend's side)

```bash
gt mesh join MESH-A7K9-XPLN
# Connects, syncs state, can see shared rigs
```

---

## Behavioral Roles

Every Gas Town in a mesh has a **behavioral role** that determines what it does — not just what it *can* do, but what it *will* do. This is configured in `mesh.yaml` and enforced deterministically.

| Role | Creates tasks | Writes code | Assigns work | Reviews PRs | Merges |
|------|:---:|:---:|:---:|:---:|:---:|
| **Planner** | Yes | **Never** | Yes | Yes | Yes |
| **Worker** | No | **Yes** | No | No | **Never** |
| **Reviewer** | No | No | No | Yes | Yes |
| **Contributor** | Yes | No | No | No | No |

```yaml
# mesh.yaml
behavioral_role:
  this_gt: "planner"           # This GT plans and delegates
  behavior:
    writes_code: false          # HARD BLOCK — config-enforced
    delegates_always: true      # Must send work to workers
  peer_roles:
    gt-docker:
      role: "worker"
      specialties: ["backend", "infrastructure"]
```

A planner Gas Town will **never** write code itself — it breaks tasks into beads and sends them to workers. A worker Gas Town will **never** merge its own PRs — it creates branches, writes code, and waits for review. This eliminates the need to repeatedly tell agents their role.

---

## Access Control

Four-level permission hierarchy, inspired by [Wasteland](https://github.com/steveyegge/wasteland)'s trust model:

```
OWNER ─── Full control: rules, access, delete, transfer
  │
ADMIN ─── Merge PRs, approve/reject, manage contributors
  │
WRITE ─── Create beads, claim work, create PRs, publish findings
  │
READ ──── View everything, send messages, cannot modify
```

### Time-Limited Access (Invite Tokens)

```bash
# Create a 24-hour access token for a code review session
gt mesh invite --role read --expires 24h
# → MESH-R4KP-7WXN

# Create a 2-week sprint token for a contractor
gt mesh invite --role write --rigs my_project --expires 14d
# → MESH-W8JL-3MPQ

# Create a permanent token for a co-founder
gt mesh invite --role admin --expires never
# → MESH-A2NF-9YBC

# Revoke any peer immediately
gt mesh revoke gt-friend
```

---

## Federation & Wasteland Integration

GT Mesh builds on the [Wasteland federation protocol](https://github.com/steveyegge/wasteland):

| Wasteland Concept | GT Mesh Equivalent | Purpose |
|-------------------|-------------------|---------|
| **HOP URI** (`hop://email/handle/`) | Mesh peer identity | Unique, routable identity for every GT |
| **Wanted board** | Shared beads | Cross-GT work items with claim system |
| **Completions** | PR submissions | Verifiable evidence of work done |
| **Stamps** | Reputation tracking | Cryptographically attributable quality ratings |
| **Rigs table** | Peers table | Registry of all connected Gas Towns |
| **Fork-based federation** | DoltHub sync | Sovereign data with shared commons |
| **`wl` CLI** | `gt mesh` CLI | Same patterns, different scope |

Use both together:

```bash
# Post work to the Wasteland wanted board
gt wl post --title "Add dark mode" --type feature --priority 2

# Or use gt mesh for direct GT-to-GT coordination
gt mesh send gt-docker "Build dark mode" "See issue #15"
```

Wasteland is the **public commons** (open to all rigs). GT Mesh is **private collaboration** (invite-only). They share the same DoltHub infrastructure and can interoperate.

---

## Commands

### Working (tested, available now)

```bash
gt mesh init                          # Initialize mesh node
gt mesh status                        # Dashboard with peers + unread count
gt mesh send <gt-id> "subj" "body"    # Send cross-GT message
gt mesh inbox [--all]                 # Check incoming messages
gt mesh sync                          # Force sync with DoltHub
gt mesh help                          # Show all commands
```

### Coming Soon

```bash
gt mesh invite [--role R] [--expires D]  # Generate invite token
gt mesh join <code>                      # Join with invite token
gt mesh access list                      # Show access table
gt mesh rules list                       # View governance rules
gt mesh feed [--since 1h]               # Activity stream
gt mesh daemon start|stop|status         # Background sync
```

---

## Platform Compatibility

GT Mesh works as a plugin in **every Gas Town variant**:

| Platform | Integration | Auto-detected |
|----------|------------|:---:|
| [steveyegge/gastown](https://github.com/steveyegge/gastown) | Daemon plugin (`plugin.md`, TOML frontmatter) | Yes |
| [gastown-publish/gasclaw](https://github.com/gastown-publish/gasclaw) | OpenClaw skill (`SKILL.md`, YAML frontmatter) | Yes |
| [Deepwork-AI/gasclaw](https://github.com/Deepwork-AI/gasclaw) | OpenClaw skill (`SKILL.md`, YAML frontmatter) | Yes |

The installer detects your platform and installs the correct integration automatically.

---

## Project Structure

```
gt-mesh/
├── scripts/              # Core mesh commands (bash)
│   ├── mesh.sh           # Main dispatcher
│   ├── mesh-init.sh      # Initialize mesh node
│   ├── mesh-status.sh    # Dashboard
│   ├── mesh-send.sh      # Cross-GT messaging
│   ├── mesh-inbox.sh     # Read messages
│   └── mesh-sync.sh      # Force sync
├── integrations/
│   ├── gastown/           # steveyegge/gastown plugin
│   └── gasclaw/           # gasclaw skill
├── plugins/               # GT daemon plugins
├── skills/                # Claude Code skills for AI agents
├── spec/                  # mesh.yaml reference specification
├── docs/                  # Full documentation
├── tests/                 # Stress test results
└── install.sh             # One-command installer
```

---

## Documentation

- [Full Documentation](docs/DOCUMENTATION.md) — Setup, lifecycle, access control, rules, scaling
- [Architecture](docs/ARCHITECTURE.md) — DoltHub backbone, sync model, schema
- [Manifesto](docs/MANIFESTO.md) — Founder's principles and non-negotiables
- [mesh.yaml Reference](spec/mesh.yaml.reference) — Complete configuration spec
- [Contributing](CONTRIBUTING.md) — How to contribute to GT Mesh

---

## Related Projects

- [Gas Town](https://github.com/steveyegge/gastown) — The multi-agent workspace manager GT Mesh extends
- [Wasteland](https://github.com/steveyegge/wasteland) — Federation protocol for Gas Towns (public commons)
- [Gasclaw](https://github.com/gastown-publish/gasclaw) — Single-container Gas Town deployment
- [Beads](https://github.com/steveyegge/beads) — Git-backed issue tracking used by GT Mesh
- [Dolt](https://github.com/dolthub/dolt) — Git-for-data database powering the mesh backbone

---

## License

MIT

---

Built by [Deepwork AI](https://github.com/Deepwork-AI) • Powered by [Gas Town](https://github.com/steveyegge/gastown) • Federation via [Wasteland](https://github.com/steveyegge/wasteland)
