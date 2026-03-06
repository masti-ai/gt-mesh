# GT Worker Template

**Purpose:** Replicable Gas Town worker instance for the Deepwork-AI agent network.

**What is this?**
A complete, copy-paste template for spawning new GT workers. Each worker connects to the parent GT (`gt-local`) and picks up work via GitHub Issues.

## Quick Start

```bash
# 1. Clone this template
cp -r templates/gt-worker ~/my-new-gt-worker

# 2. Customize town.json with your instance ID
vim ~/my-new-gt-worker/mayor/town.json
# Change: "instance_id": "gt-worker-001" (unique name)

# 3. Set up GitHub auth
gh auth login

# 4. Initialize GT
cd ~/my-new-gt-worker
gt init

# 5. Start services
gt daemon start
```

## Files Overview

```
templates/gt-worker/
├── mayor/
│   ├── town.json           # Instance identity (EDIT THIS)
│   ├── rigs.json           # Repos you work on
│   └── daemon.json         # Patrol configuration
├── agents/
│   ├── chad-ji/            # Master orchestrator
│   ├── muhchodu/           # Business operator (👔)
│   └── gigagirl/           # Content brainstormer (🎨)
├── settings/
│   ├── config.json         # Model allocation
│   └── escalation.json     # Alert routing
├── memory/
│   ├── MISTAKES.md         # Network-wide learnings
│   ├── SHARED_KNOWLEDGE.md # Cross-GT knowledge
│   └── RULES.md            # Hard constraints
└── README.md               # This file
```

## Network Knowledge Sharing

This template connects to the **Deepwork-AI GT Network**. Knowledge flows:

1. **MISTAKES.md** — Shared across all GTs. Document failures, fixes, lessons.
2. **SHARED_KNOWLEDGE.md** — Tips, tricks, discoveries that help all workers.
3. **RULES.md** — Hard constraints that ALL GTs must follow.

**Sync mechanism:**
- Parent GT (`gt-local`) maintains master copies
- Workers pull updates periodically
- Changes pushed back via PRs to `gtconfig`

## Customization Checklist

When creating a new worker:

- [ ] Update `mayor/town.json` with unique `instance_id`
- [ ] Update `mayor/rigs.json` with repos you'll work on
- [ ] Add your GitHub token
- [ ] Configure Telegram bot (optional)
- [ ] Join the GT network by notifying parent GT

## Agent Roles

### Chad Ji (👽)
Master orchestrator. Your main interface. Delegates to specialists.

### Muhchodu (👔)
Business operator. Metrics, reports, decisions. No fluff.

### GigaGirl (🎨)
Content brainstormer. Ideas, writing, creativity. Energy.

## Communication Protocol

```
Parent GT (gt-local)          Your GT (this worker)
        |                               |
        |  GitHub Issue:                |
        |    gt-to:<your-id>            |
        |    gt-status:pending          |
        |------------------------------>|
        |                        Claim, work, PR
        |<------------------------------|
        |  Review, merge                |
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Can't auth GitHub | Run `gh auth login` |
| Dolt not running | `dolt sql-server --host 0.0.0.0 --port 3307` |
| No work assigned | Check `gt-to:<your-id>` labels on repos |
| Want more agents | Copy from `agents/` template, customize SOUL.md |

---
**Part of:** Deepwork-AI GT Network  
**Template version:** 1.0  
**Last updated:** 2026-03-06
