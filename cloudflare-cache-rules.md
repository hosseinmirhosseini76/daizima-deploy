# Cloudflare Cache Rules — Daizima

> **دامنه:** `daizima.com` (پشت Cloudflare orange-cloud)  
> **هدف:** کش طولانی برای assets ثابت، کش کوتاه برای catalog عمومی، و **بدون کش** برای پیشنهاد ویژه

قانون‌ها از **بالا به پایین** ارزیابی می‌شوند. Bypassها باید **بالاتر** از Eligible باشند.

---

## اعمال‌شده روی Cloudflare (۲۰۲۶-۰۸-۲۷)

- **Bypass special offer products** اضافه شد (آخرین قانونِ منطبق برای این URLها برنده است).
- **API Products Cache** و **API homepage catalog cache**: `special_offer` از expression حذف شد؛ Edge TTL = **Respect origin**.
- **Homepage Cache**: Browser TTL = Respect origin (دیگر ۱ سال نیست).
- Zone **Browser Cache TTL** از ۱ سال به **Respect Existing Headers (0)** تغییر کرد.
- کل کش zone **purge** شد.

تأیید پروداکشن: `/api/v1/products?special_offer=true` حالا `cf-cache-status: DYNAMIC` است (دیگر HIT با Age نیست).

---

## وضعیت قبلی (علت کندی پیشنهاد ویژه)

روی پروداکشن اندازه‌گیری شد:

| URL | `Cache-Control` origin | `cf-cache-status` | `Age` دیده‌شده |
|-----|------------------------|-------------------|----------------|
| `/api/v1/products?special_offer=true&…` | `private, no-store` | **HIT** | ۲۰۰–۳۰۰+ ثانیه |
| `/api/v1/products` (لیست عادی) | `s-maxage=60` | HIT | — |
| `/api/v1/brands` | `s-maxage=60` | HIT | ۳۲۰ ثانیه (بیشتر از ۶۰) |
| `/api/v2/homepage-sections` | `private` (قبلاً) | HIT | ۴۹۰+ ثانیه |
| `/api/v2/categories/tree` | `private` (قبلاً) | HIT | ۷۷۰+ ثانیه |
| `/api/v1/search` | — | DYNAMIC | کش نمی‌شود |
| `/` HTML | `s-maxage=60` | REVALIDATED | مرورگر: **max-age=۱ سال** |

نتیجه:

1. قانون **API homepage / catalog** روی `GET /api/v1/products` اعمال می‌شود و **Ignore cache-control** است.
2. origin برای پیشنهاد ویژه `no-store` می‌فرستد، ولی Cloudflare آن را نادیده می‌گیرد و لیست کهنه را HIT می‌کند.
3. Edge TTL این قانون بیشتر از origin است (حداقل ~۱۵ دقیقه؛ احتمالاً ۱ ساعت یا بیشتر).
4. HTML صفحه اول برای مرورگر `max-age=31536000` می‌گیرد — Browser TTL قانون HTML اشتباه است.

**کار فوری در Dashboard (بدون منتظر ماندن برای دیپلوی):**

1. یک Bypass با اولویت بالاتر از catalog اضافه کن (Rule Bypass — Special offer پایین).
2. در قانون catalog، Edge TTL را از Ignore به **Respect origin** عوض کن.
3. در قانون HTML، Browser TTL را **Respect origin** کن (نه ۱ سال).
4. Purge: `https://daizima.com/api/v1/products*` و `https://daizima.com/`.

---

## ترتیب پیشنهادی قوانین (اعمال کن)

### ۱) Bypass — Private / auth (بالاترین)

**Then:** Cache eligibility = **Bypass cache**

```txt
(http.request.method eq "GET" and (
  starts_with(http.request.uri.path, "/api/v1/cart")
  or starts_with(http.request.uri.path, "/api/v2/cart")
  or starts_with(http.request.uri.path, "/api/v1/checkout")
  or starts_with(http.request.uri.path, "/api/v1/auth")
  or starts_with(http.request.uri.path, "/api/v1/admin")
  or starts_with(http.request.uri.path, "/api/v2/admin")
  or starts_with(http.request.uri.path, "/api/v1/payments")
  or http.request.uri.path eq "/api/v1/tipax/check-price"
  or http.request.uri.path eq "/api/v1/tapin/check-price"
  or starts_with(http.request.uri.path, "/panel/")
  or starts_with(http.request.uri.path, "/checkout/")
  or http.request.uri.path eq "/cart"
))
```

> کل `/api/` را Bypass نکن — با کش catalog تداخل دارد.

### ۲) Bypass — Special offer products ⚠️ اجباری

بدون این قانون، پیشنهاد ویژه صفحه اول ساعت‌ها کهنه می‌ماند.

**Then:** Cache eligibility = **Bypass cache**

```txt
(
  http.request.method eq "GET"
  and (
    http.request.uri.path eq "/api/v2/special-offer-products"
    or (
      http.request.uri.path eq "/api/v1/products"
      and (
        http.request.uri.query contains "special_offer=true"
        or http.request.uri.query contains "special_offer=1"
      )
    )
  )
)
```

### ۳) Storage media cache

| Field | Value |
|-------|--------|
| **If** | پایین |
| **Then** | Eligible for cache |
| **Edge TTL** | Ignore cache-control → **30 days** |
| **Browser TTL** | Respect origin |

```txt
(http.request.method eq "GET" and starts_with(http.request.uri.path, "/storage/"))
```

**تست (GET نه HEAD):**

```bash
curl -sD - -o /dev/null "https://daizima.com/storage/product_images/SOME.jpg" | grep -i cf-cache
# انتظار: MISS سپس HIT
```

### ۴) Hashed Nuxt assets

| Field | Value |
|-------|--------|
| **If** | `starts_with(http.request.uri.path, "/_nuxt/")` |
| **Then** | Eligible for cache |
| **Edge TTL** | **1 year** |
| **Browser TTL** | Respect origin |

مسیر `/_nuxt/builds/` را در این قانون نگذار (origin خودش `no-cache` می‌دهد). اگر لازم شد Bypass جدا:

```txt
starts_with(http.request.uri.path, "/_nuxt/builds/")
```

### ۵) API locations Tipax/Tapin

Expression با `GET` برای `/api/v1/tipax/*` locations، `/api/v1/tapin/*` locations، `/api/v1/locations/*`، shipping-*.

Edge TTL: Respect origin (origin حدود `s-maxage=3600` می‌دهد).

### ۶) API homepage / catalog

```txt
(http.request.method eq "GET" and (
  starts_with(http.request.uri.path, "/api/v2/homepage-sections")
  or starts_with(http.request.uri.path, "/api/v2/categories")
  or starts_with(http.request.uri.path, "/api/v1/brands")
  or http.request.uri.path eq "/api/v1/products"
))
```

| Field | Value |
|-------|--------|
| **Then** | Eligible for cache |
| **Edge TTL** | **Respect origin** — نه Ignore |
| **Browser TTL** | Respect origin |
| **Cache key** | Query string را **شامل کن** |

`/api/v1/products?special_offer=true` را این قانون نباید کش کند؛ Rule ۲ Bypass می‌کند. اگر Bypass نباشد، origin حالا `Cloudflare-CDN-Cache-Control: no-store` می‌فرستد — فقط وقتی Edge TTL = Respect origin اثر دارد.

### ۷) HTML pages (صفحه اول)

اگر قانونی برای `/` یا «همه HTML» داری:

| Field | Value |
|-------|--------|
| **Then** | Eligible for cache |
| **Edge TTL** | Respect origin یا **60 seconds** |
| **Browser TTL** | **Respect origin** یا **0 / bypass** — هرگز ۱ سال |

origin باید بدهد: `Cache-Control: public, max-age=0, s-maxage=60, must-revalidate`

اگر Browser TTL = 1 year باشد، مرورگر HTML صفحه اول را تا یک سال نگه می‌دارد.

---

## Brotli

Dashboard → **Speed** → **Optimization**: Brotli ✅

---

## Origin nginx

روی سرور بعد از دیپلوی conf:

```bash
sudo cp /var/www/daizima-backend/deployment/nginx/frontend-production-https.conf /etc/nginx/sites-available/daizima-frontend
nginx -t && systemctl reload nginx
```

`/storage/` باید `Cache-Control: public, max-age=2592000, immutable` بدهد.  
HTML (`location /`) باید `max-age=0, s-maxage=60, must-revalidate` بدهد.

---

## تست بعد از تغییر قوانین

```bash
# باید BYPASS یا DYNAMIC باشد، نه HIT با Age چند دقیقه‌ای
curl -sD - -o /dev/null "https://daizima.com/api/v1/products?special_offer=true&per_page=12&in_stock=true" \
  | grep -iE 'cf-cache-status|cache-control|^age:'

curl -sD - -o /dev/null "https://daizima.com/api/v2/special-offer-products?per_page=12&in_stock=true" \
  | grep -iE 'cf-cache-status|cache-control|^age:'

# HTML: max-age نباید 31536000 باشد
curl -sD - -o /dev/null "https://daizima.com/" | grep -iE 'cache-control|cf-cache-status'
```

انتظار پیشنهاد ویژه: `cf-cache-status: DYNAMIC` یا `BYPASS`، و `Cache-Control` شامل `no-store`.

---

## توکن API برای اعمال خودکار

توکن با این دسترسی‌ها:

- Zone → **Cache Purge** → Purge
- Zone → **Cache Rules** → Edit (یا Zone Settings / Rulesets Edit)
- Zone → **Zone** → Read

Zone: `daizima.com`

توکن را در `deploy/deploy.local.env` به‌صورت `CLOUDFLARE_API_TOKEN=` بگذار (جایگزین مقدار فعلی). بعد از آن می‌توان قوانین را از API ساخت و کش `/api/v1/products*` را purge کرد.
