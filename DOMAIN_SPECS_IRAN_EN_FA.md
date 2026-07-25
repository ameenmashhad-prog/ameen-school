# مواصفات الدومين والاستضافة لـ 600 طالب — نسخة للبحث (إنجليزي + فارسي)
# Domain & Hosting Specs for 600 Students — Search Version (English + Persian)

---

## PART 1: ENGLISH — For International Search (Namecheap, Cloudflare, Vercel, Supabase)

### Domain Specs to Search:
```
IRANIAN DOMAIN .ir - 1 Year - Requirements:
- TLD: .ir (Iran) or .co.ir or .ac.ir
- Registrar: nic.ir official or reseller with full DNS management
- Features: WHOIS privacy, Registrar Lock, Auto-renew, Free DNS management, Ability to set custom nameservers (Cloudflare / ArvanCloud)
- DNS: Must allow setting NS to cloudflare.com or arvancloud.ir
- Price: ~ 12,000,000 IRR per year for .ir
- ID Required: Iranian National ID or Company registration for .ir

Search Keywords:
"buy .ir domain 1 year cheap"
"ir domain with cloudflare dns"
"ir domain arvancloud nameserver"
"nic.ir reseller .ir domain"
```

### Hosting Specs for 600 Students / 1 Year:
```
STATIC WEBSITE HOSTING + API + DATABASE for 600 Students:

Frontend Hosting (Replace Vercel if blocked in Iran):
- Bandwidth: 1TB per month minimum
- Storage: 50GB SSD for static files
- Uptime: 99.9% SLA
- SSL: Free Let's Encrypt auto-renew
- CDN: Iran PoP required (ArvanCloud, Cloudflare Iran, ParsPack CDN)
- Node.js Support: Node 18+ for /api/proxy serverless functions
- Framework: Static HTML + Node.js API, framework=null
- Build: No build, outputDirectory=.
- Locations: Tehran, Isfahan, or EU with good Iran peering

Database Hosting (Replace Supabase if blocked):
- Type: PostgreSQL 15+
- Size: 8GB database storage minimum
- Storage for files: 100GB S3 compatible (for student photos, documents)
- RAM: 4GB minimum
- CPU: 2 vCPU minimum
- Connections: 200 concurrent connections
- Backup: Daily automatic backup, 7 days retention
- MAU: 600 monthly active users minimum (Supabase 100k MAU on Pro)
- Extensions: pgcrypto, postgis (if needed)
- API: PostgREST or Supabase compatible API

Total Package for 600 Students:
- 600 students x 10MB per student (photo + docs) = 6GB + 2GB overhead = 8GB DB
- 600 students x 2 logins per day x 30 days = 36,000 visits/month
- 36k visits x 2MB avg page = 72GB bandwidth/month -> need 1TB to be safe

Search Keywords:
"iran vps 4GB RAM 100GB SSD 1TB bandwidth"
"iran postgres hosting 8GB"
"liara.ir postgres database"
"parspack cloud database"
"arvancloud cdn iran hosting"
"hosting for 600 users school management"
```

### Recommended International Stack (if NOT blocked):
- Domain: Cloudflare Registrar .com 15$/year
- Frontend: Vercel Pro 20$/month (1TB bandwidth)
- Database: Supabase Pro 25$/month (8GB DB, 100GB storage, daily backup)
- Total: ~555$ / year

### Recommended Iran-Friendly Stack (if blocked):
- Domain: .ir from nic.ir (120,000 IRR/year ~ 2$)
- CDN: ArvanCloud Free or Pro (Iran PoPs, bypasses filtering)
- Frontend: Liara.ir Static Hosting or ParsPack Cloud (Iran location)
- Database: Liara.ir PostgreSQL or ParsPack Database (8GB)
- Total Iran: ~ 30,000,000 - 50,000,000 IRR per year (~ 50-80$)

---

## PART 2: FARSI / فارسی — برای جستجو در سایت های ایرانی

### مشخصات دامین ایرانی برای جستجو:
```
دامنه ایرانی .ir برای یک سال:

نوع دامنه: 
- .ir (عمومی، ارزان، فقط با کارت ملی)
- .co.ir (برای شرکت ها)
- .ac.ir (برای مدارس و دانشگاه ها - نیاز به مجوز آموزش و پرورش)
- یا .school.ir (اگر موجود باشد)

ثبت کننده:
- nic.ir (سایت رسمی - ایرنیک)
- یا نماینده رسمی ایرنیک: ایران سرور، پارس پک، هاست ایران، برتینا

ویژگی های مورد نیاز:
- مدیریت کامل DNS
- قفل انتقال دامین (Registrar Lock)
- تمدید خودکار
- امکان تغییر NS به کلودفلر (cloudflare.com) یا آروان کلود (arvancloud.ir)
- حریم خصوصی WHOIS
- قیمت: دامنه .ir حدود 12,000 تومان + مالیات برای یک سال (خیلی ارزان)
- نیاز به کارت ملی و شماره تماس ایران

کلمات کلیدی برای جستجو:
"خرید دامنه ir ارزان"
"ثبت دامنه ir در ایرنیک"
"دامنه ir با دی ان اس کلودفلر"
"خرید دامنه ir با قابلیت تغییر NS"
"نماینده ایرنیک"
```

### مشخصات هاست برای 600 دانش آموز برای یک سال:
```
هاست وب سایت + دیتابیس برای 600 دانش آموز:

هاست فرانت اند (جایگزین ورسل که در ایران فیلتر است):
- پهنای باند: حداقل 1 ترابایت در ماه (1000 گیگ)
- فضا: حداقل 50 گیگابایت SSD برای فایل های سایت
- آپتایم: 99.9% تضمینی
- SSL: رایگان و خودکار (Let's Encrypt)
- CDN: حتماً POP ایران داشته باشد (آروان کلود یا پارس پک CDN)
- پشتیبانی Node.js: نسخه 18 به بالا برای API ها
- بدون نیاز به بیلد، فقط فایل های استاتیک HTML
- لوکیشن سرور: تهران یا اصفهان یا آلمان با پینگ خوب به ایران

هاست دیتابیس (جایگزین سوپابیس که در ایران کند است):
- نوع: PostgreSQL نسخه 15 یا بالاتر
- حجم دیتابیس: حداقل 8 گیگابایت
- فضای ذخیره فایل (عکس دانش آموزان): 100 گیگابایت S3
- رم: حداقل 4 گیگابایت
- سی پی یو: حداقل 2 هسته
- تعداد اتصال همزمان: 200 کانکشن
- بکاپ: روزانه خودکار، نگهداری 7 روز
- تعداد کاربر فعال ماهانه: حداقل 600 کاربر
- افزونه ها: pgcrypto

محاسبه برای 600 دانش آموز:
- هر دانش آموز: 10 مگابایت (عکس + مدارک) = 600 × 10 = 6000 مگ = 6 گیگ
- با فایل های اضافی: نیاز به 8 گیگ دیتابیس
- بازدید: هر دانش آموز روزی 2 بار × 30 روز = 36,000 بازدید در ماه
- هر بازدید 2 مگ = 72 گیگ پهنای باند → برای اطمینان 1 ترابایت

کلمات کلیدی برای جستجو:
"هاست 600 کاربره مدرسه"
"سرور مجازی ایران 4 گیگ رم 100 گیگ"
"هاست پستگرس 8 گیگ ایران"
"لیارا دیتابیس پستگرس"
"پارس پک فضای ابری"
"آروان کلود CDN ایران"
"هاست Node.js ایران"
"هاست مدرسه 600 دانش آموز"
```

### پکیج پیشنهادی ایران (ضد فیلتر):
- دامنه: .ir از nic.ir → 12,000 تومان در سال
- CDN: آروان کلود (نسخه رایگان یا حرفه ای) → POP ایران + دور زدن فیلتر
- فرانت اند: لیارا (liara.ir) هاست استاتیک یا پارس پک
- دیتابیس: لیارا دیتابیس پستگرس یا پارس پک دیتابیس 8 گیگ
- قیمت کل ایران: حدود 30 تا 50 میلیون تومان در سال (حدود 50 تا 80 دلار)

### پکیج پیشنهادی بین المللی (اگر فیلتر نباشد):
- دامنه: Cloudflare .com → 15 دلار سال
- فرانت: Vercel Pro → 20 دلار ماه
- دیتابیس: Supabase Pro → 25 دلار ماه
- کل: 555 دلار سال

---

## PART 3: WHY IRANIAN DOMAIN HELPS WITH BLOCKING?

### English:
Iranian .ir domains are managed by IRNIC inside Iran. They resolve faster inside Iran and are less likely to be blocked by Iranian filtering system compared to .com domains hosted on Vercel/Supabase (which use Cloudflare/AWS IPs that are sometimes throttled).

Solution for blocking:
1. Buy .ir domain from nic.ir
2. Use ArvanCloud CDN (Iranian company, has many PoPs in Iran, not blocked)
3. Set ArvanCloud as DNS and CDN in front of your Vercel/Supabase
4. Users in Iran will connect to ArvanCloud Tehran PoP first (fast, not blocked), then Arvan fetches from origin (Vercel/Supabase) via non-blocked route.

### فارسی:
دامنه .ir داخل ایران مدیریت می شود و DNS آن داخل ایران است. برای همین سریع تر باز می شود و کمتر فیلتر می شود نسبت به .com که روی ورسل/سوپابیس است (IP های کلودفلر و AWS گاهی در ایران کند یا فیلتر هستند).

راه حل دور زدن فیلتر:
1. دامنه .ir از ایرنیک بخرید
2. از CDN آروان کلود استفاده کنید (شرکت ایرانی، POP زیاد در ایران، فیلتر نیست)
3. آروان را به عنوان DNS و CDN جلوی سایت خود قرار دهید
4. کاربران داخل ایران اول به POP تهران آروان وصل می شوند (سریع، بدون فیلتر)، بعد آروان از سرور اصلی (ورسل/سوپابیس) محتوا را می گیرد.

---

## CHECKLIST BEFORE BUYING:

[ ] Domain .ir available? Check on nic.ir
[ ] Can you change NS to arvancloud.ir or cloudflare.com?
[ ] Hosting has 1TB bandwidth?
[ ] Database is PostgreSQL 15+ with 8GB?
[ ] Daily backup included?
[ ] SSL free?
[ ] Support Node.js 18+?
[ ] Location: Iran or good ping to Iran (<80ms)?
[ ] Can host 600 users concurrently?
[ ] Price for 1 year total?

Copy these keywords and search on:
- iranserver.com
- parspack.com
- liara.ir
- hostiran.net
- arvancloud.ir
- nic.ir
