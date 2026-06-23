# ورژن‌گذاری انتشار اپ — دایزیما (Daizima)

این سند فقط **ورژن انتشار اپ** (Release / SemVer) را پوشش می‌دهد، نه ورژن API (`/api/v1`).

اسکریپت‌ها وضعیت git و تاریخچه commitها را بررسی می‌کنند، سطح bump را پیشنهاد می‌دهند، فایل‌های ورژن را به‌روز می‌کنند و در صورت نیاز تگ `vX.Y.Z` می‌سازند.

---

## ساختار پوشه

```
deploy/versioning/
├── doc.md              ← همین راهنما
├── lib.sh              ← منطق مشترک (SemVer + تحلیل git)
├── bump-backend.sh     ← بک‌اند (Laravel)
└── bump-frontend.sh    ← فرانت‌اند (Nuxt)
```

هر اپ (`daizima-backend` و `daizima-frontend`) **ریپوی git جدا** دارد؛ تگ‌ها مستقل هستند (مثلاً هر دو `v1.2.0` ولی در ریپوی خودشان).

---

## پیش‌نیاز

- Bash (Git Bash / Linux / macOS)
- `git` در PATH
- یکی از `php` یا `node` برای به‌روزرسانی `composer.json` / `package.json`
- اجرا از **ریشه monorepo** (`daizima/`) یا هر مسیر — اسکریپت مسیر اپ را خودش پیدا می‌کند

```bash
chmod +x deploy/versioning/*.sh   # فقط بار اول
```

---

## نحوه استفاده

### پیش‌نمایش (بدون تغییر فایل)

```bash
./deploy/versioning/bump-backend.sh --dry-run
./deploy/versioning/bump-frontend.sh --dry-run
```

با `--dry-run` حتی اگر working tree کثیف باشد، تحلیل انجام می‌شود.

### اعمال ورژن + تگ git

```bash
# ابتدا تغییرات را commit کنید (درخت کاری تمیز)
git add -A && git commit -m "feat: ..."

./deploy/versioning/bump-backend.sh
./deploy/versioning/bump-frontend.sh
```

پس از اجرا، در صورت تایید، فایل‌های ورژن به‌روز و تگ annotated `vX.Y.Z` ساخته می‌شود.

### گزینه‌های پرکاربرد

| گزینه | کاربرد |
|--------|--------|
| `--dry-run` | فقط گزارش؛ بدون نوشتن فایل و بدون تگ |
| `--yes` / `-y` | بدون پرسش تأیید؛ commit خودکار فایل‌های ورژن |
| `--no-commit` | همراه `--yes`: فقط bump فایل‌ها، بدون `git commit` |
| `--major` | اجبار bump نسخه اصلی |
| `--minor` | اجبار bump نسخه فرعی |
| `--patch` | اجبار bump وصله |
| `--no-tag` | فقط به‌روزرسانی فایل‌ها؛ بدون `git tag` |
| `--allow-dirty` | اجازه bump با فایل‌های uncommitted (تگ فقط اگر درخت تمیز باشد) |
| `-h` / `--help` | راهنمای خط فرمان |

مثال‌ها:

```bash
./deploy/versioning/bump-backend.sh --no-tag --yes
./deploy/versioning/bump-frontend.sh --no-tag --yes

با `--yes` فایل‌های ورژن بعد از bump **خودکار commit** می‌شوند (`chore(backend|frontend): release vX.Y.Z`).
برای غیرفعال کردن commit خودکار: `--yes --no-commit`.

./deploy/versioning/bump-backend.sh --minor --yes
./deploy/versioning/bump-frontend.sh --patch --no-tag --allow-dirty
```

---

## منطق تعیین ورژن (خودکار)

فرمت: **[Semantic Versioning](https://semver.org/)** — `MAJOR.MINOR.PATCH`

تحلیل از **آخرین تگ `v*`** تا `HEAD` (اگر تگی نباشد، کل تاریخچه شاخه).

| سطح | چه زمانی پیشنهاد می‌شود |
|-----|-------------------------|
| **MAJOR** | `BREAKING CHANGE` یا `BREAKING:` در commit؛ نوع با `!` مثل `feat!:`؛ migration با `dropTable` / `dropColumn` / … |
| **MINOR** | commit با `feat:`؛ migration جدید؛ کنترلر/سرویس یا صفحه جدید؛ بیش از **۲۰ فایل** تغییر کرده؛ حجم زیاد commit (۸+ عدد) |
| **PATCH** | `fix:`، `hotfix:`، `perf:`، `refactor:`، `docs:`، `chore:` و تغییرات کوچک؛ یا هر تغییر باقی‌مانده |
| **بدون bump** | از آخرین تگ تغییری نباشد و working tree هم تمیز باشد |

برای commitهای خوانا از [Conventional Commits](https://www.conventionalcommits.org/) استفاده کنید تا پیشنهاد دقیق‌تر باشد.

---

## فایل‌های به‌روزشونده

### Backend (`daizima-backend`)

| فایل | نقش |
|------|-----|
| `VERSION` | منبع ساده یک‌خطی (مثلاً `0.0.4`) |
| `composer.json` → `version` | هماهنگ با SemVer |
| `.env.example` → `APP_VERSION` | نمونه env |
| `config/app.php` → `version` | `config('app.version')` در runtime |

### Frontend (`daizima-frontend`)

| فایل | نقش |
|------|-----|
| `VERSION` | منبع ساده یک‌خطی |
| `package.json` → `version` | هماهنگ با SemVer |
| `.env.example` → `NUXT_PUBLIC_APP_VERSION` | نمونه env |
| `nuxt.config.ts` → `runtimeConfig.public.appVersion` | در build و کلاینت |

> روی سرور production مقدار `APP_VERSION` / `NUXT_PUBLIC_APP_VERSION` را در `.env` واقعی ست کنید (اسکریپت `.env` محلی را عمداً دست نمی‌زند).

---

## جریان پیشنهادی قبل از deploy

```bash
# ۱. commit تغییرات در هر ریپو
cd daizima-backend && git add -A && git commit -m "feat: ..."
cd ../daizima-frontend && git add -A && git commit -m "feat: ..."

# ۲. bump ورژن (از ریشه monorepo)
cd ..
./deploy/versioning/bump-backend.sh --yes
./deploy/versioning/bump-frontend.sh --yes

# ۳. push (اگر با --yes اجرا کردید، commit ورژن خودکار انجام شده)
cd daizima-backend && git push
cd ../daizima-frontend && git push
./deploy/deploy-from-local.sh all
```

اگر اسکریپت با درخت تمیز اجرا شود، فایل‌های ورژن و تگ در یک مرحله اعمال می‌شوند؛ سپس فقط `git push && git push --tags` کافی است.

---

## نکات مهم

1. **تگ git** فقط وقتی ساخته می‌شود که working tree **تمیز** باشد؛ با `--allow-dirty` می‌توانید ورژن فایل‌ها را عوض کنید و بعداً خودتان commit + tag بزنید.
2. **Backend و Frontend** ورژن مستقل دارند؛ لزومی ندارد عددشان همیشه یکی باشد.
3. **`--dry-run`** برای بررسی قبل از release عالی است؛ خروجی سطح bump و نسخه بعدی را نشان می‌دهد.
4. این سیستم **جایگزین ورژن API** نیست؛ مسیرهای `/api/v1` تغییری نمی‌کنند.

---

## عیب‌یابی

| مشکل | راه‌حل |
|------|--------|
| `Working tree is dirty` | commit کنید یا `--allow-dirty` / `--dry-run` |
| `Tag vX.Y.Z already exists` | ورژه بالاتر بزنید یا تگ قدیمی را حذف/تغییر نام دهید |
| `Need php or node` | یکی از آن‌ها را نصب کنید |
| `Not a git repository` | از داخل `daizima-backend` یا `daizima-frontend` که `.git` دارد اطمینان حاصل کنید |
| پیشنهاد همیشه `patch` است | commit messageها را با `feat:` / `fix:` بنویسید |

---

## مرتبط

- دیپلوی: [`../deploy-from-local.sh`](../deploy-from-local.sh)
- پرداخت ملت: [`../../daizima-backend/docs/mellat-payment-deployment.md`](../../daizima-backend/docs/mellat-payment-deployment.md)

**دایزیما (Daizima)** · https://daizima.com/
