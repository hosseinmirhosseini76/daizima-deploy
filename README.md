# Daizima Deploy

## Immediate Commands
```
./scripts/sync-production-storage.sh root@185.18.212.24 /var/www/daizima-backend
./scripts/sync-production-db.sh -y root@185.18.212.24 /var/www/daizima-backend
./scripts/sync-production-db.sh --download-only root@185.18.212.24 /var/www/daizima-backend
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
docker compose exec app php artisan media:optimize-images --path=product_images
# سایر پوشه‌ها در صورت نیاز:
# docker compose exec app php artisan media:optimize-images --path=brand_images
# docker compose exec app php artisan media:optimize-images --path=homepage_images
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

