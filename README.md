# gtconfig

Production Gas Town configuration. Clone this into a new GT instance to replicate the Deepwork AI multi-agent engineering system.

## What is Gas Town?

Gas Town is a multi-agent software engineering system. One human founder, 200+ AI agents, shipping production code 24/7. This repo contains the configuration files, templates, and conventions that make it work.

## Quick Start

```bash
# 1. Initialize a new Gas Town
gt init my-town

# 2. Copy config files into your GT
cp -r gtconfig/mayor/ my-town/mayor/
cp -r gtconfig/settings/ my-town/settings/
cp -r gtconfig/deacon/ my-town/deacon/
cp gtconfig/CLAUDE.md my-town/CLAUDE.md

# 3. Edit town.json with your instance ID
vim my-town/mayor/town.json
# Change instance_id, owner, name

# 4. Edit rigs.json with your repos
vim my-town/mayor/rigs.json

# 5. Prime the GT
cd my-town && gt prime
```

## Repo Structure

```
gtconfig/
├── README.md                    You are here
├── CLAUDE.md                    Master instruction file (read by ALL agents)
│
├── mayor/                       Mayor (coordinator) config
│   ├── town.json               GT instance identity
│   ├── rigs.json.template      Rig-to-repo mapping (edit for your repos)
│   ├── daemon.json             Daemon patrol config (heartbeat, dogs, intervals)
│   ├── overseer.json.template  Human overseer identity
│   └── multi-gt-worker-instructions.md
│                                Handoff doc for worker GT instances
│
├── settings/                    Town-wide settings
│   ├── config.json             Agent model config (which model for which role)
│   └── escalation.json         Escalation routing (critical/high/medium/low)
│
├── deacon/                      Deacon (supervisor) config
│   └── dogs/                   Dog patrol directories (auto-populated)
│
├── formulas/                    Bead formulas (mol templates for automation)
│   └── *.formula.toml          All production formulas
│
├── templates/                   Reusable templates
│   ├── repo/
│   │   ├── AGENTS.md           Agent instructions for repos
│   │   ├── CONTRIBUTING.md     Contribution guidelines template
│   │   └── .github/
│   │       └── PULL_REQUEST_TEMPLATE.md
│   └── pr/
│       ├── release-pr.md       dev -> main PR template
│       └── release-notes.md    GitHub release notes template
│
├── memory/                      Mayor memory templates
│   ├── MEMORY.md               Persistent memory structure
│   └── mistakes.md             Incident log template
│
├── skills/                      Claude Code skills
│   └── excalidraw-diagram-generator/
│       ├── SKILL.md             Skill definition
│       ├── scripts/             Python helper scripts
│       ├── references/          Schema + element docs
│       └── templates/           Starter diagram templates
│
├── plugins/                     Claude Code plugins
│   └── README.md                Plugin registry (add yours here)
│
└── agents/                      Agent role configs
    ├── mayor.md                 Mayor role description
    ├── worker.md                Worker GT role description
    └── reviewer.md              Reviewer role description
```

## Configuration Files

### CLAUDE.md (the brain)

The master instruction file read by every agent in the GT. Contains:
- Release workflow (dev -> main, consolidated PRs)
- GitHub sync rules (beads -> issues, epic-level sync)
- Deployment URL management (service registry beads)
- GitHub organization management
- Project management (Kanban + Roadmap boards)
- Releases & versioning (semver, release notes)
- Multi-GT coordination (parent/worker roles, issue lifecycle)

### town.json (identity)

```json
{
  "instance_id": "gt-local",     // Unique ID for this GT instance
  "github_sync": {
    "enabled": true,
    "accept_tasks_from": ["gt-docker"]  // Which GTs can assign work here
  }
}
```

### settings/config.json (model allocation)

Controls which AI model powers each role:
- **Mayor** (coordinator): Opus — needs deep reasoning
- **Polecat** (worker): Opus — needs to write good code
- **Deacon/Witness/Refinery** (supervisors): Sonnet — cost-effective for monitoring
- **Dog** (patrols): Sonnet — lightweight checks

### daemon.json (automation)

Configures the daemon's patrol cycle:
- **Heartbeat**: 3-minute pulse
- **Refinery**: 5-minute code quality patrols
- **Witness**: 5-minute state verification
- **Doctor dog**: 5-minute health checks
- **Wisp reaper**: 30-minute cleanup of stale wisps
- **Backup**: 15-minute Dolt + JSONL backups

## Skills & Plugins

### Skills (`.claude/skills/`)

Skills extend Claude Code with domain-specific capabilities. Copy the `skills/` directory into your GT's `.claude/skills/` path.

**Included skills:**
- **excalidraw-diagram-generator** — Generate architecture diagrams, flowcharts, mind maps, ER diagrams, and more as `.excalidraw` files from natural language descriptions

### Plugins

The `plugins/` directory holds any custom plugins. Currently a placeholder — add your own as needed.

### Installation

```bash
# Copy skills into your GT's Claude config
mkdir -p my-town/.claude/skills
cp -r gtconfig/skills/* my-town/.claude/skills/

# Copy plugins
cp -r gtconfig/plugins/ my-town/plugins/
```

## Multi-GT Setup

This GT is designed to coordinate multiple GT instances:

| Role | Description |
|------|-------------|
| **Parent (gt-local)** | Creates issues, reviews PRs, merges, manages releases |
| **Worker (gt-docker)** | Picks up issues, writes code, creates PRs to `dev` |

### Adding a new worker GT

1. Set up the new GT instance
2. Copy `mayor/multi-gt-worker-instructions.md` to the worker
3. Worker configures its `town.json` with a unique `instance_id`
4. Worker adds the CLAUDE.md worker rules to its config
5. Parent creates issues with `gt-to:<worker-id>` label
6. Worker polls, claims, branches, PRs, done

### Communication

All communication happens through GitHub:
- **Issues** with `gt-task` labels for work assignments
- **PRs** with `needs-review` label for code delivery
- **Comments** on issues/PRs for status updates
- **Labels** for lifecycle tracking (`pending` -> `claimed` -> `done`)

## Customization

### For a new project/org

1. Update `CLAUDE.md`:
   - Change org name from `Deepwork-AI` to yours
   - Update repo list
   - Update project board numbers
   - Update service registry bead IDs

2. Update `mayor/rigs.json.template`:
   - Add your repos with correct git URLs and bead prefixes

3. Update `settings/config.json`:
   - Adjust model allocation based on your budget
   - Sonnet-only config works fine for cost savings

4. Create labels on your repos:
   ```bash
   # Run this for each repo
   for LABEL in "gt-task" "gt-from:gt-local" "gt-to:gt-docker" \
     "gt-status:pending" "gt-status:claimed" "gt-status:done" \
     "needs-review" "approved" "priority:p0" "priority:p1" "priority:p2"; do
     gh label create "$LABEL" --repo your-org/your-repo
   done
   ```

## License

MIT. Use this to build your own army.

---

## GT Worker Template (NEW)

**Rapidly spawn new worker GTs with full agent configuration.**

```bash
# Clone the template
cp -r gtconfig/templates/gt-worker ~/my-new-worker
cd ~/my-new-worker

# Customize
vim mayor/town.json  # Change instance_id
vim mayor/rigs.json  # Set your repos

# Initialize
gt init .
gt prime
```

### What's Included

- **3 Pre-configured Agents:**
  - 👽 Chad Ji (master orchestrator)
  - 👔 Muhchodu (business operator)
  - 🎨 GigaGirl (content brainstormer)
  
- **Complete Setup:**
  - Mayor, daemon, settings configs
  - Agent SOUL.md, IDENTITY.md, USER.md
  - HEARTBEAT.md for periodic checks

### Template Location

```
templates/gt-worker/
├── README.md                 # Quick start guide
├── mayor/
│   ├── town.json            # Edit: instance_id
│   ├── rigs.json            # Edit: your repos
│   └── daemon.json          # Patrol config
├── agents/
│   ├── chad-ji/             # Master orchestrator
│   ├── muhchodu/            # Business agent
│   └── gigagirl/            # Content agent
└── memory/                  # Network knowledge
    ├── MISTAKES.md          # Shared learnings
    ├── SHARED_KNOWLEDGE.md  # Tips & tricks
    └── RULES.md             # Hard constraints
```

---

## GT Network Knowledge Sharing

**All GT instances share knowledge.**

When you spawn a new worker from the template, it gets:

1. **MISTAKES.md** — Documented failures and fixes from all GTs
2. **SHARED_KNOWLEDGE.md** — Tips, tricks, quick reference
3. **RULES.md** — Absolute constraints (never break these)

### How Knowledge Flows

```
Parent GT (gt-local)          Worker GTs (gt-docker, gt-worker-001, etc.)
        |                               |
        |  Maintains master copies      |
        |  of MISTAKES.md               |
        |  SHARED_KNOWLEDGE.md          |
        |  RULES.md                     |
        |------------------------------>|
        |                        Workers pull updates
        |
        <------------------------------|
                 Workers push new learnings via PRs
```

### Contributing Knowledge

When you learn something:

1. Update `templates/gt-worker/memory/MISTAKES.md` or `SHARED_KNOWLEDGE.md`
2. Commit and push to `gtconfig`
3. Other GTs pull the updates

**Format for MISTAKES.md:**
```markdown
## YYYY-MM-DD: Brief description

**Instance:** gt-docker
**Context:** What you were doing
**Mistake:** What went wrong
**Fix:** How you fixed it
**Lesson:** What others should know
```

---

Built by [Deepwork AI](https://github.com/Deepwork-AI) with [Gas Town](https://github.com/freebird-ai).
