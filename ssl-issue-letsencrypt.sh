#!/bin/bash
# Issue a browser-trusted Let's Encrypt cert for daizima.com (grey-cloud / direct origin).
# Cloudflare Origin certificates are NOT trusted by browsers when users hit the server directly.
#
# Usage:
#   1) Cloudflare API (recommended): add CLOUDFLARE_API_TOKEN to deploy/deploy.local.env
#      ./deploy/ssl-issue-letsencrypt.sh
#   2) Manual DNS: ./deploy/ssl-issue-letsencrypt.sh --manual-dns
#      Add TXT records in Cloudflare DNS, then run again with --renew

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/deploy.local.env"

if [ -n "${MSYSTEM:-}" ] || [ -n "${WINDIR:-}" ]; then
  export MSYS_NO_PATHCONV=1
fi

if [ -f "$CONFIG_FILE" ]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

: "${DEPLOY_HOST:?Set DEPLOY_HOST in deploy/deploy.local.env}"
: "${DEPLOY_PORT:=15726}"
: "${DEPLOY_USER:=root}"

ACME_SH="${ACME_SH:-$HOME/.acme.sh/acme.sh}"
if [ ! -x "$ACME_SH" ]; then
  echo "acme.sh not found. Install: curl -fsSL https://get.acme.sh | sh"
  exit 1
fi

DOMAINS=(daizima.com www.daizima.com)
ISSUE_ARGS=(--server letsencrypt --keylength ec-256)

if [ "${1:-}" = "--renew" ]; then
  "$ACME_SH" --renew -d daizima.com -d www.daizima.com --force
elif [ "${1:-}" = "--manual-dns" ]; then
  "$ACME_SH" --issue -d daizima.com -d www.daizima.com \
    --dns --yes-I-know-dns-manual-mode-enough-go-ahead-please \
    "${ISSUE_ARGS[@]}"
  echo ""
  echo "Add the TXT records above in Cloudflare → DNS, wait 1–2 minutes, then:"
  echo "  ./deploy/ssl-issue-letsencrypt.sh --renew"
  exit 0
elif [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
  # Git Bash on Windows: acme.sh curl fails; use WSL script if available.
  if [ -n "${MSYSTEM:-}" ] && command -v wsl >/dev/null 2>&1; then
    echo "[INFO] Using WSL for acme.sh (Git Bash curl is unreliable)..."
    wsl bash -lc "bash /mnt/g/business/Daizima/deploy/ssl-issue-letsencrypt-wsl.sh"
    exit 0
  fi
  export CF_Token="$CLOUDFLARE_API_TOKEN"
  "$ACME_SH" --issue -d daizima.com -d www.daizima.com --dns dns_cf "${ISSUE_ARGS[@]}" --dnssleep 90
else
  echo "Set CLOUDFLARE_API_TOKEN in deploy/deploy.local.env (Zone DNS Edit), or use --manual-dns"
  exit 1
fi

CERT_DIR="$HOME/.acme.sh/daizima.com_ecc"
FULLCHAIN="$CERT_DIR/fullchain.cer"
PRIVKEY="$CERT_DIR/daizima.com.key"

if [ ! -f "$FULLCHAIN" ] || [ ! -f "$PRIVKEY" ]; then
  echo "Certificate files not found after issue."
  exit 1
fi

echo "Uploading certificate to server..."
scp -P "$DEPLOY_PORT" -o StrictHostKeyChecking=accept-new \
  "$FULLCHAIN" "${DEPLOY_USER}@${DEPLOY_HOST}:/tmp/daizima-fullchain.pem"
scp -P "$DEPLOY_PORT" -o StrictHostKeyChecking=accept-new \
  "$PRIVKEY" "${DEPLOY_USER}@${DEPLOY_HOST}:/tmp/daizima-privkey.pem"

ssh -p "$DEPLOY_PORT" -o StrictHostKeyChecking=accept-new "${DEPLOY_USER}@${DEPLOY_HOST}" bash -s << 'REMOTE'
set -e
mkdir -p /etc/letsencrypt/live/daizima.com
install -m 644 /tmp/daizima-fullchain.pem /etc/letsencrypt/live/daizima.com/fullchain.pem
install -m 600 /tmp/daizima-privkey.pem /etc/letsencrypt/live/daizima.com/privkey.pem
rm -f /tmp/daizima-fullchain.pem /tmp/daizima-privkey.pem

sed -i 's|/etc/ssl/cloudflare/daizima.com.pem|/etc/letsencrypt/live/daizima.com/fullchain.pem|g' \
  /etc/nginx/sites-available/daizima-frontend-ssl.conf
sed -i 's|/etc/ssl/cloudflare/daizima.com.key|/etc/letsencrypt/live/daizima.com/privkey.pem|g' \
  /etc/nginx/sites-available/daizima-frontend-ssl.conf

# HTTP: ACME webroot for future renewals
cat > /etc/nginx/sites-available/daizima-frontend << 'EOF'
server {
    listen 80;
    server_name daizima.com www.daizima.com 212.23.201.113;

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/certbot;
        default_type "text/plain";
    }

    location / {
        return 301 https://daizima.com$request_uri;
    }
}
EOF
rm -f /etc/nginx/sites-enabled/daizima-frontend
ln -sf /etc/nginx/sites-available/daizima-frontend /etc/nginx/sites-enabled/daizima-frontend

nginx -t && systemctl reload nginx
openssl x509 -in /etc/letsencrypt/live/daizima.com/fullchain.pem -noout -subject -issuer -dates
REMOTE

echo "Done. Test: https://daizima.com (green lock in browser)"
