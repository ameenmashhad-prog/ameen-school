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

function field({ type, required = false, ar, fa, en, width = 'full', options = [] }) {
  return {
    id: generateId(type),
    type,
    required,
    width,
    label: { ar, fa, en },
    placeholder: {
      ar: ar,
      fa: fa,
      en: en
    },
    helpText: {
      ar: '',
      fa: '',
      en: ''
    },
    ...(options.length ? { options } : {})
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
    fields: [
      field({ type: 'text', ar: 'اسم ولي الأمر', fa: 'نام ولی', en: 'Guardian Name', required: true, width: 'half' }),
      field({ type: 'text', ar: 'اسم الطالب', fa: 'نام دانش‌آموز', en: 'Student Name', required: true, width: 'half' }),
      field({ type: 'date', ar: 'تاريخ الميلاد', fa: 'تاریخ تولد', en: 'Date of Birth', required: true, width: 'half' }),
      field({
        type: 'select', ar: 'الصف', fa: 'پایه', en: 'Grade', required: true, width: 'half',
        options: [
          option('grade_1', 'الأول الابتدائي', 'اول ابتدایی', 'Grade 1'),
          option('grade_2', 'الثاني الابتدائي', 'دوم ابتدایی', 'Grade 2'),
          option('grade_3', 'الثالث الابتدائي', 'سوم ابتدایی', 'Grade 3')
        ]
      }),
      field({ type: 'file', ar: 'الوثائق', fa: 'مدارک', en: 'Documents' }),
      field({ type: 'signature', ar: 'التوقيع الإلكتروني', fa: 'امضای الکترونیکی', en: 'Electronic Signature' })
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
    fields: [
      field({ type: 'text', ar: 'اسم الموظف', fa: 'نام کارمند', en: 'Staff Name', required: true }),
      field({ type: 'date', ar: 'تاريخ البداية', fa: 'تاریخ شروع', en: 'Start Date', required: true, width: 'half' }),
      field({ type: 'date', ar: 'تاريخ النهاية', fa: 'تاریخ پایان', en: 'End Date', required: true, width: 'half' }),
      field({ type: 'text', ar: 'سبب الإجازة', fa: 'علت مرخصی', en: 'Leave Reason', required: true }),
      field({ type: 'signature', ar: 'اعتماد المدير', fa: 'تایید مدیر', en: 'Principal Signature', required: true })
    ]
  },
  teacher_evaluation: {
    slug: 'teacher-evaluation-v3',
    visibility: 'administrative',
    printOrientation: 'portrait',
    title: {
      ar: 'نموذج تقييم معلم',
      fa: 'فرم ارزیابی معلم',
      en: 'Teacher Evaluation Form'
    },
    fields: [
      field({ type: 'text', ar: 'اسم المعلم', fa: 'نام معلم', en: 'Teacher Name', required: true }),
      field({
        type: 'select', ar: 'المعيار', fa: 'شاخص', en: 'Criteria', required: true, width: 'half',
        options: [
          option('criteria_pedagogy', 'الأداء التدريسي', 'عملکرد آموزشی', 'Teaching Performance'),
          option('criteria_punctuality', 'الانضباط الزمني', 'نظم زمانی', 'Punctuality'),
          option('criteria_communication', 'التواصل', 'ارتباط', 'Communication')
        ]
      }),
      field({ type: 'number', ar: 'الدرجة', fa: 'امتیاز', en: 'Score', required: true, width: 'half' }),
      field({ type: 'text', ar: 'ملاحظة', fa: 'یادداشت', en: 'Note' }),
      field({ type: 'signature', ar: 'اعتماد المقيم', fa: 'تایید ارزیاب', en: 'Reviewer Signature', required: true })
    ]
  },
  financial_permission: {
    slug: 'financial-permission-v3',
    visibility: 'finance_admin',
    printOrientation: 'landscape',
    title: {
      ar: 'استمارة استئذان مالي',
      fa: 'فرم مجوز مالی',
      en: 'Financial Permission Form'
    },
    fields: [
      field({ type: 'text', ar: 'اسم الجهة الطالبة', fa: 'نام درخواست‌کننده', en: 'Requesting Unit', required: true }),
      field({ type: 'number', ar: 'المبلغ المطلوب', fa: 'مبلغ درخواستی', en: 'Requested Amount', required: true, width: 'half' }),
      field({ type: 'date', ar: 'تاريخ الطلب', fa: 'تاریخ درخواست', en: 'Request Date', required: true, width: 'half' }),
      field({ type: 'text', ar: 'سبب الطلب', fa: 'دلیل درخواست', en: 'Reason', required: true }),
      field({ type: 'signature', ar: 'اعتماد المالية', fa: 'تایید مالی', en: 'Finance Approval', required: true })
    ]
  }
};

function option(value, ar, fa, en) {
  return {
    id: generateId('option'),
    value,
    label: { ar, fa, en }
  };
}

export function buildTemplateByKey(key) {
  return cloneForm(templatesMap[key] || templatesMap.student_registration);
}
