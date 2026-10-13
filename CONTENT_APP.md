# Content Platform + Content Bot

> **Cutover دامنه انجام شد (DNS + nginx + CORS).**  
> اپ Nuxt روی PM2 `:3024` را با GitHub Actions (`apps=content` یا تیک content) دیپلوی کنید؛ تا قبل از آن دامنه ممکن است 502 بدهد.

## چه چیزی با `deploy-from-local.sh backend` می‌رود؟

| قطعه | مسیر | با backend deploy؟ |
|------|------|---------------------|
| API Content Bot | `/api/content/bot/*` | بله |
| سرویس‌ها / Job / Queue timeout | `app/Services/Content/...`, `RunContentBotJob`, `docker/queue-start.sh` | بله |
| سورس Worker + host-relay | `workers/content-bot-llm/` (بدون `node_modules`) | بله (فایل‌ها) |
| Cloudflare Worker live | `*.workers.dev` | **خیر** — جدا Deploy شود |
| Nuxt `apps/content` | PM2 `:3024` | **جدا** — GitHub Actions با تیک `content` / `apps=content` (`all` شاملش نیست). nginx: `_remote-nginx-content.conf` |

`node_modules` داخل worker در آرشیو tar نیست (`--exclude=node_modules`).

---

## پیش‌نیاز قبل از اولین backend deploy برای Bot

### ۱) Cloudflare Worker + دامنه روی زون daizima (لازم برای پروداکشن ایران)

از VPS پروداکشن، `*.workers.dev` و `generativelanguage.googleapis.com` مستقیم در دسترس نیستند
(timeout / SSL EOF / HTML 403). مسیر درست: **Custom Domain روی همان زون** تا درخواست از داکر به
`content-llm.daizima.com` برود (مثل `daizima.com` که باز است) و Cloudflare خودش Worker را اجرا کند.

1. کد Worker: [`workers/content-bot-llm/src/index.js`](../daizima-backend/workers/content-bot-llm/src/index.js) (استریم، بدون `.text()`).
2. در Dashboard → Workers → `daizima-content-bot-llm` → **Domains & Routes** → **Add** → Custom Domain:
   `content-llm.daizima.com`  
   (رکورد DNS از قبل ساخته شده؛ اگر خطا داد همان CNAME را نگه دارید / Confirm کنید.)
3. تست از بیرون:
   `curl -X POST https://content-llm.daizima.com -H 'Content-Type: application/json' -d '{"model":"gemini-flash-lite-latest","messages":[{"role":"user","content":"ping"}],"max_tokens":4}'`
   باید JSON مدل برگردد (نه 522).
4. روی سرور `.env`:
   `CONTENT_BOT_LLM_API_URL=https://content-llm.daizima.com`
   سپس `docker-compose exec app php artisan config:cache` و `docker-compose up -d --force-recreate --no-deps queue`

Worker خام: `https://daizima-content-bot-llm.daizimaofficial.workers.dev` (فقط لوکال/ویندوز).

### ۲) مقادیر در `deploy/deploy.local.env`

```env
# Content Bot — synced to /var/www/daizima-backend/.env on backend deploy
CONTENT_BOT_LLM_API_KEY=          # Gemini key (یا از daizima-backend/.env خوانده می‌شود اگر خالی باشد)
CONTENT_BOT_LLM_API_URL=https://daizima-content-bot-llm.daizimaofficial.workers.dev
CONTENT_BOT_LLM_MODEL=gemini-3.5-flash
CONTENT_BOT_PUBLISH_AS_DRAFT=true
# CONTENT_BOT_SERPER_API_KEY=
# CONTENT_BOT_LLM_RELAY_TOKEN=
REDIS_QUEUE_RETRY_AFTER=660
```

**مهم:** روی پروداکشن هرگز `CONTENT_BOT_LLM_API_URL=http://host.docker.internal:8791` نگذارید — آن فقط لوکال ویندوز است.

اگر داخل کانتینر پروداکشن TLS به `workers.dev` شکست (`SSL unexpected eof`):

```bash
# روی خودِ VPS (host)، نه داخل app container:
cd /var/www/daizima-backend/workers/content-bot-llm
CONTENT_BOT_WORKER_URL=https://daizima-content-bot-llm.daizimaofficial.workers.dev \
  node host-relay.mjs
# سپس در .env سرور:
# CONTENT_BOT_LLM_API_URL=http://172.17.0.1:8791
# (یا IP gateway داکر روی آن سرور) و queue را recreate کنید
```

---

## دستور دیپلوی بک‌اند (همین کار فعلی)

از ریشه monorepo:

```bash
./deploy/deploy-from-local.sh backend --skip-pull
```

اسکریپت روی سرور:

1. کد را extract می‌کند
2. `CONTENT_BOT_*` و `REDIS_QUEUE_RETRY_AFTER` را در `.env` upsert می‌کند (اگر در `deploy.local.env` مقدار داشته باشند)
3. `update-offline.sh` → migrate، cache، recreate `app` / `queue` / `websocket`

Queue از قبل `--timeout=600` دارد (`docker/queue-start.sh`) تا با `RunContentBotJob` هم‌خوان باشد.

---

## تأیید بعد از دیپلوی بک‌اند

```bash
ssh root@185.18.212.24
cd /var/www/daizima-backend

docker-compose exec -T app php artisan tinker --execute="
  echo json_encode([
    'model' => config('content.llm_model'),
    'url' => config('content.llm_api_url'),
    'has_key' => trim((string) config('content.llm_api_key')) !== '',
    'draft' => config('content.publish_as_draft'),
  ], JSON_UNESCAPED_UNICODE);
"

# health API (نیاز به توکن admin)
# curl -sS -H "Authorization: Bearer <token>" https://api-host/api/content/bot/health

docker-compose logs queue --tail 30
```

مقاله فقط وقتی ساخته می‌شود که از پنل Content (یا API) `dry_run=false` بزنید؛ پیش‌فرض `CONTENT_BOT_PUBLISH_AS_DRAFT=true` است.

---

## Local (مرجع سریع)

| Piece | Command / URL |
|-------|----------------|
| Nuxt content | `pnpm --filter @daizima/content dev` → `:3024` |
| Laravel API | `/api/content/bot/*` (admin \| super_admin) |
| Host relay | `node workers/content-bot-llm/host-relay.mjs` → `:8791` |
| Backend env | `CONTENT_BOT_LLM_API_URL=http://host.docker.internal:8791` |
| مدل پایدار | `CONTENT_BOT_LLM_MODEL=gemini-3.5-flash` (fallback: `CONTENT_BOT_LLM_FALLBACK_MODELS`) |

---

## Production SPA (live wiring)

| Item | Value |
|------|--------|
| Domain | `https://content.daizima.com` |
| DNS | Cloudflare A → `185.18.212.24` (Proxied) |
| Nginx | `/etc/nginx/sites-available/daizima-content` (repo: `_remote-nginx-content.conf`) |
| PM2 | `daizima-content` → `127.0.0.1:3024` (بعد از Actions) |
| Env FE | `NUXT_PUBLIC_CONTENT_APP_URL=https://content.daizima.com` |
| CORS | شامل `https://content.daizima.com` |

دیپلوی فرانت:

```bash
# بعد از commit+push روی daizima-frontend-new:
gh workflow run deploy.yml -f apps=admin,content
# یا در UI: تیک admin + content
```
