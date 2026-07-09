import { cloneForm } from '@/lib/utils';

export const formTemplates = [
  {
    key: 'student_registration',
    title: {
      ar: 'تسجيل طالب',
      fa: 'ثبت‌نام دانش‌آموز',
      en: 'Student Registration'
    },
    description: {
      ar: 'قالب تسجيل طالب مع بيانات ولي الأمر والطالب والوثائق',
      fa: 'قالب ثبت‌نام با اطلاعات ولی، دانش‌آموز و مدارک',
      en: 'Student registration template with guardian, student, and document fields'
    }
  },
  {
    key: 'leave_request',
    title: {
      ar: 'طلب إجازة',
      fa: 'درخواست مرخصی',
      en: 'Leave Request'
    },
    description: {
      ar: 'قالب إجازة إدارية مع مدة وسبب وموافقات',
      fa: 'قالب مرخصی اداری با مدت، علت و تاییدها',
      en: 'Administrative leave template with duration, reason, and approvals'
    }
  },
  {
    key: 'teacher_evaluation',
    title: {
      ar: 'تقييم معلم',
      fa: 'ارزیابی معلم',
      en: 'Teacher Evaluation'
    },
    description: {
      ar: 'نموذج تقييم أداء معلم متعدد المعايير',
      fa: 'فرم ارزیابی عملکرد معلم با چند معیار',
      en: 'Multi-criteria teacher performance evaluation'
    }
  },
  {
    key: 'financial_permission',
    title: {
      ar: 'استئذان مالي',
      fa: 'مجوز مالی',
      en: 'Financial Permission'
    },
    description: {
      ar: 'قالب طلب صرف أو استئذان مالي مع التوقيع',
      fa: 'قالب درخواست هزینه یا مجوز مالی با امضا',
      en: 'Expense or financial approval template with signature'
    }
  }
];

const templatesMap = {
  student_registration: {
    slug: 'student-registration-v3',
    visibility: 'public',
    title: {
      ar: 'استمارة تسجيل طالب',
      fa: 'فرم ثبت‌نام دانش‌آموز',
      en: 'Student Registration Form'
    },
    fields: [
      field('text', 'اسم ولي الأمر', 'نام ولی', 'Guardian Name', true),
      field('text', 'اسم الطالب', 'نام دانش‌آموز', 'Student Name', true),
      field('date', 'تاريخ الميلاد', 'تاریخ تولد', 'Date of Birth', true),
      field('select', 'الصف', 'پایه', 'Grade', true),
      field('file', 'الوثائق', 'مدارک', 'Documents', false),
      field('signature', 'التوقيع الإلكتروني', 'امضای الکترونیکی', 'Electronic Signature', false)
    ]
  },
  leave_request: {
    slug: 'leave-request-v3',
    visibility: 'administrative',
    title: {
      ar: 'نموذج طلب إجازة',
      fa: 'فرم درخواست مرخصی',
      en: 'Leave Request Form'
    },
    fields: [
      field('text', 'اسم الموظف', 'نام کارمند', 'Staff Name', true),
      field('date', 'تاريخ البداية', 'تاریخ شروع', 'Start Date', true),
      field('date', 'تاريخ النهاية', 'تاریخ پایان', 'End Date', true),
      field('text', 'سبب الإجازة', 'علت مرخصی', 'Leave Reason', true),
      field('signature', 'اعتماد المدير', 'تایید مدیر', 'Principal Signature', true)
    ]
  },
  teacher_evaluation: {
    slug: 'teacher-evaluation-v3',
    visibility: 'administrative',
    title: {
      ar: 'نموذج تقييم معلم',
      fa: 'فرم ارزیابی معلم',
      en: 'Teacher Evaluation Form'
    },
    fields: [
      field('text', 'اسم المعلم', 'نام معلم', 'Teacher Name', true),
      field('select', 'المعيار', 'شاخص', 'Criteria', true),
      field('number', 'الدرجة', 'امتیاز', 'Score', true),
      field('text', 'ملاحظة', 'یادداشت', 'Note', false),
      field('signature', 'اعتماد المقيم', 'تایید ارزیاب', 'Reviewer Signature', true)
    ]
  },
  financial_permission: {
    slug: 'financial-permission-v3',
    visibility: 'finance_admin',
    title: {
      ar: 'استمارة استئذان مالي',
      fa: 'فرم مجوز مالی',
      en: 'Financial Permission Form'
    },
    fields: [
      field('text', 'اسم الجهة الطالبة', 'نام درخواست‌کننده', 'Requesting Unit', true),
      field('number', 'المبلغ المطلوب', 'مبلغ درخواستی', 'Requested Amount', true),
      field('text', 'سبب الطلب', 'دلیل درخواست', 'Reason', true),
      field('signature', 'اعتماد المالية', 'تایید مالی', 'Finance Approval', true)
    ]
  }
};

function field(type, ar, fa, en, required) {
  return {
    id: `${type}_${Math.random().toString(36).slice(2, 9)}`,
    type,
    required,
    label: { ar, fa, en },
    placeholder: {
      ar: ar,
      fa: fa,
      en: en
    }
  };
}

export function buildTemplateByKey(key) {
  return cloneForm(templatesMap[key] || templatesMap.student_registration);
}
