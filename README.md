<p align="center">
  <img src=".github/banner.png" alt="GT Mesh" width="100%" />
</p>

# GT Mesh

**Multi-agent orchestration framework for Claude Code**

GT Mesh connects multiple [Gas Town](https://github.com/steveyegge/gastown) instances into a federated coding network. Built on [Dolt](https://github.com/dolthub/dolt) (Git for data) and inspired by the [Wasteland](https://github.com/steveyegge/wasteland) federation protocol, GT Mesh gives every agent node a sovereign identity, a shared work board, and cryptographically attributable contributions.

[![Release](https://img.shields.io/github/v/release/masti-ai/gt-mesh?include_prereleases)](https://github.com/masti-ai/gt-mesh/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Stars](https://img.shields.io/github/stars/masti-ai/gt-mesh)](https://github.com/masti-ai/gt-mesh/stargazers)

---

## Why GT Mesh?

Claude Code is powerful for solo developers. But real software is built by teams. GT Mesh makes it so multiple people — each running their own Claude Code workspace — can coordinate AI agents across machines without sharing credentials, filesystem access, or API keys.

**The key idea:** Your workspace is sovereign. You keep full control. When someone joins your mesh, they can see your project and suggest work — but your agents execute it, on your terms.

### What sets GT Mesh apart

| Feature | GT Mesh | Git + GitHub | Slack + Jira |
|---------|---------|-------------|-------------|
| AI agents coordinate automatically | Yes | No | No |
| Contributor never needs your credentials | Yes | Partial (PATs) | No |
| Work flows through a review gate | Yes | Yes (PRs) | No |
| Reputation is cryptographically attributable | Yes | No | No |
| Time-limited access with invite tokens | Yes | No | No |
| Config-driven behavioral roles | Yes | No | No |

---

## How It Works

```
You (coordinator)                         Friend (contributor)
     |                                          |
  gt mesh init                             gt mesh join MESH-A7K9
     |                                          |
  gt mesh invite ----> MESH-A7K9 ----------> Pastes code
     |                                          |
     |                                    Creates tasks (beads)
     |                                          |
  Coordinator reviews <-- Dolt sync ------ "Add dark mode"
     |
  Accepts -> worker agent builds it
     |
  "PR merged" ------- Dolt sync ----------> Gets notified
```

All communication flows through a shared Dolt database. No direct connections between nodes. No firewall rules. No VPNs.

### Architecture

```
                    +-------------------------+
                    |    Dolt Hub Database     |
                    |                         |
                    |  messages | peers       |
                    |  channels | access      |
                    |  invites  | findings    |
                    +------------+------------+
                                |
                 +--------------+--------------+
                 |              |              |
            +----v----+   +----v----+   +----v----+
            |  Node A  |   |  Node B  |   |  Node C  |
            | (coord.) |   | (worker) |   | (contri- |
            |          |   |          |   |  butor)  |
            +----------+   +----------+   +----------+
                 ^              ^              ^
            sync 2min      sync 2min      sync 2min
```

Every node syncs with ONE central Dolt database — not with each other. This scales linearly: adding a node is just one more sync client, not N^2 connections.

---

## Quick Start

### Install

```bash
# One command (inside your Claude Code workspace)
curl -fsSL https://raw.githubusercontent.com/masti-ai/gt-mesh/main/install.sh | bash

# Or clone manually
git clone https://github.com/masti-ai/gt-mesh.git .gt-mesh && bash .gt-mesh/install.sh
```

The installer auto-detects your platform:
- **steveyegge/gastown** — installs daemon plugin
- **gasclaw** (any variant) — installs OpenClaw skill
- **Generic workspace** — installs scripts only

### Initialize a mesh

```bash
gt mesh init --role coordinator --github your-username
```

This creates `mesh.yaml` (your mesh identity), connects to Dolt, and registers your node as a peer.

### Invite someone

```bash
gt mesh invite --role contributor --expires 7d
# Output: MESH-A7K9-XPLN (share this code)
```

Invites are **time-limited tokens**. When they expire, access is revoked automatically.

### Join a mesh

```bash
gt mesh join MESH-A7K9-XPLN
# Connects, syncs state, ready to collaborate
```

---

## Behavioral Roles

Every node in a mesh has a **behavioral role** that determines what it does — not just what it *can* do, but what it *will* do. Configured in `mesh.yaml` and enforced deterministically.

| Role | Creates tasks | Writes code | Assigns work | Reviews PRs | Merges |
|------|:---:|:---:|:---:|:---:|:---:|
| **Planner** | Yes | Never | Yes | Yes | Yes |
| **Worker** | No | Yes | No | No | Never |
| **Reviewer** | No | No | No | Yes | Yes |
| **Contributor** | Yes | No | No | No | No |

```yaml
# mesh.yaml
behavioral_role:
  this_gt: "planner"
  behavior:
    writes_code: false        # Hard block — config-enforced
    delegates_always: true    # Must send work to workers
  peer_roles:
    worker-1:
      role: "worker"
      specialties: ["backend", "infrastructure"]
```

A planner node will **never** write code — it breaks tasks into work items and delegates. A worker node will **never** merge its own PRs. This eliminates the need to repeatedly instruct agents about their role.

---

## Formulas

Formulas are TOML-based workflow definitions that describe multi-step agent processes. They are the building blocks of how work gets done in a mesh.

### Example: `shiny.formula.toml`

```toml
description = "Engineer in a Box - design before you code, review before you ship"
formula = "shiny"
type = "workflow"
version = 1

[[steps]]
id = "design"
title = "Design {{feature}}"
description = "Think about architecture before writing code."
acceptance = "Design doc committed"

[[steps]]
id = "implement"
title = "Implement {{feature}}"
needs = ["design"]
acceptance = "All files modified/created and committed"

[[steps]]
id = "review"
title = "Review implementation"
needs = ["implement"]
acceptance = "Self-review complete, no obvious bugs"

[[steps]]
id = "test"
title = "Test {{feature}}"
needs = ["review"]
acceptance = "All tests pass, no regressions"

[[steps]]
id = "submit"
title = "Submit for merge"
needs = ["test"]
acceptance = "Clean git status, pushed to feature branch"

[vars]
[vars.feature]
description = "The feature being implemented"
required = true
```

### Key concepts

- **Steps** define the workflow stages, each with acceptance criteria
- **`needs`** creates a dependency graph — steps run in order
- **`{{variables}}`** are interpolated at runtime from `[vars]`
- **Formulas are composable** — reference other formulas as sub-steps

### Included formulas

| Formula | Purpose |
|---------|---------|
| `shiny` | Full engineering workflow: design, implement, review, test, submit |
| `code-review` | Structured code review process |
| `design` | Architecture design phase |
| `security-audit` | Security review checklist |
| `mol-polecat-work` | Worker agent task execution |
| `mol-convoy-*` | Multi-agent convoy coordination |
| `towers-of-hanoi-*` | Benchmarking formulas for agent capability testing |

---

## Access Control

Four-level permission hierarchy:

```
OWNER --- Full control: rules, access, delete, transfer
  |
ADMIN --- Merge PRs, approve/reject, manage contributors
  |
WRITE --- Create tasks, claim work, create PRs, publish findings
  |
READ ---- View everything, send messages, cannot modify
```

### Time-limited access

```bash
# 24-hour token for a code review session
gt mesh invite --role read --expires 24h

# 2-week sprint token for a contractor
gt mesh invite --role write --expires 14d

# Permanent token for a co-founder
gt mesh invite --role admin --expires never

# Revoke any peer immediately
gt mesh revoke <peer-id>
```

---

## Commands

### Available now

```bash
gt mesh init                          # Initialize mesh node
gt mesh status                        # Dashboard with peers + unread count
gt mesh send <id> "subj" "body"       # Send cross-node message
gt mesh inbox [--all]                 # Check incoming messages
gt mesh sync                          # Force sync with Dolt
gt mesh help                          # Show all commands
```

### Coming soon

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
| [steveyegge/gastown](https://github.com/steveyegge/gastown) | Daemon plugin (TOML frontmatter) | Yes |
| [gastown-publish/gasclaw](https://github.com/gastown-publish/gasclaw) | OpenClaw skill (YAML frontmatter) | Yes |
| Any Claude Code workspace | Shell scripts | Yes |

The installer detects your platform and installs the correct integration automatically.

---

## Project Structure

```
gt-mesh/
├── scripts/              # Core mesh commands (bash)
│   ├── mesh.sh           # Main dispatcher
│   ├── mesh-init.sh      # Initialize mesh node
│   ├── mesh-status.sh    # Dashboard
│   ├── mesh-send.sh      # Cross-node messaging
│   ├── mesh-inbox.sh     # Read messages
│   └── mesh-sync.sh      # Dolt sync
├── formulas/             # TOML workflow definitions
│   ├── shiny.formula.toml
│   ├── code-review.formula.toml
│   ├── security-audit.formula.toml
│   └── ...               # 40+ formulas
├── blueprints/           # Node configuration templates
├── packs/                # Portable config packs
├── integrations/
│   ├── gastown/          # steveyegge/gastown plugin
│   └── gasclaw/          # gasclaw skill
├── skills/               # Claude Code skills for AI agents
├── spec/                 # mesh.yaml reference specification
├── docs/                 # Full documentation
├── templates/            # PR and issue templates
├── docker/               # Container deployment
└── install.sh            # One-command installer
```

---

## Documentation

- [Architecture](docs/ARCHITECTURE.md) — Dolt backbone, sync model, database schema
- [Manifesto](docs/MANIFESTO.md) — Design principles and non-negotiables
- [mesh.yaml Reference](spec/mesh.yaml.reference) — Complete configuration spec
- [Contributing](CONTRIBUTING.md) — How to contribute to GT Mesh

---

## Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

**Quick version:**

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/amazing-thing`)
3. Make your changes
4. Run any existing tests
5. Submit a PR targeting the `dev` branch

All commits must include proper attribution:
```
Co-Authored-By: Your Name <your-github-email>
```

---

## Related Projects

- [Gas Town](https://github.com/steveyegge/gastown) — The multi-agent workspace manager GT Mesh extends
- [Wasteland](https://github.com/steveyegge/wasteland) — Federation protocol for Gas Towns
- [Gasclaw](https://github.com/gastown-publish/gasclaw) — Single-container Gas Town deployment
- [Beads](https://github.com/steveyegge/beads) — Git-backed issue tracking
- [Dolt](https://github.com/dolthub/dolt) — Git-for-data database powering the mesh backbone

---

## Created By

**[Pratham Bhatnagar](https://github.com/pratham-bhatnagar)** — creator and lead architect of GT Mesh.

Built by [Pratham Bhatnagar](https://github.com/pratham-bhatnagar) and a team of AI agents at [Deepwork AI](https://github.com/masti-ai).

### Contributors

<!-- ALL-CONTRIBUTORS-LIST:START -->
<a href="https://github.com/pratham-bhatnagar"><img src="https://github.com/pratham-bhatnagar.png" width="60px" alt="Pratham Bhatnagar" style="border-radius:50%"/></a>
<!-- ALL-CONTRIBUTORS-LIST:END -->

AI agents (Claude, Kimi, MiniMax) contribute code, reviews, and coordination under human supervision.

---

## Support

If you find GT Mesh useful, please consider giving it a star — it helps others discover the project.

[![Star on GitHub](https://img.shields.io/github/stars/masti-ai/gt-mesh?style=social)](https://github.com/masti-ai/gt-mesh)

---

## License

MIT — see [LICENSE](LICENSE) for details.

---

<p align="center">
  Created by <a href="https://github.com/pratham-bhatnagar">Pratham Bhatnagar</a> | <a href="https://github.com/masti-ai">Deepwork AI</a> | Powered by <a href="https://github.com/steveyegge/gastown">Gas Town</a> | Federation via <a href="https://github.com/steveyegge/wasteland">Wasteland</a>
</p>
