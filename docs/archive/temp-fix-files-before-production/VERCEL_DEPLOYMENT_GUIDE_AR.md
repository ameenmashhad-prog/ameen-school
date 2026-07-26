# دليل توحيد النشر على Vercel — حل مشكلة النسخ الكثيرة والصفحات المختفية

## المشكلة التي كانت عندك
- عندك نسخ كثيرة على Vercel (Production + Preview من فروع مختلفة)
- الفرع `feat/unify-design` و `redesign/new-identity` محذوف منهما ملفات مهمة → عند نشرهما تختفي صفحات
- `.vercelignore` كان يحجب `deployment-check.html` و `clear-session.html` اللذان مرتبطان من `super-admin.html` → 404
- سجل البوابة `platform-modules.js` فيه 40 صفحة فقط بينما المشروع فيه 65 → 25 صفحة تبدو مختفية

## الحل النهائي (5 دقائق)

### الخطوة 1: توحيد الفروع في GitHub
```bash
# تأكد أنك على main
git checkout main
git pull origin main

# الفروع الأخرى فيها تصميم جديد لكن ناقصة ملفات مالية - ندمج المفيد منها
# إذا كنت تريد الاحتفاظ بعمل التصميم:
git merge --no-ff origin/redesign/new-identity -m "merge: bring icon engine v6 to main, keep all finance pages"
# حل أي تعارض لصالح main (للصفحات المالية)

git push origin main
```

### الخطوة 2: تصحيح Vercel Settings
1. ادخل https://vercel.com/dashboard → مشروع `ameen-school`
2. Settings → Git:
   - Production Branch: `main`
   - Preview Deployments: عطّل أو اختر فقط main
   - Ignored Build Step: اتركه فارغاً
3. Settings → Domains: تأكد أن الدومين الرئيسي يشير لـ `main`

### الخطوة 3: تطبيق الملفات المصححة (تمت بالفعل في هذا المشروع)
الملفات التي تم إصلاحها:
- `vercel.json` → CSP أوسع، cleanUrls:true، cache لـ assets
- `.vercelignore` → لا يحجب صفحات الإنتاج
- `assets/platform-modules.js` → الآن 65 وحدة بدل 40
- `all-pages-hub.html` → مركز توحيد شامل

إذا لم تكن طبقتها:
```bash
cp vercel.fixed.json vercel.json
cp .vercelignore.fixed .vercelignore
cp assets/platform-modules.fixed.js assets/platform-modules.js
git add vercel.json .vercelignore assets/platform-modules.js all-pages-hub.html
git commit -m "fix: unify deployment - unhide 25 pages, fix CSP and vercelignore"
git push origin main
```

### الخطوة 4: إعادة نشر
Vercel سيعيد النشر تلقائياً بعد push. انتظر دقيقة ثم:
- افتح `https://your-domain.vercel.app/all-pages-hub.html` → يجب أن ترى 65 صفحة
- افتح `https://your-domain.vercel.app/portal.html` → شبكة فيها الآن أكثر من 60 كارت
- افتح `https://your-domain.vercel.app/super-admin.html` → جرب زر "فحص النشر" و "مسح الجلسة" (الآن تعمل)

### الخطوة 5: حذف النسخ القديمة
- Vercel → Deployments → احذف Deployments قديمة من فروع أخرى (اختياري)
- GitHub → Branches → احذف `feat/unify-design` و `redesign/new-identity` بعد التأكد أنك دمجت ما تريده

### الخطوة 6: اختبار Supabase Proxy
```bash
curl https://your-domain.vercel.app/api/rest/v1/users?select=id -H "apikey: YOUR_ANON_KEY" -H "Authorization: Bearer YOUR_ANON_KEY"
```
يجب أن يرجع 200، ليس 403.

## نصائح مستقبلية
- لا تنشئ فرع جديد لكل تعديل صغير — اعمل مباشرة على `main` أو استخدم Pull Requests
- إذا أردت تجربة تصميم جديد، استخدم `preview-mockup.html` فقط، ليس فرع كامل
- اجعل `all-pages-hub.html` هي مرجعك الدائم لمعرفة إذا صفحة مخفية
- شغّل `sql/000_complete_system_baseline_v5.sql` مرة واحدة في Supabase SQL Editor إذا صفحات المالية تظهر فارغة (تحتاج Views)

## النتيجة
- نسخة واحدة موحدة
- 65 صفحة ظاهرة
- لا 404
- بوابة موحدة فيها كل شيء
