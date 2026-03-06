#!/bin/bash
# GT Mesh — Main dispatcher
# Routes `gt mesh <subcommand>` to the correct script
#
# Usage: mesh.sh <subcommand> [args...]

set -e

MESH_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS_DIR="$MESH_DIR/scripts"
GT_ROOT="${GT_ROOT:-$(cd "$MESH_DIR/.." && pwd)}"
MESH_YAML="$GT_ROOT/mesh.yaml"

export GT_ROOT MESH_DIR MESH_YAML

cmd="${1:-help}"
shift 2>/dev/null || true

_run() {
  local script="$1"; shift
  if [ -f "$script" ]; then
    bash "$script" "$@"
  else
    local name=$(basename "$script" .sh | sed 's/mesh-//')
    echo "[error] '$name' is not yet implemented."
    echo "        Track progress: https://github.com/Deepwork-AI/gt-mesh/issues"
    exit 1
  fi
}

case "$cmd" in
  init)
    _run "$SCRIPTS_DIR/mesh-init.sh" "$@"
    ;;
  status)
    _run "$SCRIPTS_DIR/mesh-status.sh" "$@"
    ;;
  send)
    _run "$SCRIPTS_DIR/mesh-send.sh" "$@"
    ;;
  inbox)
    _run "$SCRIPTS_DIR/mesh-inbox.sh" "$@"
    ;;
  invite)
    _run "$SCRIPTS_DIR/mesh-invite.sh" "$@"
    ;;
  join)
    _run "$SCRIPTS_DIR/mesh-join.sh" "$@"
    ;;
  peers)
    _run "$SCRIPTS_DIR/mesh-status.sh" --peers "$@"
    ;;
  feed)
    _run "$SCRIPTS_DIR/mesh-feed.sh" "$@"
    ;;
  sync)
    _run "$SCRIPTS_DIR/mesh-sync.sh" "$@"
    ;;
  daemon)
    _run "$SCRIPTS_DIR/mesh-daemon.sh" "$@"
    ;;
  access)
    _run "$SCRIPTS_DIR/mesh-access.sh" "$@"
    ;;
  rules)
    _run "$SCRIPTS_DIR/mesh-rules.sh" "$@"
    ;;
  dash|dashboard)
    _run "$SCRIPTS_DIR/mesh-dash.sh" "$@"
    ;;
  beads)
    _run "$SCRIPTS_DIR/mesh-beads.sh" "$@"
    ;;
  skills)
    _run "$SCRIPTS_DIR/mesh-skills.sh" "$@"
    ;;
  config)
    _run "$SCRIPTS_DIR/mesh-config.sh" "$@"
    ;;
  auto-sync)
    _run "$SCRIPTS_DIR/mesh-auto-sync.sh" "$@"
    ;;
  packs)
    _run "$SCRIPTS_DIR/mesh-packs.sh" "$@"
    ;;
  help|--help|-h)
    echo "GT Mesh — Collaborative coding for Gas Town"
    echo ""
    echo "Usage: gt mesh <command> [options]"
    echo ""
    echo "Commands:"
    echo "  init          Initialize this GT as a mesh node"
    echo "  status        Show mesh status and dashboard"
    echo "  send          Send a message to another GT"
    echo "  inbox         Check incoming mesh messages"
    echo "  invite        Generate an invite code"
    echo "  join          Join a mesh with an invite code"
    echo "  peers         List connected peers"
    echo "  feed          View mesh activity feed"
    echo "  sync          Force sync with DoltHub"
    echo "  daemon        Start/stop/status of mesh daemon"
    echo "  access        Manage access control"
    echo "  rules         View/set mesh rules"
    echo "  dash          Full-screen dashboard (--refresh N for live)"
    echo "  beads         Shared beads — list, share, claim, unclaim"
    echo "  skills        Shared skills — list, publish, install"
    echo "  config        Mesh config — publish, pull, diff, status"
    echo "  packs         Pack registry — list, install, publish, create"
    echo "  auto-sync     Broadcast work context — log, digest, broadcast"
    echo "  help          Show this help"
    echo ""
    echo "Config: $MESH_YAML"
    echo "Plugin: $MESH_DIR"
    ;;
  *)
    echo "Unknown command: $cmd"
    echo "Run 'gt mesh help' for usage."
    exit 1
    ;;
esac
