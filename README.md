# Daizima Deploy

## Immediate Commands
```
./scripts/sync-production-db.sh -y root@185.18.212.24 /var/www/daizima-backend
./scripts/sync-production-db.sh --download-only root@185.18.212.24 /var/www/daizima-backend
./scripts/sync-production-storage.sh root@185.18.212.24 /var/www/daizima-backend
```

## Fast Backend Deploy
```
./deploy/deploy-from-local.sh backend --skip-pull
```

## سرور production


| تنظیم         | مقدار                       |
| ------------- | --------------------------- |
| Host          | `185.18.212.24`             |
| SSH Port      | `22`                        |
| User          | `root`                      |
| Backend path  | `/var/www/daizima-backend`  |
| Frontend path | `/var/www/daizima-frontend` |
| New FE path   | `/var/www/daizima-frontend-new` (storefront / admin / user) |


فرانت جدید **فقط از GitHub Actions** دیپلوی می‌شود (`daizima-frontend-new` → Deploy apps). پوش روی `main` آن را بالا نمی‌آورد. راهنما: `[daizima-frontend-new/docs/GITHUB_DEPLOY.md](../daizima-frontend-new/docs/GITHUB_DEPLOY.md)`. اسکریپت `deploy-from-local.sh frontend` هنوز فرانت **قدیمی** (`:3000`) را می‌فرستد.

اتصال SSH: `ssh root@185.18.212.24`  
تنظیمات دیپلوی محلی: `deploy/deploy.local.env` (از `deploy.local.env.example` کپی کنید).  
وقتی احراز هویت با SSH key کار می‌کند، `DEPLOY_PASSWORD` را خالی بگذارید.

## Multi-app domains

جزئیات: `[MULTI_APP.md](MULTI_APP.md)` — nginx: `[_remote-nginx-multi-app.conf](_remote-nginx-multi-app.conf)`

| دامنه | اپ | پورت |
|-------|-----|------|
| `daizima.com` | storefront | `3021` |
| `admin.daizima.com` | admin | `3022` |
| `user.daizima.com` | user | `3023` |
| `content.daizima.com` | content | `3024` |

## Content Bot (بک‌اند)

API و صف Content Bot با همان دیپلوی بک‌اند می‌آید. ساب‌دامین Content هنوز gated است.

**[`CONTENT_APP.md`](CONTENT_APP.md)** — env، Cloudflare Worker، تأیید بعد از دیپلوی.

خلاصه قبل از `./deploy/deploy-from-local.sh backend --skip-pull`:

| موضوع | عمل |
|--------|-----|
| Worker | کد `workers/content-bot-llm/src/index.js` روی CF Deploy باشد |
| `deploy.local.env` | `CONTENT_BOT_LLM_*` + `REDIS_QUEUE_RETRY_AFTER=660` |
| مدل | `gemini-flash-lite-latest` (پایدارتر از flash-lite قدیمی) |
| URL پروداکشن | Worker `*.workers.dev` — نه `host.docker.internal` |

## WebSocket (Reverb) + کش محصول / Cloudflare

قبل از دیپلوی بک‌اند/ادمین برای اعلان سبد و قیمت تازه، این راهنما را کامل کنید:

**[`WEBSOCKET_AND_CACHE.md`](WEBSOCKET_AND_CACHE.md)**

خلاصه:

| موضوع | عمل |
|--------|-----|
| Backend `.env` | `BROADCAST_*=reverb` + `REVERB_*` + اختیاری `CLOUDFLARE_*` |
| Docker | `docker-compose up -d --force-recreate websocket` |
| Nginx | `location /ws/` → `127.0.0.1:6101/` (با strip پیشوند) روی admin (و ترجیحاً apex) |
| Frontend admin | `NUXT_PUBLIC_WEBSOCKET_URL=wss://admin.daizima.com/ws` در GitHub Variables / `.env.prod` |
| Cloudflare | Cache Rules: Respect origin برای products؛ Bypass برای cart/checkout؛ توکن Purge در بک‌اند |

Cloudflare rules کامل: [`cloudflare-cache-rules.md`](cloudflare-cache-rules.md)

## ۱. Deploy

از ریشه monorepo (مثلاً `g:/business/Daizima`):

```
# فقط frontend

./deploy/deploy-from-local.sh frontend --skip-pull

# فقط backend

./deploy/deploy-from-local.sh backend --skip-pull

./deploy/deploy-from-local.sh backend

./deploy/deploy-from-local.sh backend --with-storage

# هر دو با هم

./deploy/deploy-from-local.sh all
```



# خلاصه کندی‌های روزانه (روی سرور، داخل بک‌اند):

```
cd /var/www/daizima-backend
bash scripts/summarize-perf.sh
# یا: DATE=2026-08-03 bash scripts/summarize-perf.sh
```



# کش تصاویر /storage در Cloudflare + بهینه‌سازی WebP:

راهنما: `deploy/cloudflare-cache-rules.md` (Rule: Storage media cache)

روی سرور بعد از دیپلوی backend (نیاز به GD با JPEG/WebP — Dockerfile به‌روز شده):

```
cd /var/www/daizima-backend
docker-compose exec app php artisan media:optimize-images --path=product_images
# سایر پوشه‌ها در صورت نیاز:
# docker-compose exec app php artisan media:optimize-images --path=brand_images
# docker-compose exec app php artisan media:optimize-images --path=homepage_images
```

بعد از آپدیت nginx conf: `nginx -t && systemctl reload nginx`

# اگر کد را قبلاً pull کردید:

./deploy/deploy-from-local.sh all --skip-pull

در صورت وجود ارور در هنگام دیپلوی شدن میتوانید از کدهای زیر بعد از اتصال به سرور استفاده کنید
cd /var/www/daizima-frontend
pm2 restart daizima-frontend --update-env || pm2 start .output/server/index.mjs --name daizima-frontend --cwd /var/www/daizima-frontend
pm2 save
nginx -t && systemctl reload nginx
pm2 status

# برای سینک کردن تصاویر موجود در سرور با لوکال:

```
./scripts/sync-production-storage.sh user@server.com /var/www/daizima-backend


./scripts/sync-production-storage.sh root@185.18.212.24 /var/www/daizima-backend
```



# برای سینک کردن دیتابیس لوکال با پروداکشن:

cd daizima-backend

```
echo yes | ./scripts/sync-production-db.sh root@185.18.212.24 /var/www/daizima-backend

# یا بدون نیاز به pipe:

./scripts/sync-production-db.sh -y root@185.18.212.24 /var/www/daizima-backend

# فقط دانلود دامپ (بدون سینک با دیتابیس لوکال) — فایل در DB-DUMPs ذخیره می‌شود:

./scripts/sync-production-db.sh --download-only root@185.18.212.24 /var/www/daizima-backend
```



# بکاپ دوره‌ای دامپ روی سرور جدا (ویندوز سرور / بدون Docker محلی):

روی ماشین بکاپ فقط Git Bash + کلید SSH لازم است (Docker فقط روی سرور پروداکشن است).

ساختار پیشنهادی روی سرور بکاپ:

```
parent/
  daizima-backend/   # clone
  deploy/            # clone
  DB-DUMPs/          # خودکار ساخته می‌شود کنار daizima-backend
```

```
cd daizima-backend

# یک‌بار تست دستی (بدون -o: دامپ‌ها در ../DB-DUMPs ذخیره می‌شوند):
./scripts/download-production-db-backup.sh \
  -i ~/.ssh/daizima_backup \
  --keep-days 30 \
  root@185.18.212.24 /var/www/daizima-backend
```

زمان‌بندی هر ۶ ساعت در Windows Task Scheduler:

- Program: `C:\Program Files\Git\bin\bash.exe`
- Arguments:

```
-lc "cd /d/path/to/parent/daizima-backend && ./scripts/download-production-db-backup.sh -i ~/.ssh/daizima_backup --keep-days 30 root@185.18.212.24 /var/www/daizima-backend"
```

- Trigger: Daily، و سپس Advanced → Repeat every 6 hours

فایل‌های `production-dump-*.sql[.gz]` قدیمی‌تر از `--keep-days` (پیش‌فرض ۳۰ روز) خودکار پاک می‌شوند. به‌صورت پیش‌فرض دامپ فشرده (`.gz`) نگه داشته می‌شود.

# برای دسترسی به دیتابیس روی لوکال:

cd daizima-backend

```
docker exec -it daizima-db mysql -u daizima_user -pdaizima_password daizima
```



## API ترب

راهنمای production و رفع خطا: `daizima-backend/docs/Torob/PRODUCTION_TROUBLESHOOTING.md`

For Deploying BackEnd:

cd /var/www/daizima-backend
chmod +x update.sh
./update.sh

instead of these command you can use: (daizima update backend)

```
dub
```

For Deploying FrontEnd:

cd /var/www/daizima-frontend/
chmod +x update.sh
./update.sh

instead of these command you can use: (daizima update frontend)

```
duf
```

Test Sending SMS

```
docker-compose exec app php artisan kavenegar:test --send --phone=09194391758
```

---

## Map POI Collector (OpenStreetMap → SQLite)

پروژه: `map-poi-collector/`  
جمع‌آوری کسب‌وکارهای ثبت‌شده در OSM به‌صورت شهر به شهر، بدون API key و بدون scrape مرورگر.  
جزئیات بیشتر: [`map-poi-collector/README.md`](../map-poi-collector/README.md)

### نصب

```
cd map-poi-collector
npm install
```

نیاز: Node.js 20+

دیتابیس پیش‌فرض: `map-poi-collector/data/places.db`  
تغییر مسیر DB در همهٔ دستورها: `--db ./path/to/places.db`

### لیست شهرهای ایران از OSM

```
# دانلود city + town + municipality → جدول city_catalog
npm run fetch-iran-cities

# همان + خروجی CSV
npm run fetch-iran-cities -- --export-csv data/iran-cities.csv

# شامل روستاها (حجم خیلی بیشتر)
npm run fetch-iran-cities -- --include-villages

# مشاهده کاتالوگ
npm run list-iran-cities
npm run list-iran-cities -- --place-type city --limit 50
```

### جمع‌آوری کسب‌وکارها (شهر به شهر)

```
# یک شهر (EN یا FA)
npm run collect -- --city Shahrood
npm run collect -- --city شاهرود
npm run collect -- --city تهران

# چند شهر مشخص
npx tsx src/cli.ts collect-many --cities "Shahrood,Isfahan"

# موازی (۲–۳ پیشنهاد می‌شود؛ Overpass عمومی تحمل بار بالا ندارد)
npx tsx src/cli.ts collect-many --cities "Shahrood,Isfahan,Shiraz" --concurrency 3 --delay-ms 1500
npx tsx src/cli.ts collect-many --from-catalog --place-type city --concurrency 2 --delay-ms 2000

# همهٔ presetهای داخلی (شاهرود، تهران، مشهد، اصفهان، شیراز، تبریز)
npx tsx src/cli.ts collect-many

# همهٔ cityهای کاتالوگ OSM (طولانی؛ فاصله بین شهرها)
npx tsx src/cli.ts collect-many --from-catalog --place-type city --delay-ms 8000

# فقط townها از کاتالوگ
npx tsx src/cli.ts collect-many --from-catalog --place-type town --delay-ms 8000
```

`--concurrency N`: چند شهر هم‌زمان.  
`--delay-ms`: فاصلهٔ شروع slotها تا stampede روی یک mirror نشود.

### وضعیت / لیست‌ها / آمار

```
# شهرهایی که جمع‌آوری شده‌اند (با تعداد places)
npm run list-cities

# presetهای داخلی با bbox
npx tsx src/cli.ts list-presets

# آمار کلی (cities / places / phone / hours / address / catalog)
npm run stats
```

### جداول مهم SQLite

| جدول | نقش |
|------|-----|
| `city_catalog` | لیست شهر/town ایران از OSM |
| `cities` | شهرهایی که برایشان collect زده شده + bbox |
| `places` | کسب‌وکارها (نام، تلفن، آدرس، ساعت، lat/lng، …) |
| `collect_runs` | تاریخچهٔ هر اجرا |

نمونه کوئری:

```
SELECT name, phone, address, opening_hours, category, subcategory
FROM places
WHERE city_id = 1 AND phone IS NOT NULL
LIMIT 50;
```

