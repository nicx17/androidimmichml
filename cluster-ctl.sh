#!/usr/bin/env bash
set -euo pipefail

# Locate and load .env configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"

if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
elif [ -f "$SCRIPT_DIR/.env.example" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/.env.example"
    set +a
else
    echo "Error: Neither .env nor .env.example found in $SCRIPT_DIR" >&2
    exit 1
fi

# Parse space-separated NODES string into an array
read -r -a NODE_LIST <<< "${NODES:-192.168.0.210 192.168.0.211}"
SSH_PORT="${SSH_PORT:-8022}"
ML_HOST="${ML_HOST:-0.0.0.0}"
ML_PORT="${ML_PORT:-3003}"
TMUX_SESSION="${TMUX_SESSION:-immich-ml}"
MACHINE_LEARNING_CACHE_FOLDER="${MACHINE_LEARNING_CACHE_FOLDER:-/root/ml-cache}"
MACHINE_LEARNING_WORKERS="${MACHINE_LEARNING_WORKERS:-1}"
MACHINE_LEARNING_MODEL_TTL="${MACHINE_LEARNING_MODEL_TTL:-0}"
MACHINE_LEARNING_REQUEST_THREADS="${MACHINE_LEARNING_REQUEST_THREADS:-0}"
MACHINE_LEARNING_MODEL_INTER_OP_THREADS="${MACHINE_LEARNING_MODEL_INTER_OP_THREADS:-0}"
MACHINE_LEARNING_MODEL_INTRA_OP_THREADS="${MACHINE_LEARNING_MODEL_INTRA_OP_THREADS:-0}"

usage() {
    cat << EOF
Usage: $0 {start|stop|restart|status|sync-env|logs [node]}

Commands:
  start          Acquire wake-lock and start detached tmux ML session on all NODES
  stop           Kill tmux ML session and release wake-lock on all NODES
  restart        Push latest .env settings and restart ML service on all NODES
  status         Check HTTP /ping health on ML_PORT ($ML_PORT) across all NODES
  sync-env       Push local .env settings to /root/immich-ml.env on all NODES
  logs [node]    Attach to live tmux console on [node] (defaults to ${NODE_LIST[0]:-node})
EOF
    exit "${1:-1}"
}

sync_node_env() {
    local host="$1"
    echo "==> Syncing .env parameters to $host:/root/immich-ml.env..."
    # Client-side expansion is intentional: workstation variables are populated into the remote environment file.
    # shellcheck disable=SC2087
    cat << EOF | ssh -p "$SSH_PORT" -o ConnectTimeout=5 "$host" "proot-distro login debian -- bash -c 'cat > /root/immich-ml.env'"
ML_HOST="$ML_HOST"
ML_PORT=$ML_PORT
MACHINE_LEARNING_CACHE_FOLDER="$MACHINE_LEARNING_CACHE_FOLDER"
MACHINE_LEARNING_WORKERS=$MACHINE_LEARNING_WORKERS
MACHINE_LEARNING_MODEL_TTL=$MACHINE_LEARNING_MODEL_TTL
MACHINE_LEARNING_REQUEST_THREADS=$MACHINE_LEARNING_REQUEST_THREADS
MACHINE_LEARNING_MODEL_INTER_OP_THREADS=$MACHINE_LEARNING_MODEL_INTER_OP_THREADS
MACHINE_LEARNING_MODEL_INTRA_OP_THREADS=$MACHINE_LEARNING_MODEL_INTRA_OP_THREADS
EOF
}

[ $# -lt 1 ] && usage 1

case "$1" in
    -h|--help|help)
        usage 0
        ;;
    start)
        for host in "${NODE_LIST[@]}"; do
            echo "==> Starting $TMUX_SESSION on $host (SSH :$SSH_PORT -> ML :$ML_PORT)..."
            ssh -p "$SSH_PORT" -o ConnectTimeout=5 "$host" \
                "termux-wake-lock && (tmux has-session -t '$TMUX_SESSION' 2>/dev/null || TERM=xterm-256color tmux new-session -d -s '$TMUX_SESSION' 'proot-distro login debian -- /root/start-ml.sh')" || echo "Error: Failed to reach $host" >&2
        done
        ;;
    stop)
        for host in "${NODE_LIST[@]}"; do
            echo "==> Stopping $TMUX_SESSION on $host..."
            ssh -p "$SSH_PORT" -o ConnectTimeout=5 "$host" \
                "tmux kill-session -t '$TMUX_SESSION' 2>/dev/null || true; termux-wake-unlock" || echo "Error: Failed to reach $host" >&2
        done
        ;;
    sync-env)
        for host in "${NODE_LIST[@]}"; do
            sync_node_env "$host" || echo "Error: Failed to sync env to $host" >&2
        done
        ;;
    restart)
        for host in "${NODE_LIST[@]}"; do
            sync_node_env "$host" || echo "Error: Failed to sync env to $host" >&2
            echo "==> Restarting $TMUX_SESSION on $host..."
            ssh -p "$SSH_PORT" -o ConnectTimeout=5 "$host" \
                "termux-wake-lock && tmux kill-session -t '$TMUX_SESSION' 2>/dev/null || true; sleep 1; TERM=xterm-256color tmux new-session -d -s '$TMUX_SESSION' 'proot-distro login debian -- /root/start-ml.sh'" || echo "Error: Failed to restart on $host" >&2
        done
        ;;
    status)
        printf "%-30s %-10s %-15s\n" "NODE" "PORT" "STATUS"
        printf "%-30s %-10s %-15s\n" "----" "----" "------"
        for host in "${NODE_LIST[@]}"; do
            target_ip=$(ssh -G "$host" 2>/dev/null | awk '/^hostname / {print $2}' || true)
            [ -z "$target_ip" ] && target_ip="$host"
            if resp=$(curl -fsS --max-time 3 "http://${target_ip}:${ML_PORT}/ping" 2>/dev/null); then
                printf "%-30s %-10s %-15s\n" "$host ($target_ip)" "$ML_PORT" "ONLINE ($resp)"
            else
                printf "%-30s %-10s %-15s\n" "$host ($target_ip)" "$ML_PORT" "OFFLINE"
            fi
        done
        ;;
    logs)
        node="${2:-${NODE_LIST[0]}}"
        echo "==> Attaching to $node [$TMUX_SESSION] (Press CTRL+B then D to detach)..."
        ssh -t -p "$SSH_PORT" -o ConnectTimeout=5 "$node" "TERM=xterm-256color tmux attach -t '$TMUX_SESSION'"
        ;;
    *)
        usage 1
        ;;
esac
