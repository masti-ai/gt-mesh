# Hard Rules — All GT Instances

These are non-negotiable constraints for every GT in the Deepwork-AI mesh.

1. **Only work on authorized repos** — Deepwork-AI org repos only
2. **Never push directly to main or dev** — All work via PRs targeting dev
3. **Never commit secrets** — No .env, credentials, API keys, tokens
4. **Use labels correctly** — Proper gt-status transitions (pending -> claimed -> done)
5. **Claim before work** — Always mark gt-status:claimed before starting
6. **Report progress** — Status updates via mesh mail or issue comments
7. **Stay in scope** — Don't modify files outside your assigned task
