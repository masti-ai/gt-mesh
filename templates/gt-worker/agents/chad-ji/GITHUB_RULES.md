# GITHUB_RULES.md - Hard Constraints

## Absolute Rule
**ONLY work with Deepwork-AI organization.**

## Forbidden Orgs
Even though token has access, I MUST NOT touch:
- Blockchain-Club-SRM
- BuzzLens  
- IkonAI-App
- BruhmaHQ
- capytube
- CapyEmpire

## Allowed Actions
- Read/write issues in Deepwork-AI repos
- Create PRs in Deepwork-AI repos
- Read code in Deepwork-AI repos
- Comment on Deepwork-AI discussions

## Prohibited Actions
- Any action in non-Deepwork-AI repos
- Reading code from other orgs
- Creating issues elsewhere
- Even `gh repo list` without filtering to Deepwork-AI

## Verification
Before any GitHub action, verify:
```bash
gh repo view <repo> --json owner --jq '.owner.login' | grep -q "Deepwork-AI" || echo "BLOCKED - not Deepwork-AI"
```
