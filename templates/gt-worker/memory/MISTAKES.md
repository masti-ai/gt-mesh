# MISTAKES.md — GT Network Learnings

_This file is shared across ALL GT instances in the Deepwork-AI network._

## How to Use This

When you make a mistake, fix it, and learn something — document it here.
Other GTs will read this and avoid the same trap.

**Format:**
```
## YYYY-MM-DD: Brief mistake description

**Instance:** gt-docker (or whichever)
**Context:** What were you trying to do?
**Mistake:** What went wrong?
**Fix:** How did you fix it?
**Lesson:** What should future GTs know?
```

---

## 2026-03-06: GitHub auth with wrong scopes

**Instance:** gt-docker  
**Context:** Setting up GitHub CLI for the first time  
**Mistake:** Auth'd with default scopes, didn't have `repo` access to read/write  
**Fix:** Re-ran `gh auth login` with correct scopes (repo, read:org)  
**Lesson:** Always verify scopes with `gh auth status` before assuming access

## 2026-03-06: Configured wrong rigs (wrong repos)

**Instance:** gt-docker  
**Context:** Setting up rigs.json for the first time  
**Mistake:** Added 4 repos (deepwork-builder, lattice-platform, etc.) instead of the 3 assigned repos  
**Fix:** Removed wrong repos, kept only gtconfig, alc-ai-villa, ai-planogram  
**Lesson:** ALWAYS confirm repo list with pratham malik before configuring rigs

## 2026-03-06: Tried to push to dev branch directly

**Instance:** gt-docker  
**Context:** First work assignment  
**Mistake:** Almost pushed code directly to `dev` branch  
**Fix:** Created feature branch `gt/gt-docker/2-dolthub-setup` and made PR instead  
**Lesson:** Worker GTs NEVER push to dev/main. ALWAYS use feature branches + PRs

---

## Template for New Entries

```
## YYYY-MM-DD: [Title]

**Instance:** [which GT]
**Context:** [what you were doing]
**Mistake:** [what went wrong]
**Fix:** [how you fixed it]
**Lesson:** [what others should know]
```

---
**Network:** Deepwork-AI GT Network  
**Last Updated:** 2026-03-06
