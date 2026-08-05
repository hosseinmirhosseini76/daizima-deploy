# Cloudflare Cache Rules — Daizima

> **دامنه:** `daizima.com` (پشت Cloudflare orange-cloud)  
> **هدف:** کاهش TTFB و bandwidth برای assets ثابت و APIهای عمومی

---

## Rule — Product / media storage (اولویت بالا برای سرعت عکس)

| Field | Value |
|-------|--------|
| **Name** | `Storage media cache` |
| **If (Edit expression)** | ببین پایین |
| **Then** | Cache eligibility: **Eligible for cache** |
| **Edge TTL** | Ignore cache-control → **30 days** (یا 1 year) |
| **Browser TTL** | Respect origin / 30 days |
| **Cache key** | Include query string = OFF کافی است (معمولاً query ندارند) |
| **Headers custom** | هیچ — `custom-header` نگذار |

```txt
(http.request.method eq "GET" and starts_with(http.request.uri.path, "/storage/"))
```

**تست (GET نه HEAD):**

```bash
curl -sD - -o /dev/null "https://daizima.com/storage/product_images/SOME.jpg" | grep -i cf-cache
curl -sD - -o /dev/null "https://daizima.com/storage/product_images/SOME.jpg" | grep -i cf-cache
# انتظار: MISS سپس HIT
```

---

## Rule — API locations Tipax/Tapin (انجام‌شده)

Expression با `GET` برای `/api/v1/tipax/*` locations، `/api/v1/tapin/*` locations، `/api/v1/locations/*`، shipping-*.

---

## Rule — API homepage / catalog (انجام‌شده)

`/api/v2/homepage-sections*`, `/api/v2/categories*`, `/api/v1/brands*`, `/api/v1/products` (GET).

**نکته:** `/api/v1/categories` legacy است و فعلاً ۵۰۰ می‌دهد — کش نمی‌شود.

---

## Rule — Hashed Nuxt assets

| Field | Value |
|-------|--------|
| **If** | URI Path starts with `/_nuxt/` |
| **Then** | Eligible for cache |
| **Edge TTL** | **1 year** |
| **Browser TTL** | Respect origin |

---

## Rule — Bypass (خصوصی)

Bypass برای: `/api/v1/tipax/check-price`, `/api/v1/tapin/check-price`, `/api/*/cart*`, `/api/*/checkout*`, `/api/*/auth*`, `/api/*/payments*`, `/api/*/admin*`, `/panel/`, `/checkout/`, `/cart`.

> دیگر کل `/api/` را Bypass نکن — با Ruleهای کش عمومی تداخل دارد. Bypassها را **بالاتر** از cache rules بگذار.

---

## Brotli

Dashboard → **Speed** → **Optimization**: Brotli ✅

---

## Origin nginx

روی سرور بعد از دیپلوی conf:

```bash
# از repo
sudo cp /var/www/daizima-backend/deployment/nginx/frontend-production-https.conf /etc/nginx/sites-available/daizima-frontend
nginx -t && systemctl reload nginx
```

`/storage/` باید `Cache-Control: public, max-age=2592000, immutable` بدهد.
