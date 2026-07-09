# Amin Forms Studio v3

طبقة مستقلة جديدة مبنية لتطبيق برومبت v3 على بنية حديثة (Next.js + Tailwind + RPC-only + i18n modular).

## التشغيل المتوقع
```bash
cd next-forms-v3
npm install
npm run dev
```

## ملاحظات قبل التشغيل
- أضف الخطوط المحلية داخل `public/fonts/`
- انسخ الإعدادات من `.env.example`
- عرّف:
  - `NEXT_PUBLIC_SUPABASE_URL`
  - `NEXT_PUBLIC_SUPABASE_ANON_KEY`
  - `SUPABASE_SERVICE_ROLE_KEY`
  - `FORMS_UPLOAD_BUCKET` (اختياري، الافتراضي: `forms-v3-uploads`)
- اربط RPCات الفعلية المذكورة في `docs/FORMS_ENGINE_V3_IMPLEMENTATION_AR.md`
- جهّز bucket تخزين مناسب لرفع مرفقات الاستمارات عبر مسار الخادم `/api/forms/upload-file`.

## فحوص backend بعد تطبيق SQL
```bash
npm run forms:health
npm run forms:smoke
```

راجع أيضًا:
- `docs/FORMS_V3_BACKEND_ACTIVATION_AR.md`
