# دليل التشغيل الإنتاجي (WSL2)

هذا الملف يغطي ما بعد التجهيز: كيف تُدار البيئة كخادم تطوير/تشغيل موثوق على جهاز
واحد، وما هي نقاط الفشل المعروفة في WSL2 وكيف تُعالج.

---

## 1. نموذج التشغيل

| الطبقة | المسؤول | ملاحظات |
|---|---|---|
| ويندوز | المستخدم | تحديثات ويندوز، تشغيل/إيقاف WSL، النسخ الاحتياطي |
| WSL2 (VM خفيفة) | `%UserProfile%\.wslconfig` | ذاكرة، أنوية، swap، شبكة |
| التوزيعة | `systemd` + `bootstrap.sh` | خدمات، مؤقّتات، سجلات |
| التطبيقات | Docker Compose أو systemd units | تُدار من داخل التوزيعة |

نقطة مهمة: WSL2 ليست خادماً دائماً. عند إغلاق ويندوز أو `wsl --shutdown` تتوقف كل
الخدمات. للإنتاج الحقيقي على مدار الساعة استخدم خادماً حقيقياً؛ استخدم هذه البيئة
كـ staging أو بيئة تطوير مطابقة.

---

## 2. الخدمات المُدارة

```bash
systemctl status docker
systemctl status systemd-timesyncd
systemctl list-timers --all | grep -E 'wsl-healthcheck|apt-daily'
systemctl status ssh          # عند -WithSsh
```

| الوحدة | الوظيفة | التفعيل |
|---|---|---|
| `docker.service` | محرّك الحاويات | تلقائي |
| `systemd-timesyncd` | مزامنة الوقت | تلقائي (prod) |
| `unattended-upgrades` | تحديثات أمنية | تلقائي (prod) |
| `wsl-healthcheck.timer` | فحص كل 6 ساعات | تلقائي |
| `ssh.service` | وصول عن بعد | `-WithSsh` |
| `fail2ban` | حماية SSH | غير مفعّل افتراضياً |

---

## 3. التحديثات

- **تلقائي (prod):** `unattended-upgrades` يثبّت تحديثات الأمان فقط، دون إعادة تشغيل.
- **يدوي:** `sudo apt update && sudo apt upgrade -y` ثم `wsl-verify`.
- **Docker:** `docker compose pull && docker compose up -d` لكل حزمة.
- **WSL نفسه:** من ويندوز `wsl --update`؛ راجع الإصدار بـ `wsl --version`.
- بعد ترقية النواة أو إعدادات `.wslconfig`: `wsl --shutdown` ثم أعد الدخول.

---

## 4. النسخ الاحتياطي

### 4.1 نسخة كاملة (موصى بها قبل أي تغيير كبير)

```powershell
.\windows\Export-Wsl.ps1 -StopFirst
```

- الناتج: `exports\Ubuntu-24.04-<timestamp>.tar`
- يتضمن: الحزم، `/home`، `/etc`، Docker volumes.
- الاستعادة: `wsl --import` (القيادة مطبوعة في نهاية السكربت).

### 4.2 نسخة البيانات فقط

```bash
# قواعد البيانات
docker exec $(docker ps -qf name=postgres) pg_dump -U app app > ~/backups/app.sql
# الأسرار
cp /opt/wsl-stack/.env ~/backups/stack.env
```

### 4.3 الجدولة

لا يوجد جدولة تلقائية للتصدير (لأنه يتطلب إيقاف التوزيعة). أنشئ مهمة في Task Scheduler:

```
wsl --terminate Ubuntu-24.04
wsl --export Ubuntu-24.04 D:\backups\wsl-YYYYMMDD.tar
```

---

## 5. الأمان

| الإجراء | الأمر |
|---|---|
| التحقق من المنافذ المفتوحة | `ss -tulpn` |
| سجل نجاح/فشل SSH | `journalctl -u ssh -n 100` |
| تقييد SSH بالمفاتيح | ضع المفتاح في `~/.ssh/authorized_keys` وأعد التجهيز |
| كلمة مرور للمستخدم | `sudo passwd dev` ثم أعد التجهيز بـ `-SecureSudo` |
| تدقيق صلاحيات sudo | `sudo -l -U dev` |
| تحديث الحاويات | `docker compose pull` (لا تستخدم `:latest` في الإنتاج) |

ملاحظات:
- WSL2 خلف NAT افتراضياً؛ المنافذ غير مكشوفة على الشبكة المحلية. `networkingMode=mirrored`
  يغيّر ذلك — لا تفعّله إلا بقصد.
- Docker = صلاحيات جذر. لا تُضف مستخدمين غير موثوقين إلى مجموعة `docker`.
- الملفات في `/mnt/c` تخضع لصلاحيات ويندوز وقد تفقد `chmod`؛ احتفظ بالأسرار في ext4.

---

## 6. المراقبة

```bash
wsl-verify                      # فحص شامل فوري
journalctl -u wsl-healthcheck   # نتائج المؤقّت
tail -f /var/log/wsl-verify.log # سجل تاريخي مختصر
docker stats --no-stream        # استهلاك الحاويات
free -h && df -h /             # الموارد
systemd-analyze blame | head   # بطء الإقلاع
```

من ويندوز:

```powershell
wsl --status
wsl --list --verbose
Get-Process vmmem | Select-Object CPU, WorkingSet64
```

---

## 7. التعافي من الأعطال

| الحالة | الإجراء |
|---|---|
| التوزيعة لا تُقلع | `wsl --shutdown` ثم `wsl -d Ubuntu-24.04 -u root -- bash` |
| `systemd` لا يعمل | تحقق من `/etc/wsl.conf` ثم أعد التشغيل |
| Docker لا يبدأ | `journalctl -u docker -n 200`؛ افحص `/etc/docker/daemon.json` |
| القرص ممتلئ | `docker system prune -a --volumes` بعد نسخة احتياطية، ثم ضغط VHD |
| فساد نظام الملفات | صدّر ما تستطيع، ثم `wsl --unregister` واستورد نسخة سليمة |
| فقدان كلمة مرور المستخدم | `wsl -u root passwd dev` |

أوامر إنقاذ:

```powershell
wsl --shutdown
wsl --list --verbose
wsl --export Ubuntu-24.04 D:\rescue.tar
wsl --unregister Ubuntu-24.04
wsl --import Ubuntu-24.04 C:\WSL\Ubuntu-24.04 D:\rescue.tar --version 2
```

---

## 8. قائمة تحقق قبل الاعتماد على البيئة

- [ ] `wsl -v` يعرض WSL 2.x
- [ ] `wsl-verify` يعيد 0 بدون فشل
- [ ] `systemctl is-system-running` يعيد `running` أو `degraded` مع سبب معروف
- [ ] `docker run --rm hello-world` ينجح بدون sudo
- [ ] نسخة احتياطية حديثة موجودة في `exports/` ومخزّنة خارج الجهاز
- [ ] `.env` و`authorized_keys` بصلاحيات صحيحة (`600` / `700`)
- [ ] `unattended-upgrades` مفعّل في `prod`
- [ ] منفذ SSH غير مكشوف خارجياً، أو محمي بمفاتيح فقط
