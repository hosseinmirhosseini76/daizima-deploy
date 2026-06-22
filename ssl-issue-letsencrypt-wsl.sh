#!/bin/bash
# Run inside WSL: issues LE cert via Cloudflare DNS and uploads to server.
set -e

ENV_FILE="/mnt/g/business/Daizima/deploy/deploy.local.env"
CF_TOKEN=$(grep '^CLOUDFLARE_API_TOKEN=' "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d '\r\n')
DEPLOY_HOST=$(grep '^DEPLOY_HOST=' "$ENV_FILE" | cut -d= -f2- | tr -d '\r\n')
DEPLOY_PORT=$(grep '^DEPLOY_PORT=' "$ENV_FILE" | cut -d= -f2- | tr -d '\r\n')
DEPLOY_USER=$(grep '^DEPLOY_USER=' "$ENV_FILE" | cut -d= -f2- | tr -d '\r\n')

if [ -z "$CF_TOKEN" ]; then
  echo "CLOUDFLARE_API_TOKEN missing in deploy.local.env"
  exit 1
fi

export CF_Token="$CF_TOKEN"

if [ ! -x "$HOME/.acme.sh/acme.sh" ]; then
  curl -fsSL https://get.acme.sh | sh -s email=admin@daizima.com
fi

"$HOME/.acme.sh/acme.sh" --issue -d daizima.com -d www.daizima.com \
  --dns dns_cf --server letsencrypt --keylength ec-256 --force --dnssleep 90

CERT_DIR="$HOME/.acme.sh/daizima.com_ecc"
FULLCHAIN="$CERT_DIR/fullchain.cer"
PRIVKEY="$CERT_DIR/daizima.com.key"

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

echo "Done: https://daizima.com"
