# جاهزية تحويل الرصيد الدائن بين الإخوة — UI + SQL

## ما الذي تم تنفيذه
### 1) SQL
- `sql/archive/165_finance_credit_transfer_between_siblings.sql`

يضيف:
- جدول `finance_credit_transfers`
- RPC لاقتراح الطلاب الهدف من نفس ولي الأمر
- RPC لتنفيذ نقل الرصيد
- تحديث reconciliation حتى تحتسب التحويلات بين الإخوة

### 2) واجهة تقرير الرصيد الدائن
- `assets/finance-credit-report.js`
- `assets/finance-credit-report.css`
- `finance-credit-report.html`

تمت إضافة:
- زر `تحويل لطالب آخر`
- Modal لاختيار الطالب الهدف
- إدخال مبلغ التحويل والملاحظة
- تنفيذ التحويل من نفس شاشة الرصيد الدائن

### 3) ربط من النظام المالي الرئيسي
- `assets/finance-pro.js`
- `finance-pro.html`

تمت إضافة زر:
- `تحويل رصيد`

داخل الطالب الذي لديه `credit_balance > 0`

وعند الضغط عليه ينتقل مباشرة إلى تقرير الرصيد الدائن مع فتح مسار التحويل.

## النتيجة العملية
إذا دفع ولي الأمر زيادة لطالب معيّن، تستطيع المالية الآن:
1. فتح الطالب من `finance-pro.html`
2. الضغط على `تحويل رصيد`
3. اختيار الأخ/الأخت الهدف
4. إدخال مبلغ التحويل
5. تنفيذ النقل

## ملاحظة تشغيلية
لكي تعمل هذه الميزة فعليًا على الموقع، يجب تشغيل:
- `sql/archive/165_finance_credit_transfer_between_siblings.sql`

## دعم العملتين
تم أيضًا تجهيز patch إضافية لدعم حفظ التحويلات مع:
- الدولار USD
- الريال الإيراني IRR
- وسعر الصرف المستخدم

الملف:
- `sql/archive/166_finance_credit_transfer_currency_support.sql`
