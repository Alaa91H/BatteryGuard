# بيئة WSL2 / Linux جاهزة للتجارب والإنتاج

حزمة تثبيت وتجهيز كاملة لبيئة WSL2 على ويندوز: تُثبّت التوزيعة، تضبط النواة والموارد،
تُجهّز سلاسل الأدوات (Node / Python / Go / Rust)، تُشغّل Docker الأصلي داخل WSL بدون
Docker Desktop، وتضيف طبقة إنتاجية (تحديثات أمنية تلقائية، systemd، سجلات محدودة،
مؤقّت فحص صحي، SSH اختياري) — كل ذلك بأوامر قابلة لإعادة التشغيل.

---

## المتطلبات

| البند | الحد الأدنى |
|---|---|
| ويندوز | 10 إصدار 2004 (بناء 19041) أو أحدث / ويندوز 11 |
| المعالج | محاكاة افتراضية مفعّلة في BIOS/UEFI (VT-x / AMD-V) |
| الصلاحيات | جلسة PowerShell **بصلاحيات مسؤول** لمرحلة التثبيت فقط |
| الذاكرة | 8 GB (يُضبط WSL على 8 GB و6 أنوية في `.wslconfig`) |
| الشبكة | اتصال بالإنترنت أثناء التثبيت |

---

## البدء السريع

```powershell
# 1) التثبيت (يحتاج مسؤول) - ثم أعد تشغيل ويندوز
powershell -ExecutionPolicy Bypass -File .\windows\Install-Wsl2.ps1

# 2) بعد إعادة التشغيل (يحتاج مسؤول أيضاً)
powershell -ExecutionPolicy Bypass -File .\windows\Install-Wsl2.ps1 -Resume

# 3) التجهيز الكامل داخل لينكس (لا يحتاج مسؤول)
powershell -ExecutionPolicy Bypass -File .\windows\Provision-Wsl.ps1 -Profile dev

# 4) خادم Git محلي خاص (اختياري)
powershell -ExecutionPolicy Bypass -File .\windows\Provision-Wsl.ps1 -Profile dev -WithForge
```

ثم:

```powershell
wsl -d Ubuntu-24.04
```

لبيئة إنتاجية مع SSH وتحديثات تلقائية:

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\Provision-Wsl.ps1 -Profile prod -WithSsh -Upgrade
```

> المرحلة 3 تُشغّل السكربت مرتين: مرة لكتابة `/etc/wsl.conf`، ثم بعد إعادة تشغيل
> التوزيعة لتصبح `systemd` هي العملية رقم 1 وتُفعّل الخدمات فعلياً.

---

## ما الذي يحدث بالتفصيل

### المرحلة 1 — ويندوز

1. التحقق من بناء ويندوز وصلاحيات المسؤول.
2. تفعيل `Microsoft-Windows-Subsystem-Linux` و`VirtualMachinePlatform` عبر DISM.
3. تعيين `DefaultVersion=2` في سجل WSL.
4. تحديث حزمة WSL من Microsoft (`wsl --update --web-download`).
5. نسخ `.wslconfig` إلى `%UserProfile%\.wslconfig` (لا يستبدل ملفاً موجوداً إلا مع `-Force`).
6. طلب إعادة التشغيل عند الحاجة (رمز الخروج `3`).

### المرحلة 2 — بعد إعادة التشغيل

1. تثبيت `Ubuntu-24.04` عبر `wsl --install --no-launch --web-download` (بدون إنشاء مستخدم تفاعلي).
2. تثبيت التوزيعة على WSL2 وتفعيل VHD المتنامي (sparse) إن كان مدعوماً.

### المرحلة 3 — داخل لينكس (`linux/bootstrap.sh`)

| الطبقة | المحتوى |
|---|---|
| النظام | `build-essential`, `cmake`, `git` + `git-lfs`, `jq`, `ripgrep`, `fd`, `fzf`, `tmux`, `htop`, `btop`, `strace`, `sysstat` |
| الهوية | مستخدم `dev`، `sudo` بدون كلمة مرور (قابل للتعطيل)، لغات `en_US.UTF-8` + `ar_SA.UTF-8` |
| النواة | `systemd=true`, inotify 524288, `vm.max_map_count`, `somaxconn`, حدود الملفات المفتوحة |
| الشبكة | `dnsTunneling`, إبقاء `generateResolvConf` |
| Node | Node.js LTS من NodeSource + `corepack` + `pnpm` |
| Python | `python3` + `venv` + `pipx` + `uv` + CPython 3.12 مُدار |
| Go | أحدث إصدار مستقر من `go.dev` إلى `/usr/local/go` |
| Rust | اختياري (`-WithRust`) عبر rustup |
| Docker | `docker-ce` + `buildkit` + `compose` + تدوير السجلات + إضافة المستخدم لمجموعة `docker` |
| الإنتاج | `unattended-upgrades`, سقف journald 500MB, `systemd-timesyncd`, مؤقّت فحص كل 6 ساعات, SSH على المنفذ 2222 |
| اختياري | حزمة PostgreSQL 16 + Redis 7 + Adminer في `/opt/wsl-stack`، وNVIDIA Container Toolkit |
| Git محلي | **Forgejo** (`-WithForge`) على `http://localhost:3000` — بيانات في `/opt/wsl-forgejo` |

---

## المسارات المهمة

| المسار | الوظيفة |
|---|---|
| `/opt/wsl-provision` | نسخة السكربتات داخل التوزيعة (المصدر هو `linux/`) |
| `/usr/local/bin/wsl-verify` | أداة الفحص الصحي |
| `/etc/wsl.conf` | ضبط WSL داخل التوزيعة |
| `/etc/sysctl.d/99-wsl-sysctl.conf` | ضبط النواة |
| `/etc/systemd/system/wsl-healthcheck.*` | المؤقّت الصحي |
| `/opt/wsl-stack` | حزمة Docker الاختيارية + `.env` بصلاحيات `600` |
| `/opt/wsl-forgejo` | خادم Git المحلي: `compose.yaml` + `data/` + `.env` بصلاحيات `600` |
| `%UserProfile%\.wslconfig` | ضبط الموارد من جهة ويندوز |
| `exports/` | نسخ التوزيعة الاحتياطية |

---

## ملفات التعريف (Profiles)

| | `dev` | `prod` | `full` |
|---|---|---|---|
| الأساس + shell + ضبط النواة | ✅ | ✅ | ✅ |
| Node / Python / pnpm / uv | ✅ | ✅ | ✅ |
| Go / Rust | ✅ | ❌ | ✅ |
| Docker Engine | ✅ | ✅ | ✅ |
| تحديثات أمنية تلقائية + NTP + سقف السجلات | ❌ | ✅ | ✅ |
| مؤقّت الفحص الصحي | ✅ | ✅ | ✅ |
| SSH (عند `-WithSsh`) | ❌ | ✅ | ✅ |

---

## الخيارات

```powershell
# بيئة تطوير مع zsh وRust وقواعد بيانات تعمل فوراً
.\windows\Provision-Wsl.ps1 -Profile dev -WithZsh -WithRust -StartDatabases

# خادم Git محلي (Forgejo) على localhost:3000
.\windows\Provision-Wsl.ps1 -Profile dev -WithForge

# إنتاج مع SSH وترقية كاملة للحزم
.\windows\Provision-Wsl.ps1 -Profile prod -WithSsh -Upgrade

# بدون Docker (بيئة نظيفة للأدوات فقط)
.\windows\Provision-Wsl.ps1 -Profile dev -NoDocker

# توزيعة أو مستخدم أو منطقة زمنية مختلفة
.\windows\Provision-Wsl.ps1 -Distro Ubuntu-22.04 -User alahu -Timezone Asia/Riyadh
```

كل الخيارات متاحة أيضاً مباشرة داخل لينكس:

```bash
sudo bash /opt/wsl-provision/bootstrap.sh --help
```

---

## التحقق والصحة

```powershell
wsl -d Ubuntu-24.04 -u dev -- wsl-verify
```

يفحص: نواة WSL، systemd، ضبط `/etc/wsl.conf`، صلاحيات `sudo`، عضوية `docker`،
وجود كل أداة، إصدارات Node/Python/Go، استجابة Docker، ترميز UTF-8، حدود inotify،
DNS، HTTPS، المساحة الحرة، المؤقّت الصحي، وحاوية Forgejo عند تثبيتها. يعيد `1` عند أي فشل.

سجل المؤقّت:

```bash
journalctl -u wsl-healthcheck --no-pager
```

---

## الاستخدام اليومي

```bash
# الدخول
wsl -d Ubuntu-24.04

# Docker بدون sudo (بعد إعادة الدخول أو newgrp docker)
docker run --rm hello-world
docker compose version

# Node
node -v && pnpm -v

# Python
uv python list
uv venv .venv && source .venv/bin/activate

# Go
go version

# قواعد البيانات
cd /opt/wsl-stack && docker compose up -d
# postgres: 127.0.0.1:5432 | redis: 127.0.0.1:6379
# adminer (اختياري): docker compose --profile tools up -d → http://127.0.0.1:8080
```

> ضع المشاريع في نظام ملفات لينكس (`~/src`) لا في `/mnt/c` — أداء I/O يختلف بفارق كبير.

---

## خادم Git محلي (Forgejo)

خادم Git خاص بك، يعمل داخل WSL2 فقط ولا يحتاج أي حساب أو خدمة خارجية:

```powershell
.\windows\Provision-Wsl.ps1 -Profile dev -WithForge
```

| البند | القيمة |
|---|---|
| الواجهة | <http://localhost:3000> |
| Git SSH | `ssh://git@localhost:2223` بعد إضافة مفتاحك من الإعدادات |
| المدير | `FORGEJO_ADMIN_USER` (الافتراضي `forge`) و`FORGEJO_ADMIN_PASSWORD` في `/opt/wsl-forgejo/.env` |
| البيانات | `/opt/wsl-forgejo/data` (SQLite + المستودعات + السجلات) |
| التحكم | `cd /opt/wsl-forgejo && docker compose stop\|start\|logs -f` |

يُنشأ مستودع تجريبي خاص باسم `hello` تلقائياً للتحقق من الدفع عبر HTTP. لإنشاء مستودع حقيقي:

```bash
cd ~/src && mkdir demo && cd demo && git init -b main
git remote add origin http://localhost:3000/forge/demo.git
git add . && git commit -m "first commit" && git push -u origin main
```

الخادم مربوط بـ `127.0.0.1` عمداً: لا يمكن الوصول إليه من الشبكة أو من أجهزة أخرى.
وبما أنه داخل WSL، فهو يعمل فقط عندما تكون التوزيعة قيد التشغيل؛ Docker يعيد تشغيل
الحاوية تلقائياً عند إقلاع WSL. هذا يجعل البيانات محلية بالكامل، لكنه ليس نسخة
احتياطية — استخدم `Export-Wsl.ps1` دورياً.

> كلمة مرور المدير محفوظة بصلاحيات `600` في `/opt/wsl-forgejo/.env` (اقرأها بـ`sudo cat`).
> إعادة التجهيز تعيد ضبطها إلى قيمة `.env` إن تغيّرت من الواجهة.

---

## النسخ الاحتياطي والاستعادة

```powershell
# نسخة كاملة (توقف التوزيعة لضمان تماسك الحالة)
powershell -ExecutionPolicy Bypass -File .\windows\Export-Wsl.ps1 -StopFirst

# تصدير صورة القرص فقط (أسرع، أكبر)
powershell -ExecutionPolicy Bypass -File .\windows\Export-Wsl.ps1 -Vhd -StopFirst

# استعادة
wsl --import Ubuntu-restored $env:USERPROFILE\WSL\Ubuntu-restored .\exports\Ubuntu-24.04-<ts>.tar --version 2
wsl --set-default Ubuntu-restored
```

التصدير يشمل الحزم، `/home`، إعدادات systemd، وبيانات Docker volumes.

---

## التخصيص

| ما تريد تغييره | المكان |
|---|---|
| ذاكرة/أنوية/swap WSL | `.wslconfig` ثم `wsl --shutdown` |
| اللغة والمنطقة الزمنية | أعلام `-Locale` / `-Timezone` |
| إصدار Node | سكربت NodeSource LTS، عدّل `linux/modules/toolchains.sh` |
| إصدار Go | يُقرأ من `go.dev/dl/?mode=json` (أحدث مستقر) |
| حزم إضافية | أضفها إلى `packages` في `linux/modules/base.sh` |
| منافذ قواعد البيانات | `linux/docker/compose.yaml` |
| إصدار Forgejo | أضف `FORGEJO_IMAGE=codeberg.org/forgejo/forgejo:<tag>` إلى `/opt/wsl-forgejo/.env` ثم `docker compose up -d` |
| منفذ SSH | `install_ssh` في `linux/modules/prod.sh` (الافتراضي 2222) |

بعد أي تعديل على `linux/` أعد التشغيل:

```powershell
.\windows\Provision-Wsl.ps1 -Profile dev
```

---

## استكشاف الأخطاء

| العرض | السبب | الحل |
|---|---|---|
| `WslRegisterDistribution failed with error: 0x80370102` | المحاكاة الافتراضية معطّلة | فعّل VT-x/AMD-V في BIOS، وتأكد أن `VirtualMachinePlatform` مفعّل ثم أعد التشغيل |
| `0x8007019e` | ميزة WSL غير مفعّلة | `Install-Wsl2.ps1` ثم إعادة تشغيل ويندوز |
| `System has not been booted with systemd` | `systemd` لم تُفعّل بعد | تأكد من `systemd=true` في `/etc/wsl.conf` ثم `wsl --shutdown` |
| `permission denied` على Docker | المستخدم ليس في مجموعة `docker` بعد | `newgrp docker` أو أغلق الجلسة وافتحها |
| فشل DNS | VPN أو resolver ويندوز | `dnsTunneling=true` في `.wslconfig` ثم `wsl --shutdown` |
| انحراف الساعة | السبات/الاستئناف | `sudo hwclock -s` أو `sudo systemctl restart systemd-timesyncd` |
| القرص لا يصغر بعد حذف ملفات | VHD لا يتقلّص تلقائياً | `wsl --manage Ubuntu-24.04 --set-sparse true` أو ضغطه عبر diskpart |
| بناء بطيء | المشروع على `/mnt/c` | انقله إلى `~/src` |
| استهلاك ذاكرة مرتفع | page cache | `autoMemoryReclaim=gradual` + `wsl --shutdown` |
| المنفذ 3000 مشغول | خدمة أخرى تستخدمه | عدّل منفذ المنصة في `/opt/wsl-forgejo/compose.yaml` ثم `docker compose up -d` |

سجلات مفيدة:

```bash
journalctl -xe
journalctl -u docker -n 100
sudo tail -50 /var/log/wsl-verify.log
```

---

## الأمان

- حساب لينكس بكلمة مرور مقفلة + `sudo` بدون كلمة مرور **داخل WSL المحلي فقط**. استخدم
  `-SecureSudo` إن كان الجهاز مشتركاً، ثم `sudo passwd dev`.
- SSH معطّل افتراضياً؛ عند تفعيله يستخدم المنفذ 2222، `PermitRootLogin no`، ومصادقة
  بالمفاتيح تلقائياً عند وجود `~/.ssh/authorized_keys`.
- Docker يمنح صلاحيات جذر فعلياً؛ لا تضف مستخدمين غير موثوقين إلى مجموعة `docker`.
- Forgejo مربوط بـ `127.0.0.1` فقط، والتسجيل معطّل، ولا يرى الزوار غير المسجلين أي مستودع.
- لا تضع أسراراً في `.wslconfig` أو ملفات المستودع؛ استخدم `.env` (مستثنى في `.gitignore`).
- نسخ ويندوز الاحتياطية غير مشفّرة افتراضياً؛ احفظ `exports/` في مكان موثوق.

---

## الصيانة

```bash
# تحديث النظام
sudo apt update && sudo apt upgrade -y

# تنظيف
sudo apt autoremove --purge -y && docker system prune -f

# فحص
wsl-verify

# إعادة تشغيل WSL من ويندوز (بعد تغيير .wslconfig)
wsl --shutdown
```

للتفاصيل التشغيلية الكاملة راجع [`docs/production.md`](docs/production.md).
