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
# فقط frontend
./deploy/deploy-from-local.sh frontend
# فقط backend
./deploy/deploy-from-local.sh backend
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