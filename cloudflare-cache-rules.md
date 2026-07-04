# Cloudflare Cache Rules — Daizima

> **دامنه:** `daizima.com` (پشت Cloudflare orange-cloud)  
> **هدف:** کاهش TTFB و bandwidth برای assets ثابت، بدون stale شدن HTML/API

---

## پیشنهاد Cache Rules (Dashboard → Rules → Cache Rules)

### Rule 1 — Hashed Nuxt assets (اولویت بالا)

| Field | Value |
|-------|--------|
| **If** | URI Path starts with `/_nuxt/` |
| **Then** | Cache eligibility: Eligible for cache |
| **Edge TTL** | Ignore cache-control → **1 year** |
| **Browser TTL** | Respect origin |

**دلیل:** فایل‌های hash شده immutable هستند؛ deploy جدید = نام فایل جدید.

---

### Rule 2 — Static public assets

| Field | Value |
|-------|--------|
| **If** | URI Path matches `*.woff2`, `*.webp`, `*.svg`, `/fonts/*`, `/images/*` |
| **Then** | Edge TTL: **30 days** |

---

### Rule 3 — HTML homepage (اختیاری — با Nitro SWR هماهنگ)

| Field | Value |
|-------|--------|
| **If** | URI Path equals `/` |
| **Then** | Edge TTL: **60 seconds** (یا Respect origin) |

**نکته:** اگر Nitro `swr: 60` فعال است، origin خودش HTML تازه می‌دهد؛ Cloudflare می‌تواند `Respect origin headers` باشد.

---

### Rule 4 — Bypass cache (هرگز cache نشوند)

| Field | Value |
|-------|--------|
| **If** | URI Path starts with `/api/`, `/panel/`, `/user-panel/`, `/checkout/`, `/cart` |
| **Then** | Cache eligibility: **Bypass cache** |

---

### Rule 5 — Service Worker (PWA)

| Field | Value |
|-------|--------|
| **If** | URI Path is `/sw.js`, `/workbox-*.js`, `/manifest.webmanifest` |
| **Then** | Bypass cache یا Edge TTL: **0** |

---

## Page Rules قدیمی (اگر Cache Rules در دسترس نیست)

```
/_nuxt/*     → Cache Level: Cache Everything, Edge TTL: 1 month
/api/*       → Cache Level: Bypass
/sw.js       → Cache Level: Bypass
```

---

## Brotli در Cloudflare

Dashboard → **Speed** → **Optimization**:

- ✅ Brotli
- ✅ Auto Minify: **فقط HTML** (JS/CSS را minify نکن — origin قبلاً minify کرده)

---

## بعد از deploy

1. DevTools → Network → response header `cf-cache-status` برای `/_nuxt/*.js`
2. انتظار: `HIT` بعد از اولین request
3. HTML `/` → `DYNAMIC` یا `MISS` با TTL کوتاه
