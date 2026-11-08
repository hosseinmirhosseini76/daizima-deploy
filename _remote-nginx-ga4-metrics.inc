# GA4 first-party measurement path (origin gateway, no Cloudflare proxy required).
# Browser → https://daizima.com/metrics/... → https://G-SMV686PG1P.fps.goog/metrics/...
# Keep the /metrics prefix (do not rewrite it away). IPv4-only resolver (origin IPv6 to fps is broken).
# Health: GET /metrics/healthy → "ok"
#
# Production path: /etc/nginx/snippets/daizima-ga4-first-party.inc
# (included from sites-enabled/daizima-frontend). Backup before edits.

location ^~ /metrics/ {
    resolver 1.1.1.1 8.8.8.8 ipv6=off valid=300s;
    set $ga4_fps_host G-SMV686PG1P.fps.goog;
    proxy_pass https://$ga4_fps_host;
    proxy_http_version 1.1;
    proxy_ssl_server_name on;
    proxy_ssl_name G-SMV686PG1P.fps.goog;
    proxy_set_header Host G-SMV686PG1P.fps.goog;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Country IR;
    proxy_buffering off;
    proxy_connect_timeout 10s;
    proxy_read_timeout 30s;
    add_header Cache-Control "no-store" always;
    add_header X-GA4-Proxy fps always;
}
