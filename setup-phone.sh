#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# Load .env if present in the same directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/.env" ]; then
    echo "==> Loading configuration from $SCRIPT_DIR/.env..."
    set -a
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/.env"
    set +a
elif [ -f "$SCRIPT_DIR/.env.example" ]; then
    echo "==> Loading default configuration from $SCRIPT_DIR/.env.example..."
    set -a
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/.env.example"
    set +a
fi

# Allow CLI flag to override IMMICH_VERSION, otherwise use .env or default
IMMICH_VERSION="${1:-${IMMICH_VERSION:-v3.4.1}}"
ML_HOST="${ML_HOST:-0.0.0.0}"
ML_PORT="${ML_PORT:-3003}"
MACHINE_LEARNING_CACHE_FOLDER="${MACHINE_LEARNING_CACHE_FOLDER:-/root/ml-cache}"
MACHINE_LEARNING_WORKERS="${MACHINE_LEARNING_WORKERS:-1}"
MACHINE_LEARNING_MODEL_TTL="${MACHINE_LEARNING_MODEL_TTL:-0}"
MACHINE_LEARNING_REQUEST_THREADS="${MACHINE_LEARNING_REQUEST_THREADS:-0}"
MACHINE_LEARNING_MODEL_INTER_OP_THREADS="${MACHINE_LEARNING_MODEL_INTER_OP_THREADS:-0}"
MACHINE_LEARNING_MODEL_INTRA_OP_THREADS="${MACHINE_LEARNING_MODEL_INTRA_OP_THREADS:-0}"
TMUX_SESSION="${TMUX_SESSION:-immich-ml}"

echo "==> [1/5] Updating Termux and installing host utilities..."
pkg update -y && pkg upgrade -y
pkg install -y proot-distro openssh tmux ncurses-utils curl
termux-wake-lock

echo "==> [2/5] Installing Debian proot environment..."
if [ ! -d "$PREFIX/var/lib/proot-distro/installed-rootfs/debian" ]; then
    proot-distro install debian
else
    echo "Debian proot is already installed."
fi

echo "==> [3/5] Provisioning Debian dependencies and uv..."
proot-distro login debian -- bash -c "
set -euo pipefail
apt update && apt upgrade -y
apt install -y git curl build-essential python3 python3-venv python3-dev libgl1 libglib2.0-0

if [ ! -f /root/.local/bin/uv ]; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi
export PATH="/root/.local/bin:\$PATH"
export UV_LINK_MODE=copy

if ! grep -q 'UV_LINK_MODE=copy' /root/.bashrc; then
    echo 'export UV_LINK_MODE=copy' >> /root/.bashrc
    echo 'export PATH="/root/.local/bin:\$PATH"' >> /root/.bashrc
fi

echo '==> [4/5] Cloning Immich ($IMMICH_VERSION) and syncing CPU wheels...'
cd /root
if [ ! -d /root/immich ]; then
    git clone --depth 1 --branch "$IMMICH_VERSION" https://github.com/immich-app/immich.git
else
    cd /root/immich
    git fetch --depth 1 origin tag "$IMMICH_VERSION"
    git checkout "$IMMICH_VERSION"
fi

cd /root/immich/machine-learning
rm -rf .venv
uv sync --extra cpu --no-dev
uv cache clean

echo '==> [5/5] Writing /root/immich-ml.env and /root/start-ml.sh...'
mkdir -p "$MACHINE_LEARNING_CACHE_FOLDER"

cat << 'ENVEOF' > /root/immich-ml.env
ML_HOST="$ML_HOST"
ML_PORT=$ML_PORT
MACHINE_LEARNING_CACHE_FOLDER="$MACHINE_LEARNING_CACHE_FOLDER"
MACHINE_LEARNING_WORKERS=$MACHINE_LEARNING_WORKERS
MACHINE_LEARNING_MODEL_TTL=$MACHINE_LEARNING_MODEL_TTL
MACHINE_LEARNING_REQUEST_THREADS=$MACHINE_LEARNING_REQUEST_THREADS
MACHINE_LEARNING_MODEL_INTER_OP_THREADS=$MACHINE_LEARNING_MODEL_INTER_OP_THREADS
MACHINE_LEARNING_MODEL_INTRA_OP_THREADS=$MACHINE_LEARNING_MODEL_INTRA_OP_THREADS
ENVEOF

cat << 'STARTEOF' > /root/start-ml.sh
#!/bin/bash
set -euo pipefail
export PATH="/root/.local/bin:\$PATH"
export UV_LINK_MODE=copy

if [ -f /root/immich-ml.env ]; then
    set -a
    source /root/immich-ml.env
    set +a
fi

ML_HOST="\${ML_HOST:-0.0.0.0}"
ML_PORT="\${ML_PORT:-3003}"
export MACHINE_LEARNING_CACHE_FOLDER="\${MACHINE_LEARNING_CACHE_FOLDER:-/root/ml-cache}"
export MACHINE_LEARNING_WORKERS="\${MACHINE_LEARNING_WORKERS:-1}"
export MACHINE_LEARNING_MODEL_TTL="\${MACHINE_LEARNING_MODEL_TTL:-0}"

[ "\${MACHINE_LEARNING_REQUEST_THREADS:-0}" -gt 0 ] && export MACHINE_LEARNING_REQUEST_THREADS
[ "\${MACHINE_LEARNING_MODEL_INTER_OP_THREADS:-0}" -gt 0 ] && export MACHINE_LEARNING_MODEL_INTER_OP_THREADS
[ "\${MACHINE_LEARNING_MODEL_INTRA_OP_THREADS:-0}" -gt 0 ] && export MACHINE_LEARNING_MODEL_INTRA_OP_THREADS

cd /root/immich/machine-learning

if [ "\$MACHINE_LEARNING_MODEL_TTL" -eq 0 ]; then
    exec uv run --no-dev uvicorn immich_ml.main:app --host "\$ML_HOST" --port "\$ML_PORT" --workers "\$MACHINE_LEARNING_WORKERS"
else
    while true; do
        uv run --no-dev uvicorn immich_ml.main:app --host "\$ML_HOST" --port "\$ML_PORT" --workers "\$MACHINE_LEARNING_WORKERS"
        echo "Idle timeout (\$MACHINE_LEARNING_MODEL_TTL s) reached; respawning clean worker in 2s..."
        sleep 2
    done
fi
STARTEOF
chmod +x /root/start-ml.sh
"

echo ""
echo "=========================================================="
echo " Setup Complete on port ${ML_PORT}!"
echo " Start sshd and launch immich-ml in a detached session:"
echo "   sshd"
echo "   TERM=xterm-256color tmux new-session -d -s ${TMUX_SESSION} 'proot-distro login debian -- /root/start-ml.sh'"
echo "=========================================================="
