# چک‌لیست Production — daizima.com + Cloudflare

> **وضعیت repo:** آدرس‌های عمومی به `https://daizima.com` به‌روز شده‌اند. روی **سرور production** هنوز باید `.env` واقعی، nginx و پنل‌های پرداخت را مطابق این سند تنظیم کنید.

---

## بخش ۱ — تنظیمات سرور (الان)

### ۱.۱ بک‌اند — `/var/www/daizima-backend/.env`

```env
APP_URL=https://daizima.com
FRONTEND_URL=https://daizima.com
FORCE_HTTPS=true

CORS_ALLOWED_ORIGINS=https://daizima.com,https://www.daizima.com

MELLAT_CALLBACK_URL=https://daizima.com/api/v1/payments/mellat/callback
MELLAT_FRONTEND_RESULT_URL=https://daizima.com/checkout/payment/result
ZARINPAL_CALLBACK_URL=https://daizima.com/api/v1/payments/zarinpal/callback
ZARINPAL_FRONTEND_RESULT_URL=https://daizima.com/checkout/payment/result
```

```bash
cd /var/www/daizima-backend
docker-compose exec app php artisan config:clear
docker-compose exec app php artisan cache:clear
docker-compose restart
```

### ۱.۲ فرانت‌اند — `/var/www/daizima-frontend/.env`

```env
NUXT_PUBLIC_API_BASE_URL=/api
NUXT_API_PROXY_TARGET=http://127.0.0.1:8000
NUXT_PUBLIC_SITE_URL=https://daizima.com
NUXT_PUBLIC_WEBSOCKET_URL=wss://daizima.com/ws
NUXT_PUBLIC_APP_ENV=production
```

سپس **rebuild** (متغیرهای `NUXT_PUBLIC_*` در زمان build embed می‌شوند):

```bash
cd /var/www/daizima-frontend
./update.sh
```

### ۱.۳ nginx

فایل: `deployment/nginx/frontend-production.conf` — `server_name daizima.com www.daizima.com 212.23.201.113`

کپی به سرور و:

```bash
nginx -t && systemctl reload nginx
```

### ۱.۴ تست

```bash
curl -I https://daizima.com/api/v1/categories/tree
# HTTP/2 200 — نه 301 به IP و نه certificate error
```

---

## بخش ۲ — SSL با Cloudflare

دامنه پشت Cloudflare است؛ SSL برای **کاربر** معمولاً روی Cloudflare تمام می‌شود. روی **origin (سرور)** بسته به حالت SSL:

| حالت Cloudflare | بین کاربر ↔ Cloudflare | بین Cloudflare ↔ سرور شما |
|-----------------|------------------------|---------------------------|
| **Flexible** | HTTPS | HTTP (پورت 80) |
| **Full** | HTTPS | HTTPS (گواهی self-signed هم OK) |
| **Full (strict)** | HTTPS | HTTPS + گواهی معتبر روی origin |

**پیشنهاد:** `Full (strict)` + گواهی Origin روی سرور (یا Let's Encrypt).

### ۲.۱ Cloudflare Dashboard

1. **DNS:** رکورد `A` برای `@` و `www` → `212.23.201.113` با **Proxied** (نارنجی)
2. **SSL/TLS → Overview:** `Full (strict)` (یا موقتاً `Full` تا گواهی origin نصب شود)
3. **SSL/TLS → Edge Certificates:** `Always Use HTTPS` = ON
4. **SSL/TLS → Origin Server:** Create Certificate → نصب روی nginx (برای strict)
5. (اختیاری) **Rules → Redirect:** `http://*daizima.com/*` → `https://daizima.com`

### ۲.۲ گواهی روی سرور (یکی از دو روش)

**روش A — Cloudflare Origin Certificate (ساده با Full strict):**

1. در Cloudflare: Origin Certificate برای `daizima.com` و `*.daizima.com`
2. فایل‌ها را روی سرور بگذار (مثلاً `/etc/ssl/cloudflare/`)
3. بلوک `listen 443 ssl` در nginx را فعال کن با همان مسیرها

**روش B — Let's Encrypt (بدون وابستگی به Cloudflare cert):**

```bash
certbot certonly --nginx -d daizima.com -d www.daizima.com
```

> اگر Cloudflare Proxied است، ممکن است لازم باشد موقتاً DNS-only (خاکستری) شود یا از DNS challenge استفاده کنید.

### ۲.۳ nginx — HTTPS روی origin (برای Full / Full strict)

در `frontend-production.conf` بلوک HTTPS را uncomment/configure کن و redirect HTTP:

```nginx
return 301 https://daizima.com$request_uri;
```

در همه locationهای proxy:

```nginx
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header Host $host;
```

`ForceHttps` در Laravel با `X-Forwarded-Proto: https` از Cloudflare هم کار می‌کند.

### ۲.۴ پنل‌های پرداخت

Callbackها را **دقیقاً** به این آدرس‌ها به‌روز کنید:

- Mellat: `https://daizima.com/api/v1/payments/mellat/callback`
- Zarinpal: `https://daizima.com/api/v1/payments/zarinpal/callback`

### ۲.۵ Redirect IP → دامنه (توصیه)

برای `server_name 212.23.201.113` (یا در همان server block):

```nginx
return 301 https://daizima.com$request_uri;
```

### ۲.۶ چک‌لیست نهایی

- [ ] `https://daizima.com` بدون certificate error
- [ ] API: `curl -I https://daizima.com/api/v1/categories/tree` → 200
- [ ] WebSocket: `wss://daizima.com/ws` (اگر استفاده می‌کنید)
- [ ] login / cart / checkout
- [ ] بازگشت از درگاه به `/checkout/payment/result`
- [ ] تصاویر `storage` با `https://daizima.com/storage/...` (بعد از `APP_URL`)
- [ ] Google Search Console + sitemap `https://daizima.com/sitemap.xml`

---

## بخش ۳ — فاز قبلی IP (فقط برای rollback)

اگر موقتاً باید روی IP خام کار کنید: `FORCE_HTTPS=false` و `APP_URL`/`FRONTEND_URL` روی IP — **بعد از مهاجرت به دامنه استفاده نکنید.**

---

## خلاصه env

| تنظیم | مقدار production |
|--------|-------------------|
| `FORCE_HTTPS` | `true` |
| `APP_URL` / `FRONTEND_URL` | `https://daizima.com` |
| `NUXT_PUBLIC_SITE_URL` | `https://daizima.com` |
| `NUXT_PUBLIC_API_BASE_URL` | `/api` |
| `NUXT_PUBLIC_WEBSOCKET_URL` | `wss://daizima.com/ws` |
| `DEPLOY_HOST` (SSH) | `212.23.201.113` (همان IP سرور) |
