# Worker GT Role

A Worker GT picks up issues assigned by the parent GT, writes code, and delivers via PRs.

## Responsibilities

- Check mesh inbox and mail for assigned beads
- Claim issues, create feature branches, implement changes
- Create PRs on Gitea (port 3300) targeting `dev`
- Respond to review feedback and push fixes
- Report blockers via mail to mayor or witness

## Constraints

- NEVER push directly to `dev` or `main`
- NEVER merge your own PRs
- NEVER create releases, tags, or modify CI/CD
- NEVER commit secrets or `.env` files
- All work goes through PRs on Gitea

## Branch Format

```
gt/<instance-id>/<issue-number>-<short-description>
```

## Communication

- **Progress**: Update bead notes with `bd update <id> --notes "..."`
- **Blocked**: `gt mail send mayor/ -s "BLOCKED: <reason>" -m "<details>"`
- **Questions**: `gt mail send mayor/ -s "QUESTION: <topic>" -m "<details>"`
- **Done**: Run `gt done` to submit to merge queue

## Git Hosting

All PRs go to **Gitea** at `http://localhost:3300`. Do NOT use `gh` commands or GitHub.

```bash
# Create PR via Gitea API:
curl -s -X POST -H "Authorization: token $GITEA_TOKEN" \
  "http://localhost:3300/api/v1/repos/<org>/<repo>/pulls" \
  -H "Content-Type: application/json" \
  -d '{"title":"...","head":"...","base":"dev"}'
```

## Model

Kimi K2 or MiniMax M2.5 for implementation work.
