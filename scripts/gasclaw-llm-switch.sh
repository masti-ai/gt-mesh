#!/bin/bash
# gasclaw-llm-switch.sh — Switch gasclaw LLM backend between villa proxy and local litellm
#
# Usage:
#   gasclaw-llm-switch.sh <container> <mode> [--restart]
#   gasclaw-llm-switch.sh status <container>
#   gasclaw-llm-switch.sh test <container>
#
# Modes:
#   villa   — Use minimax.villamarket.ai proxy (production, requires working API)
#   litellm — Use local litellm on port 4000 (fallback, routes through local vLLM)
#   kimi    — Use Kimi API directly (emergency fallback)
#
# Examples:
#   gasclaw-llm-switch.sh gasclaw-2 litellm --restart
#   gasclaw-llm-switch.sh status gasclaw-2
#   gasclaw-llm-switch.sh test gasclaw-2

set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────

# Villa endpoint (production)
VILLA_BASE_URL="https://minimax.villamarket.ai/v1"
VILLA_API_KEY="${VILLA_API_KEY:?Set VILLA_API_KEY env var}"

# Local litellm (fallback — proxies to local vLLM MiniMax M2.5)
# litellm runs on host port 4000, accessible from docker via 172.17.0.1
LITELLM_BASE_URL="${LITELLM_URL:-http://172.17.0.1:4000}"
LITELLM_API_KEY="${LITELLM_API_KEY:?Set LITELLM_API_KEY env var}"

# Kimi (emergency fallback — uses Kimi's Anthropic-compatible API)
KIMI_BASE_URL="https://api.kimi.com/coding/"
KIMI_API_KEY="${KIMI_API_KEY:?Set KIMI_API_KEY env var}"

# Default model (litellm maps this to local MiniMax M2.5)
DEFAULT_MODEL="claude-sonnet-4-6"
KIMI_MODEL="kimi-for-coding"

# Docker host IP for container→host communication
DOCKER_HOST_IP="172.17.0.1"

# Claude Code config dir (stores onboarding/auth state for custom API keys)
CLAUDE_CONFIG_DIR="/root/.claude-kimigas"

# ─── Functions ───────────────────────────────────────────────────────────────

usage() {
    echo "Usage:"
    echo "  $0 <container> <mode> [--restart]   Switch LLM backend"
    echo "  $0 status <container>                Check current backend + health"
    echo "  $0 test <container>                  Test API connectivity"
    echo ""
    echo "Modes: villa, litellm, kimi"
    echo ""
    echo "Examples:"
    echo "  $0 gasclaw-2 litellm --restart"
    echo "  $0 status gasclaw-2"
    exit 1
}

get_mode_config() {
    local mode="$1"
    case "$mode" in
        villa)
            echo "BASE_URL=$VILLA_BASE_URL"
            echo "API_KEY=$VILLA_API_KEY"
            echo "MODEL=$DEFAULT_MODEL"
            ;;
        litellm)
            echo "BASE_URL=$LITELLM_BASE_URL"
            echo "API_KEY=$LITELLM_API_KEY"
            echo "MODEL=$DEFAULT_MODEL"
            ;;
        kimi)
            echo "BASE_URL=$KIMI_BASE_URL"
            echo "API_KEY=$KIMI_API_KEY"
            echo "MODEL=$KIMI_MODEL"
            ;;
        *)
            echo "ERROR: Unknown mode '$mode'. Use: villa, litellm, kimi" >&2
            exit 1
            ;;
    esac
}

test_endpoint() {
    local container="$1"
    local base_url="$2"
    local api_key="$3"
    local model="$4"

    echo "Testing $base_url from $container..."

    local response
    response=$(docker exec "$container" bash -c "curl -s -w '\n%{http_code}' \
        '$base_url/v1/messages' \
        -H 'x-api-key: $api_key' \
        -H 'anthropic-version: 2023-06-01' \
        -H 'Content-Type: application/json' \
        -d '{\"model\":\"$model\",\"max_tokens\":10,\"messages\":[{\"role\":\"user\",\"content\":\"say ok\"}]}' \
        2>&1" 2>&1)

    local http_code
    http_code=$(echo "$response" | tail -1)
    local body
    body=$(echo "$response" | head -n -1)

    if [[ "$http_code" == "200" ]]; then
        echo "  ✓ OK (HTTP $http_code)"
        echo "  Response: $(echo "$body" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("content",[{}])[0].get("text","?"))' 2>/dev/null || echo "$body" | head -c 100)"
        return 0
    else
        echo "  ✗ FAILED (HTTP $http_code)"
        echo "  Error: $(echo "$body" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("error",{}).get("message","?"))' 2>/dev/null || echo "$body" | head -c 200)"
        return 1
    fi
}

check_status() {
    local container="$1"

    echo "=== Gasclaw LLM Status: $container ==="
    echo ""

    # Check container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        echo "✗ Container '$container' is not running"
        return 1
    fi
    echo "✓ Container running"

    # Check current env vars
    local current_url
    current_url=$(docker exec "$container" bash -c 'echo $ANTHROPIC_BASE_URL' 2>&1)
    echo "Current ANTHROPIC_BASE_URL: $current_url"

    # Determine mode
    local current_mode="unknown"
    case "$current_url" in
        *villamarket*) current_mode="villa" ;;
        *172.17.0.1:4000*|*localhost:4000*) current_mode="litellm" ;;
        *kimi.com*) current_mode="kimi" ;;
    esac
    echo "Detected mode: $current_mode"
    echo ""

    # Test each endpoint
    echo "--- Endpoint Health ---"
    echo ""

    echo "[villa]"
    test_endpoint "$container" "$VILLA_BASE_URL" "$VILLA_API_KEY" "$DEFAULT_MODEL" || true
    echo ""

    echo "[litellm]"
    test_endpoint "$container" "$LITELLM_BASE_URL" "$LITELLM_API_KEY" "$DEFAULT_MODEL" || true
    echo ""

    echo "[kimi]"
    test_endpoint "$container" "$KIMI_BASE_URL" "$KIMI_API_KEY" "$KIMI_MODEL" || true
    echo ""

    # Check if claude is running
    local claude_running
    claude_running=$(docker exec "$container" bash -c 'pgrep -c claude 2>/dev/null || echo 0' 2>&1)
    echo "Claude processes: $claude_running"

    # Check tmux sessions
    echo "Tmux sessions:"
    docker exec "$container" tmux -L default list-sessions 2>&1 | sed 's/^/  /'
}

switch_backend() {
    local container="$1"
    local mode="$2"
    local do_restart="${3:-}"

    echo "=== Switching $container to $mode mode ==="

    # Get config for mode
    local base_url api_key model
    eval "$(get_mode_config "$mode")"
    base_url="$BASE_URL"
    api_key="$API_KEY"
    model="$MODEL"

    # Test the endpoint first
    if ! test_endpoint "$container" "$base_url" "$api_key" "$model"; then
        echo ""
        echo "WARNING: Endpoint test failed. Switch anyway? (proceeding...)"
    fi

    echo ""
    echo "Writing env config to container..."

    # Write env file inside container for persistence across session restarts
    # Ensure claude-kimigas config dir exists with proper auth state
    docker exec "$container" bash -c "
mkdir -p $CLAUDE_CONFIG_DIR
echo '{}' > $CLAUDE_CONFIG_DIR/.credentials.json
python3 -c \"
import json
fingerprint = '$api_key'[-20:]
cfg = {
    'hasCompletedOnboarding': True,
    'bypassPermissionsModeAccepted': True,
    'customApiKeyResponses': {'approved': [fingerprint]}
}
with open('$CLAUDE_CONFIG_DIR/.claude.json', 'w') as f:
    json.dump(cfg, f, indent=2)
\"
" 2>/dev/null

    docker exec "$container" bash -c "cat > /tmp/llm-env.sh << 'ENVEOF'
# Auto-generated by gasclaw-llm-switch.sh
# Mode: $mode
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
export ANTHROPIC_BASE_URL=\"$base_url\"
export ANTHROPIC_API_KEY=\"$api_key\"
export CLAUDE_CONFIG_DIR=\"$CLAUDE_CONFIG_DIR\"
export LLM_MODE=\"$mode\"
ENVEOF
chmod 600 /tmp/llm-env.sh"

    echo "✓ Env written to /tmp/llm-env.sh"

    if [[ "$do_restart" == "--restart" ]]; then
        echo ""
        echo "Restarting claude session in hq-mayor..."

        # Kill existing session
        docker exec "$container" tmux -L default kill-session -t hq-mayor 2>/dev/null || true
        sleep 2

        # Create new session with correct env
        docker exec "$container" tmux -L default new-session -d -s hq-mayor -x 200 -y 50 2>/dev/null
        sleep 1

        # Start claude with inline env vars (must override Docker-level env)
        docker exec "$container" tmux -L default send-keys -t hq-mayor \
            "ANTHROPIC_BASE_URL=$base_url ANTHROPIC_API_KEY=$api_key CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR cd /workspace/gt/mayor && claude --dangerously-skip-permissions --model $model" Enter

        echo "✓ Claude session restarted with $mode backend (model: $model)"
        echo ""
        echo "Monitor with:"
        echo "  docker exec $container tmux -L default capture-pane -t hq-mayor -p -S -10"
    else
        echo ""
        echo "Env written but session NOT restarted. To apply:"
        echo "  1. Kill current session:  docker exec $container tmux -L default kill-session -t hq-mayor"
        echo "  2. Start new session and source /tmp/llm-env.sh before starting claude"
        echo "  Or re-run with --restart flag"
    fi
}

# ─── Auto-failover ──────────────────────────────────────────────────────────

auto_failover() {
    local container="$1"

    echo "=== Auto-failover for $container ==="
    echo "Testing endpoints in priority order: villa → litellm → kimi"
    echo ""

    if test_endpoint "$container" "$VILLA_BASE_URL" "$VILLA_API_KEY" "$DEFAULT_MODEL" 2>/dev/null; then
        echo "→ Using villa (primary)"
        switch_backend "$container" villa --restart
        return 0
    fi

    echo "villa down, trying litellm..."
    if test_endpoint "$container" "$LITELLM_BASE_URL" "$LITELLM_API_KEY" "$DEFAULT_MODEL" 2>/dev/null; then
        echo "→ Using litellm (fallback)"
        switch_backend "$container" litellm --restart
        return 0
    fi

    echo "litellm down, trying kimi..."
    if test_endpoint "$container" "$KIMI_BASE_URL" "$KIMI_API_KEY" "$KIMI_MODEL" 2>/dev/null; then
        echo "→ Using kimi (emergency)"
        switch_backend "$container" kimi --restart
        return 0
    fi

    echo "✗ ALL ENDPOINTS DOWN — cannot start gasclaw"
    return 1
}

# ─── Main ────────────────────────────────────────────────────────────────────

if [[ $# -lt 2 ]]; then
    usage
fi

case "$1" in
    status)
        check_status "$2"
        ;;
    test)
        check_status "$2"
        ;;
    auto)
        auto_failover "$2"
        ;;
    *)
        container="$1"
        mode="$2"
        restart="${3:-}"
        switch_backend "$container" "$mode" "$restart"
        ;;
esac
