# daizima-deploy

۱. نصب sshpass (یک‌بار — برای اتوماتیک شدن SSH)
روی Windows با Git Bash:

# اگر choco دارید:
choco install sshpass
# یا SSH key بسازید (بهتر و امن‌تر):
ssh-keygen -t ed25519
ssh-copy-id -p 15726 root@212.23.201.113
# بعد DEPLOY_PASSWORD را از deploy.local.env خالی کنید

۲. Deploy

cd d:/bussiness-work/daizima
```
# فقط frontend

./deploy/deploy-from-local.sh frontend

# فقط backend

./deploy/deploy-from-local.sh backend

# هر دو با هم

./deploy/deploy-from-local.sh all
```
# هر دو
./deploy/deploy-from-local.sh all
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
```

# برای دسترسی به دیتابیس روی لوکال:
cd daizima-backend
```
docker exec -it daizima-db mysql -u daizima_user -pdaizima_password daizima
```

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