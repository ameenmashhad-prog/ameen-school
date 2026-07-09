import { cloneForm, generateId } from '@/lib/utils';

export const formTemplates = [
  {
    key: 'student_registration',
    title: { ar: 'تسجيل طالب', fa: 'ثبت‌نام دانش‌آموز', en: 'Student Registration' },
    description: {
      ar: 'قالب تسجيل طالب مع بيانات ولي الأمر والطالب والوثائق',
      fa: 'قالب ثبت‌نام با اطلاعات ولی، دانش‌آموز و مدارک',
      en: 'Student registration template with guardian, student, and document fields'
    }
  },
  {
    key: 'leave_request',
    title: { ar: 'طلب إجازة', fa: 'درخواست مرخصی', en: 'Leave Request' },
    description: {
      ar: 'قالب إجازة إدارية مع مدة وسبب وموافقات',
      fa: 'قالب مرخصی اداری با مدت، علت و تاییدها',
      en: 'Administrative leave template with duration, reason, and approvals'
    }
  },
  {
    key: 'teacher_evaluation',
    title: { ar: 'تقييم معلم', fa: 'ارزیابی معلم', en: 'Teacher Evaluation' },
    description: {
      ar: 'نموذج تقييم أداء معلم متعدد المعايير',
      fa: 'فرم ارزیابی عملکرد معلم با چند معیار',
      en: 'Multi-criteria teacher performance evaluation'
    }
  },
  {
    key: 'financial_permission',
    title: { ar: 'استئذان مالي', fa: 'مجوز مالی', en: 'Financial Permission' },
    description: {
      ar: 'قالب طلب صرف أو استئذان مالي مع التوقيع',
      fa: 'قالب درخواست هزینه یا مجوز مالی با امضا',
      en: 'Expense or financial approval template with signature'
    }
  }
];

function option(value, ar, fa, en) {
  return {
    id: generateId('option'),
    value,
    label: { ar, fa, en }
  };
}

function field({ id, type, required = false, ar, fa, en, width = 'full', section = 'general', options = [], placeholder = null, accept = null }) {
  return {
    id: id || generateId(type),
    type,
    required,
    width,
    section,
    label: { ar, fa, en },
    placeholder: placeholder || { ar, fa, en },
    helpText: { ar: '', fa: '', en: '' },
    ...(options.length ? { options } : {}),
    ...(accept ? { accept } : {})
  };
}

const templatesMap = {
  student_registration: {
    slug: 'student-registration-v3',
    visibility: 'public',
    printOrientation: 'portrait',
    title: {
      ar: 'استمارة تسجيل طالب',
      fa: 'فرم ثبت‌نام دانش‌آموز',
      en: 'Student Registration Form'
    },
    sections: [
      { key: 'guardian', title: { ar: 'بيانات ولي الأمر', fa: 'اطلاعات ولی', en: 'Guardian Information' } },
      { key: 'student', title: { ar: 'بيانات الطالب', fa: 'اطلاعات دانش‌آموز', en: 'Student Information' } },
      { key: 'attachments', title: { ar: 'الوثائق والمرفقات', fa: 'مدارک و پیوست‌ها', en: 'Documents & Attachments' } },
      { key: 'approval', title: { ar: 'الاعتماد والتوقيع', fa: 'تایید و امضا', en: 'Approval & Signature' } }
    ],
    fields: [
      field({ id: 'guardian_name', type: 'text', ar: 'اسم ولي الأمر', fa: 'نام ولی', en: 'Guardian Name', required: true, width: 'half', section: 'guardian' }),
      field({ id: 'guardian_phone', type: 'text', ar: 'رقم الهاتف', fa: 'شماره تلفن', en: 'Phone Number', required: true, width: 'half', section: 'guardian', placeholder: { ar: 'مثال: +964...', fa: 'مثال: +98...', en: 'Example: +964...' } }),
      field({ id: 'guardian_email', type: 'text', ar: 'البريد الإلكتروني', fa: 'ایمیل', en: 'Email', width: 'half', section: 'guardian' }),
      field({ id: 'guardian_address', type: 'text', ar: 'العنوان', fa: 'نشانی', en: 'Address', width: 'half', section: 'guardian' }),
      field({ id: 'student_name', type: 'text', ar: 'اسم الطالب', fa: 'نام دانش‌آموز', en: 'Student Name', required: true, width: 'half', section: 'student' }),
      field({ id: 'student_birth_date', type: 'date', ar: 'تاريخ الميلاد', fa: 'تاریخ تولد', en: 'Date of Birth', required: true, width: 'half', section: 'student' }),
      field({
        id: 'student_grade', type: 'select', ar: 'الصف', fa: 'پایه', en: 'Grade', required: true, width: 'half', section: 'student',
        options: [
          option('grade_1', 'الأول الابتدائي', 'اول ابتدایی', 'Grade 1'),
          option('grade_2', 'الثاني الابتدائي', 'دوم ابتدایی', 'Grade 2'),
          option('grade_3', 'الثالث الابتدائي', 'سوم ابتدایی', 'Grade 3')
        ]
      }),
      field({
        id: 'student_gender', type: 'select', ar: 'الجنس', fa: 'جنسیت', en: 'Gender', required: true, width: 'half', section: 'student',
        options: [option('male', 'ذكر', 'پسر', 'Male'), option('female', 'أنثى', 'دختر', 'Female')]
      }),
      field({ id: 'student_notes', type: 'text', ar: 'ملاحظات إضافية', fa: 'توضیحات تکمیلی', en: 'Additional Notes', section: 'student' }),
      field({ id: 'student_documents', type: 'file', ar: 'الوثائق', fa: 'مدارک', en: 'Documents', section: 'attachments', accept: '.pdf,.jpg,.png,.jpeg' }),
      field({ id: 'guardian_signature', type: 'signature', ar: 'التوقيع الإلكتروني', fa: 'امضای الکترونیکی', en: 'Electronic Signature', required: true, section: 'approval' })
    ]
  },
  leave_request: {
    slug: 'leave-request-v3',
    visibility: 'administrative',
    printOrientation: 'portrait',
    title: {
      ar: 'نموذج طلب إجازة',
      fa: 'فرم درخواست مرخصی',
      en: 'Leave Request Form'
    },
    sections: [
      { key: 'staff', title: { ar: 'بيانات الموظف', fa: 'اطلاعات کارمند', en: 'Staff Information' } },
      { key: 'leave', title: { ar: 'تفاصيل الإجازة', fa: 'جزئیات مرخصی', en: 'Leave Details' } },
      { key: 'attachments', title: { ar: 'المرفقات الداعمة', fa: 'پیوست‌های پشتیبان', en: 'Supporting Attachments' } },
      { key: 'approval', title: { ar: 'الاعتماد الإداري', fa: 'تایید اداری', en: 'Administrative Approval' } }
    ],
    fields: [
      field({ id:'staff_name', type:'text', ar:'اسم الموظف', fa:'نام کارمند', en:'Staff Name', required:true, width:'half', section:'staff' }),
      field({ id:'staff_department', type:'text', ar:'القسم / الوحدة', fa:'بخش / واحد', en:'Department / Unit', required:true, width:'half', section:'staff' }),
      field({ id:'staff_role', type:'text', ar:'المسمى الوظيفي', fa:'عنوان شغلی', en:'Job Title', width:'half', section:'staff' }),
      field({ id:'staff_email', type:'text', ar:'البريد الإلكتروني', fa:'ایمیل', en:'Email', width:'half', section:'staff' }),
      field({
        id:'leave_type', type:'select', ar:'نوع الإجازة', fa:'نوع مرخصی', en:'Leave Type', required:true, width:'half', section:'leave',
        options:[
          option('annual','إجازة اعتيادية','مرخصی عادی','Annual Leave'),
          option('medical','إجازة مرضية','مرخصی درمانی','Medical Leave'),
          option('emergency','إجازة طارئة','مرخصی اضطراری','Emergency Leave'),
          option('unpaid','إجازة بدون راتب','مرخصی بدون حقوق','Unpaid Leave')
        ]
      }),
      field({ id:'leave_start_date', type:'date', ar:'تاريخ البداية', fa:'تاریخ شروع', en:'Start Date', required:true, width:'half', section:'leave' }),
      field({ id:'leave_end_date', type:'date', ar:'تاريخ النهاية', fa:'تاریخ پایان', en:'End Date', required:true, width:'half', section:'leave' }),
      field({ id:'return_date', type:'date', ar:'تاريخ العودة المتوقع', fa:'تاریخ بازگشت مورد انتظار', en:'Expected Return Date', width:'half', section:'leave' }),
      field({ id:'leave_reason', type:'text', ar:'سبب الإجازة', fa:'علت مرخصی', en:'Leave Reason', required:true, section:'leave' }),
      field({ id:'handover_notes', type:'text', ar:'خطة التسليم / البديل', fa:'برنامه تحویل / جانشین', en:'Handover / Delegate Plan', section:'leave' }),
      field({ id:'supporting_document', type:'file', ar:'المستند الداعم', fa:'سند پشتیبان', en:'Supporting Document', section:'attachments', accept:'.pdf,.jpg,.png,.jpeg' }),
      field({ id:'principal_signature', type:'signature', ar:'اعتماد المدير', fa:'تایید مدیر', en:'Principal Signature', required:true, section:'approval' })
    ]
  },
  teacher_evaluation: {
    slug: 'teacher-evaluation-v3',
    visibility: 'administrative',
    printOrientation: 'portrait',
    title: { ar: 'نموذج تقييم معلم', fa: 'فرم ارزیابی معلم', en: 'Teacher Evaluation Form' },
    sections: [],
    fields: [
      field({ type: 'text', ar: 'اسم المعلم', fa: 'نام معلم', en: 'Teacher Name', required: true }),
      field({ type: 'select', ar: 'المعيار', fa: 'شاخص', en: 'Criteria', required: true, width: 'half', options: [option('criteria_pedagogy', 'الأداء التدريسي', 'عملکرد آموزشی', 'Teaching Performance'), option('criteria_punctuality', 'الانضباط الزمني', 'نظم زمانی', 'Punctuality'), option('criteria_communication', 'التواصل', 'ارتباط', 'Communication')] }),
      field({ type: 'number', ar: 'الدرجة', fa: 'امتیاز', en: 'Score', required: true, width: 'half' }),
      field({ type: 'text', ar: 'ملاحظة', fa: 'یادداشت', en: 'Note' }),
      field({ type: 'signature', ar: 'اعتماد المقيم', fa: 'تایید ارزیاب', en: 'Reviewer Signature', required: true })
    ]
  },
  financial_permission: {
    slug: 'financial-permission-v3',
    visibility: 'finance_admin',
    printOrientation: 'landscape',
    title: { ar: 'استمارة استئذان مالي', fa: 'فرم مجوز مالی', en: 'Financial Permission Form' },
    sections: [],
    fields: [
      field({ type: 'text', ar: 'اسم الجهة الطالبة', fa: 'نام درخواست‌کننده', en: 'Requesting Unit', required: true }),
      field({ type: 'number', ar: 'المبلغ المطلوب', fa: 'مبلغ درخواستی', en: 'Requested Amount', required: true, width: 'half' }),
      field({ type: 'date', ar: 'تاريخ الطلب', fa: 'تاریخ درخواست', en: 'Request Date', required: true, width: 'half' }),
      field({ type: 'text', ar: 'سبب الطلب', fa: 'دلیل درخواست', en: 'Reason', required: true }),
      field({ type: 'signature', ar: 'اعتماد المالية', fa: 'تایید مالی', en: 'Finance Approval', required: true })
    ]
  }
};

export function buildTemplateByKey(key) {
  return cloneForm(templatesMap[key] || templatesMap.student_registration);
}
