# Multi-app frontend (storefront / admin / user)

## Domains

| App | Domain | Local | PM2 / port |
|-----|--------|-------|------------|
| Storefront | `https://daizima.com` | `http://127.0.0.1:3021` | `:3021` |
| Admin | `https://admin.daizima.com` | `http://127.0.0.1:3022` | `:3022` |
| User | `https://user.daizima.com` | `http://127.0.0.1:3023` | `:3023` |

**Deploy is GitHub-only** (`daizima-frontend-new` → Actions → Deploy apps). No deploy on push. Guide: [`daizima-frontend-new/docs/GITHUB_DEPLOY.md`](../daizima-frontend-new/docs/GITHUB_DEPLOY.md).

| Phase | Nginx | Live shop |
|-------|--------|-----------|
| 1 (now) | [`_remote-nginx-admin-user.conf`](_remote-nginx-admin-user.conf) + [`_remote-nginx-apex-bridge.inc`](_remote-nginx-apex-bridge.inc) | Old Nuxt `:3000`; `/auth` + `/_sf/` → new storefront `:3021` |
| 2 (cutover) | [`_remote-nginx-multi-app.conf`](_remote-nginx-multi-app.conf) | Apex `/` → `:3021`; then `pm2 stop daizima-frontend` |

Legacy monolith conf: [`_remote-nginx-https.conf`](_remote-nginx-https.conf) / [`_remote-nginx-current.conf`](_remote-nginx-current.conf).

## DNS / SSL

1. Add A/AAAA (or CNAME via Cloudflare) for `admin` and `user`.
2. Issue certs (certbot or reuse Cloudflare Origin used by apex).
3. Phase 1: install admin/user vhosts, include the apex bridge inside the **existing** daizima.com server. Do not point `/` at `:3021` yet.

```bash
nginx -t && systemctl reload nginx
```

## Frontend env (production)

Baked at **GitHub Actions build** from `.env.prod` (plus repo Variables). Also copied to `/var/www/daizima-frontend-new/.env` for runtime.

```
NUXT_PUBLIC_STOREFRONT_URL=https://daizima.com
NUXT_PUBLIC_ADMIN_APP_URL=https://admin.daizima.com
NUXT_PUBLIC_USER_APP_URL=https://user.daizima.com
NUXT_PUBLIC_AUTH_COOKIE_DOMAIN=.daizima.com
NUXT_PUBLIC_API_BASE_URL=/api
# Admin cart alerts (Laravel Reverb). Prefer admin host that serves location /ws/
NUXT_PUBLIC_WEBSOCKET_URL=wss://admin.daizima.com/ws
```

WebSocket + product cache deploy checklist: [`WEBSOCKET_AND_CACHE.md`](WEBSOCKET_AND_CACHE.md)

## Auth cookie SSO

- Login only on storefront (old shop until cutover).
- Token in `localStorage` (`access_token`) **and** JS cookie `dz_auth` with `Domain=.daizima.com`.
- Phase 1: `/auth/continue` on `:3021` writes that cookie from localStorage.
- Admin/user copy cookie → their own `localStorage` on boot.

## Legacy redirects

- `daizima.com/panel/*` → `admin.daizima.com/*`
- `daizima.com/user-panel/*` → `user.daizima.com/*`

## PM2

Managed by GitHub Action + `daizima-frontend-new/ecosystem.config.cjs`. Do not `pm2 stop daizima-frontend` until storefront cutover.
