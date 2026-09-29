# دیپلوی WebSocket (Reverb) + کش محصول / Cloudflare

این سند چک‌لیست **production** برای قابلیت‌های اخیر است:

1. اعلان لحظه‌ای افزودن به سبد در پنل ادمین (Laravel Reverb + Echo)
2. باطل‌سازی کش Redis/Cloudflare هنگام تغییر قیمت یا موجودی
3. همگام‌سازی سبد فروشگاه قبل از پرداخت (قیمت / ناموجود)

جزئیات فنی عمیق‌تر:

- Backend: [`daizima-backend/docs/REVERB_ADMIN_CART_ALERTS.md`](../daizima-backend/docs/REVERB_ADMIN_CART_ALERTS.md)
- Backend: [`daizima-backend/docs/PRODUCT_CART_CACHE_INVALIDATION.md`](../daizima-backend/docs/PRODUCT_CART_CACHE_INVALIDATION.md)
- Cloudflare Rules: [`cloudflare-cache-rules.md`](cloudflare-cache-rules.md)
- Multi-app domains: [`MULTI_APP.md`](MULTI_APP.md)

---

## معماری خلاصه

| قطعه | نقش |
|------|-----|
| Docker `websocket` | `php artisan reverb:start --host=0.0.0.0 --port=6001` |
| Host port | `6101` → container `6001` |
| Nginx `location /ws/` | پروکسی به `127.0.0.1:6101/` با **strip کردن پیشوند `/ws`** |
| Admin Echo | `NUXT_PUBLIC_WEBSOCKET_URL` → کانال خصوصی `admin.carts` |
| Auth | `POST /api/broadcasting/auth` (Sanctum Bearer) |
| Product cache | Redis version bump + اختیاری Cloudflare purge API |

---

## ۱) Backend — env روی سرور

مسیر: `/var/www/daizima-backend/.env`

### Reverb / Broadcast (الزامی برای اعلان سبد)

```env
BROADCAST_CONNECTION=reverb
BROADCAST_DRIVER=reverb

REVERB_APP_ID=daizima
REVERB_APP_KEY=<random-secure>
REVERB_APP_SECRET=<random-secure>
REVERB_SERVER_HOST=0.0.0.0
REVERB_SERVER_PORT=6001
REVERB_HOST=websocket
REVERB_PORT=6001
REVERB_SCHEME=http

# مرورگر ادمین از پشت Cloudflare/nginx
REVERB_CLIENT_HOST=admin.daizima.com
REVERB_CLIENT_PORT=443
REVERB_CLIENT_SCHEME=https
REVERB_CLIENT_PATH=/ws
```

`PUSHER_*` را با همان `APP_ID` / `KEY` / `SECRET` و host داخلی `websocket` هم‌تراز نگه دارید (سازگاری Echo/Pusher protocol).

### Cloudflare product purge (توصیه‌شده)

```env
CLOUDFLARE_ZONE_ID=<zone-id-daizima.com>
CLOUDFLARE_API_TOKEN=<token-با-Cache-Purge>
CLOUDFLARE_STOREFRONT_ORIGIN=https://daizima.com
```

بدون این سه مقدار، فقط باطل‌سازی Redis انجام می‌شود؛ کش edge تا TTL origin (~۶۰s برای catalog) کهنه می‌ماند.

نمونه کامل: `daizima-backend/.env.prod.example`

---

## ۲) Backend — دستورات دیپلوی

از ریشه monorepo (با SSH key):

```bash
./deploy/deploy-from-local.sh backend --skip-pull
# یا روی سرور:
cd /var/www/daizima-backend
# dub   # یا ./update.sh
```

بعد از آپدیت `.env` و کد:

```bash
cd /var/www/daizima-backend

# حتماً با docker-compose (نه docker compose) طبق قرارداد پروژه
docker-compose up -d --force-recreate websocket
docker-compose exec app php artisan config:clear
docker-compose exec app php artisan config:cache

# وضعیت
docker-compose ps websocket
docker-compose logs --tail=80 websocket
```

اگر `BROADCAST_DRIVER=null` یا سرویس websocket بالا نباشد، اعلان ادمین کار نمی‌کند.

---

## ۳) Nginx — `/ws/` روی دامنه‌های لازم

قالب‌های به‌روز در همین پوشه:

- [`_remote-nginx-admin-user.conf`](_remote-nginx-admin-user.conf) — `admin.daizima.com` (+ user)
- [`_remote-nginx-multi-app.conf`](_remote-nginx-multi-app.conf) — apex + admin
- [`_remote-nginx-https.conf`](_remote-nginx-https.conf) / [`_remote-nginx-current.conf`](_remote-nginx-current.conf)

الگوی صحیح (توجه به `/` انتهای `proxy_pass` برای strip):

```nginx
location /ws/ {
    proxy_pass http://127.0.0.1:6101/;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout 60s;
}
```

روی سرور بعد از کپی conf:

```bash
nginx -t && systemctl reload nginx
```

حداقل روی **`admin.daizima.com`** لازم است (پنل اعلان). برای یکپارچگی، روی `daizima.com` هم بگذارید.

---

## ۴) Frontend — Admin + Storefront

فرانت جدید فقط از **GitHub Actions** دیپلوی می‌شود. راهنما: [`daizima-frontend-new/docs/GITHUB_DEPLOY.md`](../daizima-frontend-new/docs/GITHUB_DEPLOY.md)

### متغیرهای build / GitHub Variables

| متغیر | مقدار production پیشنهادی |
|--------|---------------------------|
| `NUXT_PUBLIC_WEBSOCKET_URL` | `wss://admin.daizima.com/ws` (ادمین) — یا `wss://daizima.com/ws` اگر فقط روی apex پروکسی شده |
| `NUXT_PUBLIC_API_BASE_URL` | `/api` |
| `NUXT_PUBLIC_STOREFRONT_URL` | `https://daizima.com` |
| `NUXT_PUBLIC_ADMIN_APP_URL` | `https://admin.daizima.com` |

نمونه محلی / Actions: `daizima-frontend-new/.env.prod` و workflow `deploy.yml`.

> **نکته:** URL باید با دامنهٔ همان vhost که `location /ws/` دارد یکی باشد تا handshake بدون CORS/کوکی عجیب انجام شود. برای پنل ادمین ترجیح: `wss://admin.daizima.com/ws`.

### دیپلوی فرانت

1. bump ورژن در صورت نیاز: `./deploy/versioning/bump-frontend.sh --no-tag --yes`
2. push به ریپوی `daizima-frontend-new`
3. Actions → **Deploy apps** (storefront + admin + user)

بعد از دیپلوی، hard refresh روی `admin.daizima.com`.

---

## ۵) Cloudflare Dashboard (الزامی برای قیمت/موجودی تازه)

جزئیات کامل: [`cloudflare-cache-rules.md`](cloudflare-cache-rules.md)

حداقل‌ها:

1. **Bypass** برای `/api/v1/cart*`, checkout, auth, admin (بالاترین اولویت)
2. **Bypass** برای `special_offer=true` و `/api/v2/special-offer-products`
3. قانون catalog `/api/v1/products*`: Edge TTL = **Respect origin** (نه Ignore cache-control)
4. توکن با **Cache Purge** → در `.env` بک‌اند (`CLOUDFLARE_API_TOKEN` + `ZONE_ID`)

بدون Respect origin، حتی با `no-store` از Laravel، HIT کهنه روی edge می‌ماند.

---

## ۶) چک‌لیست تست بعد از دیپلوی

### WebSocket / اعلان ادمین

1. لاگین `admin.daizima.com`
2. DevTools → Network → WS: اتصال به `/ws/...` / status 101
3. از فروشگاه یک کالا به سبد اضافه کنید
4. در ادمین: زنگ اعلان + صدا + کارت (قیمت / ناموجود کردن)

اگر WS fail شد: `websocket` container، nginx `/ws/`، و `NUXT_PUBLIC_WEBSOCKET_URL` را چک کنید.

### کش قیمت / موجودی

1. قیمت یا موجودی را از ادمین عوض کنید
2. PDP فروشگاه را رفرش کنید — باید قیمت/ناموجود تازه باشد (نه اسنپ‌شات ۲ دقیقه قبل)
3. اگر `CLOUDFLARE_*` ست است، در لاگ Laravel خطای purge نباشد

### سبد فروشگاه

1. کالا در سبد → ادمین قیمت را عوض کند یا ناموجود کند
2. صفحه سبد / دکمه پرداخت → مودال «تغییرات سبد» (قیمت و/یا ناموجود)
3. بعد از تأیید، ناموجودها حذف و پرداخت با قیمت جدید ادامه یابد

---

## ۷) ترتیب پیشنهادی یک release کامل

```text
1. Backend .env (Reverb + Cloudflare) روی سرور
2. Deploy backend + recreate websocket + config:cache
3. Reload nginx با /ws/
4. Deploy frontend-new (admin + storefront) از GitHub Actions
   با NUXT_PUBLIC_WEBSOCKET_URL صحیح
5. تأیید Cloudflare Cache Rules (Respect origin + Bypass cart)
6. تست چک‌لیست بخش ۶
```

ورژن‌گذاری:

```bash
./deploy/versioning/bump-backend.sh --no-tag --yes
./deploy/versioning/bump-frontend.sh --no-tag --yes
```

---

## عیب‌یابی سریع

| علامت | احتمال |
|--------|--------|
| اعلان ادمین نمی‌آید | `BROADCAST_*=null`، websocket down، nginx بدون `/ws/`، توکن ادمین برای `/api/broadcasting/auth` |
| WS 404 / failed / **502** | nginx اشتباه: باید `location /ws/` → `proxy_pass http://127.0.0.1:6101/;` باشد (پورت **6101** با strip؛ نه `6001`) |
| PDP قیمت کهنه | Redis OK ولی Cloudflare Ignore cache-control؛ یا `CLOUDFLARE_*` خالی |
| سبد ناگهان خالی بدون مودال | دیپلوی فرانت/بک قدیمی؛ باید sync با `prune_unavailable` فقط بعد از تأیید UI باشد |
| صدا پخش نمی‌شود | autoplay مرورگر — یک‌بار کلیک روی پنل ادمین |

**دایزیما** · https://daizima.com/ · https://admin.daizima.com/
