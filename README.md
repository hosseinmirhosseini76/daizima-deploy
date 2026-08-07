# Daizima Deploy

## بعد DEPLOY_PASSWORD را از deploy.local.env خالی کنید

۲. Deploy

cd d:/bussiness-work/daizima

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


./scripts/sync-production-storage.sh root@212.23.201.113:15726 /var/www/daizima-backend
```



# برای سینک کردن دیتابیس لوکال با پروداکشن:

cd daizima-backend

```
echo yes | ./scripts/sync-production-db.sh root@212.23.201.113:15726 /var/www/daizima-backend

# یا بدون نیاز به pipe:

./scripts/sync-production-db.sh -y root@212.23.201.113:15726 /var/www/daizima-backend

# فقط دانلود دامپ (بدون سینک با دیتابیس لوکال) — فایل در DB-DUMPs ذخیره می‌شود:

./scripts/sync-production-db.sh --download-only root@212.23.201.113:15726 /var/www/daizima-backend
```



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

