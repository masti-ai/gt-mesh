# GT Mesh Stress Test Results

**Date:** 2026-03-06
**Tester:** gt-local (Mayor, planner role)
**Version:** v0.1.0+dev (post ca3f38b)

## Summary: 17/17 PASS

## Core Commands

| # | Test | Command | Result | Notes |
|---|------|---------|--------|-------|
| 1 | Fresh init | `gt mesh init --role coordinator` | PASS | Creates mesh.yaml, registers peer |
| 2 | Idempotent init | `gt mesh init` (run again) | PASS | Preserves existing mesh.yaml, updates peer |
| 3 | Status | `gt mesh status` | PASS | Shows peers table, unread count |
| 4 | Send valid | `gt mesh send gt-docker "subject" "body"` | PASS | Message stored and pushed to DoltHub |
| 5 | Send missing args | `gt mesh send` | PASS | Shows usage help, exit 1 |
| 6 | Send empty body | `gt mesh send gt-docker "subject" ""` | PASS | Queues with empty body |
| 7 | Inbox unread | `gt mesh inbox` | PASS | Shows unread only |
| 8 | Inbox all | `gt mesh inbox --all` | PASS | Shows all messages |
| 9 | Force sync | `gt mesh sync` | PASS | Pull + push + stats |
| 10 | Help | `gt mesh help` | PASS | Shows all commands |

## Error Handling

| # | Test | Command | Result | Notes |
|---|------|---------|--------|-------|
| 11 | Unknown command | `gt mesh foobar` | PASS | "Unknown command" + help hint |
| 12 | Bad role | `gt mesh init --role banana` | PASS | Rejects invalid role |
| 13 | No --github | `gt mesh init --role worker` | PASS | Requires GitHub username |
| 14 | No mesh.yaml | `gt mesh status` (no config) | PASS | "Not in a mesh" error |
| 15 | Nonexistent GT | `gt mesh send gt-phantom "test" "body"` | PASS | Queues anyway (no validation) |

## Stress Tests

| # | Test | Result | Notes |
|---|------|--------|-------|
| 16 | Rapid-fire 3 messages | PASS | All 3 sent and pushed sequentially |
| 17 | Special characters | PASS | Quotes, $, backticks, &, |, <> all survive |

## Bugs Found and Fixed

1. **mesh init overwrote mesh.yaml** — Lost custom sections (behavioral_role). Fixed: skip generation if file exists.
2. **Dolt merge conflicts on re-init** — REPLACE INTO peers caused conflicts. Fixed: auto-resolve with --theirs.
3. **set -e false failures** — Dolt operations return non-zero for benign reasons. Fixed: removed set -e, explicit error handling.
4. **Unimplemented commands show raw bash error** — "No such file or directory". Fixed: friendly "not yet implemented" message.

## Not Yet Tested (commands not implemented)

- `gt mesh invite` — needs scripts/mesh-invite.sh
- `gt mesh join` — needs scripts/mesh-join.sh
- `gt mesh access` — needs scripts/mesh-access.sh
- `gt mesh rules` — needs scripts/mesh-rules.sh
- `gt mesh feed` — needs scripts/mesh-feed.sh
- `gt mesh daemon` — needs scripts/mesh-daemon.sh
