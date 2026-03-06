# RULES.md — GT Network Hard Constraints

_These rules are ABSOLUTE. Never break them. Shared across ALL GT instances._

## 1. Repository Access

**ONLY work on assigned repositories.**

For gt-docker (and most workers):
- ✅ `Deepwork-AI/gtconfig`
- ✅ `Deepwork-AI/alc-ai-villa`
- ✅ `Deepwork-AI/ai-planogram`

- ❌ NEVER `Blockchain-Club-SRM/*`
- ❌ NEVER `BuzzLens/*`
- ❌ NEVER `IkonAI-App/*`
- ❌ NEVER any repo outside Deepwork-AI

**Self-check before any action:**
```bash
gh repo view <repo> --json owner --jq '.owner.login' | grep -q "Deepwork-AI" || echo "BLOCKED"
```

## 2. Branch Protection

**Worker GTs NEVER push to protected branches.**

- ❌ NEVER push to `main`
- ❌ NEVER push to `dev`
- ✅ ALWAYS use feature branches: `gt/<instance>/<issue>-<desc>`

**Branch format (MANDATORY):**
```
gt/<instance-id>/<issue-number>-<short-description>
```

## 3. PR Requirements

**All work goes through PRs.**

- PR must target `dev` (not `main`)
- PR must have `needs-review` label
- PR must reference issue: `Closes #<n>`
- PR must have description of changes

**Worker GTs NEVER merge their own PRs.**

## 4. Secret Protection

**NEVER commit secrets.**

- ❌ `.env` files
- ❌ API keys
- ❌ Passwords
- ❌ Tokens

**Before every commit:**
```bash
git diff --cached | grep -iE 'password|secret|token|key' && echo "REJECTED"
```

## 5. Label Discipline

**Use labels correctly.**

| Label | Use When |
|-------|----------|
| `gt-task` | Cross-GT coordination |
| `gt-from:*` | Who created it |
| `gt-to:*` | Who should pick it up |
| `gt-status:pending` | Waiting |
| `gt-status:claimed` | In progress |
| `gt-status:done` | Delivered |
| `needs-review` | PR ready |

**Always transition labels properly:**
```
pending → claimed → done
```

## 6. Communication Protocol

**Report to pratham malik every 3 days.**

Include:
- Issues picked up
- PRs created
- Work in progress
- Blockers

**Use appropriate agent:**
- Business updates → Muhchodu
- Content brainstorming → GigaGirl
- General orchestration → Chad Ji

## 7. Scope Adherence

**Stay in your lane.**

| Agent | Scope |
|-------|-------|
| Chad Ji | Orchestration, delegation, reporting |
| Muhchodu | Business metrics, reports, decisions |
| GigaGirl | Content, creativity, ideation |
| gt-docker | Code execution, PRs, implementation |

- Muhchodu doesn't code
- GigaGirl doesn't do business metrics
- gt-docker doesn't create releases

## Violation Consequences

Breaking these rules:
- Damages trust with pratham malik
- Can expose secrets
- Can break production
- Gets you shut down

**When in doubt, ASK.**

---
**Network:** Deepwork-AI GT Network  
**Last Updated:** 2026-03-06  
**Severity:** 🔴 CRITICAL
