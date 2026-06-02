#!/bin/bash
# Deploy Daizima from local machine to server (no GitHub access needed on server)
#
# Usage:
#   ./deploy/deploy-from-local.sh frontend
#   ./deploy/deploy-from-local.sh backend
#   ./deploy/deploy-from-local.sh all
#   ./deploy/deploy-from-local.sh frontend --skip-pull
#   ./deploy/deploy-from-local.sh frontend --skip-build
#   ./deploy/deploy-from-local.sh backend --skip-pull

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$SCRIPT_DIR/deploy.local.env"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [ ! -f "$CONFIG_FILE" ]; then
  log_error "Missing $CONFIG_FILE"
  echo "Copy deploy/deploy.local.env.example to deploy/deploy.local.env and fill in values."
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${DEPLOY_HOST:?DEPLOY_HOST is required}"
: "${DEPLOY_PORT:?DEPLOY_PORT is required}"
: "${DEPLOY_USER:?DEPLOY_USER is required}"
: "${REMOTE_BACKEND_PATH:=/var/www/daizima-backend}"
: "${REMOTE_FRONTEND_PATH:=/var/www/daizima-frontend}"

TARGET="${1:-all}"
SKIP_PULL=false
SKIP_BUILD=false

for arg in "$@"; do
  case "$arg" in
    --skip-pull) SKIP_PULL=true ;;
    --skip-build) SKIP_BUILD=true ;;
  esac
done

if [ "$1" = "--skip-pull" ] || [ "$1" = "--skip-build" ]; then
  TARGET="${2:-all}"
fi

SSH_BASE=(ssh -p "$DEPLOY_PORT" -o StrictHostKeyChecking=accept-new)
SCP_BASE=(scp -P "$DEPLOY_PORT" -o StrictHostKeyChecking=accept-new)

if [ -n "${DEPLOY_PASSWORD:-}" ] && command -v sshpass >/dev/null 2>&1; then
  SSH_BASE=(sshpass -p "$DEPLOY_PASSWORD" ssh -p "$DEPLOY_PORT" -o StrictHostKeyChecking=accept-new)
  SCP_BASE=(sshpass -p "$DEPLOY_PASSWORD" scp -P "$DEPLOY_PORT" -o StrictHostKeyChecking=accept-new)
elif [ -n "${DEPLOY_PASSWORD:-}" ]; then
  log_warn "sshpass not found. Install it or use SSH keys; you may be prompted for password."
fi

remote() {
  "${SSH_BASE[@]}" "${DEPLOY_USER}@${DEPLOY_HOST}" "$@"
}

upload_file() {
  local source_path="$1"
  local target_path="$2"
  "${SCP_BASE[@]}" "$source_path" "${DEPLOY_USER}@${DEPLOY_HOST}:${target_path}"
}

run_frontend_deploy_on_server() {
  remote "bash -lc 'set -e
    [ -s \"\$HOME/.nvm/nvm.sh\" ] && . \"\$HOME/.nvm/nvm.sh\"
    [ -f \"\$HOME/.bashrc\" ] && . \"\$HOME/.bashrc\"
    [ -f \"\$HOME/.profile\" ] && . \"\$HOME/.profile\"
    export PATH=\"/usr/local/bin:/usr/bin:\$HOME/.local/bin:\$HOME/.nvm/versions/node/\$(ls -1 \"\$HOME/.nvm/versions/node\" 2>/dev/null | tail -1)/bin:\$PATH\"

    if ! command -v pm2 >/dev/null 2>&1; then
      PM2_BIN=\$(find \"\$HOME/.nvm\" /usr/local/lib/node_modules /usr/lib/node_modules -name pm2 -type f 2>/dev/null | head -1)
      if [ -n \"\$PM2_BIN\" ]; then
        export PATH=\"\$(dirname \"\$PM2_BIN\"):\$PATH\"
      fi
    fi

    if ! command -v pm2 >/dev/null 2>&1; then
      echo \"pm2 not found in PATH\"
      exit 1
    fi

    cd \"$REMOTE_FRONTEND_PATH\"
    if [ ! -d \".output/server\" ]; then
      echo \".output/server not found after extract\"
      exit 1
    fi

    pm2 flush daizima-frontend 2>/dev/null || true
    pm2 restart daizima-frontend --update-env || pm2 start .output/server/index.mjs --name daizima-frontend --cwd \"$REMOTE_FRONTEND_PATH\"
    pm2 save
    rm -rf /var/cache/nginx/daizima-frontend/* 2>/dev/null || true
    nginx -t && systemctl reload nginx || true
    pm2 status'"
}

deploy_frontend() {
  log_info "=== Deploying Frontend ==="
  cd "$ROOT_DIR/daizima-frontend"

  if [ "$SKIP_PULL" = false ]; then
    log_info "Pulling latest frontend code..."
    git pull origin main
  fi

  if [ "$SKIP_BUILD" = false ]; then
    log_info "Installing dependencies..."
    pnpm install --frozen-lockfile

    log_info "Building frontend..."
    export NUXT_PUBLIC_API_BASE_URL="${NUXT_PUBLIC_API_BASE_URL:-http://${DEPLOY_HOST}/api}"
    export NUXT_PUBLIC_WEBSOCKET_URL="${NUXT_PUBLIC_WEBSOCKET_URL:-ws://${DEPLOY_HOST}:6001}"
    export NUXT_PUBLIC_APP_NAME="${NUXT_PUBLIC_APP_NAME:-Daizima}"
    export NUXT_PUBLIC_APP_ENV="${NUXT_PUBLIC_APP_ENV:-production}"
    NODE_OPTIONS="--max-old-space-size=4096" pnpm run build
  fi

  if [ ! -d ".output/server" ]; then
    log_error ".output/server not found. Run build first or remove --skip-build."
    exit 1
  fi

  ARCHIVE="/tmp/daizima-frontend-output-$(date +%Y%m%d_%H%M%S).tar.gz"
  REMOTE_ARCHIVE="${REMOTE_FRONTEND_PATH}/frontend-output.tar.gz"

  log_info "Creating single archive from .output..."
  tar -czf "$ARCHIVE" -C "$ROOT_DIR/daizima-frontend" .output

  ARCHIVE_SIZE="$(du -h "$ARCHIVE" | cut -f1)"
  log_info "Archive ready: $ARCHIVE ($ARCHIVE_SIZE)"

  log_info "Uploading single archive to server..."
  remote "mkdir -p '$REMOTE_FRONTEND_PATH'"
  upload_file "$ARCHIVE" "$REMOTE_ARCHIVE"

  log_info "Extracting on server and restarting services..."
  remote "set -e
    cd '$REMOTE_FRONTEND_PATH'
    rm -rf .output
    tar -xzf frontend-output.tar.gz
    rm -f frontend-output.tar.gz"

  run_frontend_deploy_on_server

  rm -f "$ARCHIVE"
  log_info "Frontend deploy completed."
}

deploy_backend() {
  log_info "=== Deploying Backend ==="
  cd "$ROOT_DIR/daizima-backend"

  if [ "$SKIP_PULL" = false ]; then
    log_info "Pulling latest backend code..."
    git pull origin main
  fi

  ARCHIVE="/tmp/daizima-backend-$(date +%Y%m%d_%H%M%S).tar.gz"
  log_info "Creating source archive..."
  tar -czf "$ARCHIVE" \
    --exclude='.git' \
    --exclude='.env' \
    --exclude='vendor' \
    --exclude='node_modules' \
    --exclude='storage/logs' \
    --exclude='storage/framework/cache/data' \
    --exclude='bootstrap/cache/*.php' \
    -C "$ROOT_DIR/daizima-backend" .

  ARCHIVE_SIZE="$(du -h "$ARCHIVE" | cut -f1)"
  log_info "Archive ready: $ARCHIVE ($ARCHIVE_SIZE)"

  log_info "Uploading single archive to server..."
  upload_file "$ARCHIVE" "${REMOTE_BACKEND_PATH}/deploy-source.tar.gz"

  log_info "Extracting on server and running offline update..."
  remote "set -e
    cd '$REMOTE_BACKEND_PATH'
    tar -xzf deploy-source.tar.gz
    rm -f deploy-source.tar.gz
    chmod +x update-offline.sh
    bash update-offline.sh"

  rm -f "$ARCHIVE"
  log_info "Backend deploy completed."
}

case "$TARGET" in
  frontend)
    deploy_frontend
    ;;
  backend)
    deploy_backend
    ;;
  all)
    deploy_backend
    deploy_frontend
    ;;
  *)
    echo "Usage: $0 [frontend|backend|all] [--skip-pull] [--skip-build]"
    exit 1
    ;;
esac

log_info "All requested deploy steps finished."
