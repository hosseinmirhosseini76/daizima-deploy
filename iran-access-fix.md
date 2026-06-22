# دسترسی مشتریان ایران — بدون تغییر DNS روی سیستم کاربر

> مشکل «سایت باز نمی‌شود» برای بسیاری از کاربران ایرانی به‌خاطر **Proxy نارنجی Cloudflare** است، نه DNS سیستم مشتری.
> بعضی ISPها / VPNها IPهای Cloudflare (`104.21.x`, `172.67.x`) را فیلتر یا کند می‌کنند.

## راه‌حل پیشنهادی (یک‌بار روی Cloudflare + سرور)

**DNS only (ابر خاکستری) + SSL روی خود سرور**

کاربر `daizima.com` را resolve می‌کند → مستقیم `212.23.201.113` → HTTPS روی سرور.
مشتری **هیچ کاری** نمی‌کند.

---

## مرحله ۱ — Cloudflare (۵ دقیقه)

1. **DNS → Records**
2. برای این رکوردها Proxy را **خاموش** کن (ابر **خاکستری** = DNS only):
   - `daizima.com` A → `212.23.201.113`
   - `www` A → `212.23.201.113`
   - `*` A → `212.23.201.113` (اختیاری)
3. **SSL/TLS → Overview** → بعد از نصب SSL روی سرور: **Full (strict)**
   - تا SSL origin آماده نشده: موقتاً **Full**

بعد از خاکستری شدن، `nslookup daizima.com` باید **`212.23.201.113`** بدهد (نه IP Cloudflare).

---

## مرحله ۲ — گواهی SSL روی سرور

### گواهی Origin Cloudflare (فقط پشت Proxy نارنجی)

اگر DNS **Proxied (نارنجی)** است، مرورگر گواهی Cloudflare را می‌بیند — Origin Certificate روی سرور کافی است.

### گواهی Let's Encrypt (DNS only / خاکستری — مرورگر سبز)

اگر DNS **خاکستری** است، کاربر مستقیم به `212.23.201.113` وصل می‌شود. **Origin Certificate مرورگر را قبول نمی‌کند** (خطای SSL). باید Let's Encrypt نصب شود:

```bash
# در Cloudflare: My Profile → API Tokens → Create → Zone DNS Edit
# سپس در deploy/deploy.local.env: CLOUDFLARE_API_TOKEN=...
./deploy/ssl-issue-letsencrypt.sh
```

یا دستی TXT در DNS (بدون API token):

```bash
./deploy/ssl-issue-letsencrypt.sh --manual-dns
# TXT را در Cloudflare اضافه کن، بعد:
./deploy/ssl-issue-letsencrypt.sh --renew
```

---

## مرحله ۲ (قدیم) — Origin Certificate (فقط با Proxy نارنجی)

1. Cloudflare → **SSL/TLS → Origin Server → Create Certificate**
2. Hostnames: `daizima.com`, `*.daizima.com`
3. روی سرور:

```bash
sudo mkdir -p /etc/ssl/cloudflare
sudo nano /etc/ssl/cloudflare/daizima.com.pem    # Certificate
sudo nano /etc/ssl/cloudflare/daizima.com.key    # Private Key
sudo chmod 600 /etc/ssl/cloudflare/daizima.com.key
```

---

## مرحله ۳ — nginx: فعال‌سازی HTTPS

فایل: `/etc/nginx/sites-available/daizima-frontend`

### ۳.۱ بلوک HTTP — فقط redirect

در `server { listen 80; ...}` خط redirect را **فعال** کن:

```nginx
return 301 https://daizima.com$request_uri;
```

و بقیه locationهای داخل همان server block را comment کن **یا** فقط redirect بگذار.

### ۳.۲ بلوک HTTPS — کپی همان locationها

از repo فایل `deployment/nginx/frontend-production-https.conf` را کپی کن:

```bash
sudo cp /var/www/daizima-backend/deployment/nginx/frontend-production-https.conf \
  /etc/nginx/sites-available/daizima-frontend-ssl.conf
sudo ln -sf /etc/nginx/sites-available/daizima-frontend-ssl.conf \
  /etc/nginx/sites-enabled/daizima-frontend-ssl.conf
```

یا محتوای HTTPS را در همان فایل site اضافه کن.

```bash
sudo nginx -t && sudo systemctl reload nginx
```

### ۳.۳ WebSocket

Docker websocket روی host پورت **6101** است:

```nginx
location /ws {
    proxy_pass http://127.0.0.1:6101;
    ...
}
```

---

## مرحله ۴ — تست (بدون تغییر DNS لوکال)

```bash
curl -sI https://212.23.201.113/ -k --resolve daizima.com:443:212.23.201.113 \
  -H "Host: daizima.com" | head -5

curl -sI https://daizima.com/ | head -5
```

مرورگر: `https://daizima.com`

---

## اگر هنوز بعضی کاربران باز نمی‌کنند

1. **دامنه `.ir` ثبت کن** (`daizima.ir`) → همان A record → برای بازار ایران
2. **آروان‌کلاد** (CDN ایرانی) به‌جای Cloudflare Proxy — برای فروشگاه داخلی رایج‌تر است
3. فیلتر بودن دامنه را در [fa.ir](https://faq.ir) / تست از اینترنت موبایل چک کن

---

## چرا DNS سیستم تو (10.255.255.1) فرق دارد؟

آن resolver مربوط VPN/آنتی‌virus است، نه ISP معمولی مشتری. با **DNS only** اکثر مشتریان `212.23.201.113` می‌گیرند و مستقیم وصل می‌شوند.
