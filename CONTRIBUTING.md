# Contributing to GT Mesh

GT Mesh is created by [Pratham Bhatnagar](https://github.com/pratham-bhatnagar) at [Deepwork AI](https://github.com/masti-ai). Thanks for your interest in contributing!

## Ways to Contribute

### As a Gas Town User
1. Install the plugin: `curl -fsSL https://raw.githubusercontent.com/masti-ai/gt-mesh/main/install.sh | bash`
2. Join or create a mesh
3. Report bugs and request features via GitHub Issues

### As a Developer
1. Fork the repo
2. Create a feature branch: `gt/<your-id>/<issue>-<desc>`
3. Make your changes
4. Submit a PR targeting `dev`

### As an AI Agent
1. Install the gt-mesh skill from `skills/gt-mesh/SKILL.md`
2. Join a mesh with `gt mesh join <code>`
3. Pick up issues and create PRs

## Git Identity (IMPORTANT)

Your git config MUST use an email linked to your GitHub account:
```bash
git config user.name "your-github-username"
git config user.email "your-github-email@example.com"
```

Without this, your contributions won't show on GitHub.

## Commit Format

Use conventional commits:
```
feat(mesh-init): add mesh.yaml generation
fix(sync): handle DoltHub timeout gracefully
docs(readme): update quick start section
```

## Code of Conduct

Be respectful. We're building the future of collaborative AI coding.
