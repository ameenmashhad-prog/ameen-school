# عقد RPC المقترح — محرك الاستمارات v3

## المبدأ
لا توجد أي كتابة مباشرة من الواجهة إلى الجداول.
كل عمليات الإنشاء/التحديث/الاستعادة/النشر/قراءة النسخ تمر عبر RPC فقط.

---

## 1) forms_save_draft_v3
### المدخلات
```json
{
  "form_slug": "student-registration-v3",
  "locale": "ar",
  "version_label": "2026-07-09T10:00:00.000Z",
  "visibility": "public",
  "autosave": true,
  "schema": { "...": "full form schema" }
}
```

### المخرجات
```json
{
  "ok": true,
  "form_id": "uuid",
  "version_id": "uuid",
  "saved_at": "timestamp"
}
```

---

## 2) forms_restore_version_v3
### المدخلات
```json
{
  "version_id": "uuid"
}
```

### المخرجات
```json
{
  "ok": true,
  "schema": { "...": "restored form schema" },
  "restored_from": "uuid"
}
```

---

## 3) forms_publish_v3
### المدخلات
```json
{
  "form_slug": "student-registration-v3",
  "locale": "ar",
  "visibility": "public",
  "schema": { "...": "validated final schema" }
}
```

### المخرجات
```json
{
  "ok": true,
  "published_form_id": "uuid",
  "issued_at": "timestamp",
  "status": "issued"
}
```

---

## 4) forms_list_versions_v3
### المدخلات
```json
{
  "form_slug": "student-registration-v3"
}
```

### المخرجات
```json
{
  "ok": true,
  "versions": [
    { "version_id": "uuid", "version_label": "...", "saved_at": "..." }
  ]
}
```

---

## 5) forms_request_upload_ticket_v3
### المدخلات
```json
{
  "form_slug": "student-registration-v3",
  "locale": "ar",
  "field_id": "student_documents",
  "file_name": "passport.pdf",
  "content_type": "application/pdf",
  "byte_size": 524288
}
```

### المخرجات
```json
{
  "ok": true,
  "ticket_id": "uuid-or-token",
  "expires_at": "timestamp",
  "upload_strategy": "signed_upload"
}
```

---

## 6) forms_submit_student_registration_v3
### المدخلات
```json
{
  "form_slug": "student-registration-v3",
  "locale": "ar",
  "visibility": "public",
  "submission_ref": "SR-1720000000000",
  "upload_ticket_id": "uuid-or-token",
  "schema": { "...": "validated schema snapshot" },
  "values": { "...": "submitted values" }
}
```

### المخرجات
```json
{
  "ok": true,
  "submission_id": "uuid",
  "submission_ref": "SR-1720000000000",
  "status": "received"
}
```

---

## 7) مسار النقل الثنائي للملفات
بعد إصدار تذكرة الرفع من `forms_request_upload_ticket_v3`، يتم نقل الملف الثنائي عبر مسار الخادم:
- `POST /api/forms/upload-file`

### المدخلات (multipart/form-data)
- `ticket_id`
- `form_slug`
- `field_id`
- `file`

### المخرجات
```json
{
  "ok": true,
  "bucket": "forms-v3-uploads",
  "object_path": "student-registration-v3/student_documents/...",
  "file_name": "passport.pdf",
  "byte_size": 524288
}
```

> هذا المسار ليس كتابة مباشرة من الواجهة إلى الجداول، بل نقل ثنائي للخادم بعد إصدار تذكرة RPC، بينما يبقى حفظ بيانات النموذج نفسه عبر RPC فقط.

---

## 8) forms_submit_teacher_evaluation_v3
### المدخلات
```json
{
  "form_slug": "teacher-evaluation-v3",
  "locale": "ar",
  "visibility": "administrative",
  "submission_ref": "TE-1720000000000",
  "upload_ticket_id": "uuid-or-token",
  "schema": { "...": "validated schema snapshot" },
  "values": { "...": "submitted values" }
}
```

### المخرجات
```json
{
  "ok": true,
  "submission_id": "uuid",
  "submission_ref": "TE-1720000000000",
  "status": "received"
}
```
