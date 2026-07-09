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
    key: 'family_registration_v3',
    title: { ar: 'تسجيل الأسرة والطلاب', fa: 'ثبت‌نام خانواده و دانش‌آموزان', en: 'Family & Students Registration' },
    description: {
      ar: 'نسخة عائلية حديثة مبنية على بيانات الاستمارة القديمة مع منع تكرار بيانات الأب والعائلة',
      fa: 'نسخه خانوادگی جدید بر پایه فرم قدیمی با حذف تکرار اطلاعات پدر و نام خانوادگی',
      en: 'A normalized family registration flow based on the legacy form without repeating father and family data'
    }
  },
  {
    key: 'student_registration_packet',
    title: { ar: 'استمارة التسجيل المطبوعة', fa: 'فرم چاپی ثبت‌نام', en: 'Printable Registration Packet' },
    description: {
      ar: 'إعادة بناء فورم التسجيل الورقي بصيغة قابلة للتعديل والطباعة مع القسم المالي',
      fa: 'بازسازی فرم کاغذی ثبت‌نام به‌صورت قابل ویرایش و چاپ همراه با بخش مالی',
      en: 'Editable and printable rebuild of the paper registration packet with finance fields'
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


const nationalityOptions = [
  option('iraqi', 'عراقي', 'عراقی', 'Iraqi'),
  option('syrian', 'سوري', 'سوری', 'Syrian'),
  option('lebanese', 'لبناني', 'لبنانی', 'Lebanese'),
  option('bahraini', 'بحريني', 'بحرینی', 'Bahraini'),
  option('kuwaiti', 'كويتي', 'کویتی', 'Kuwaiti'),
  option('yemeni', 'يمني', 'یمنی', 'Yemeni'),
  option('afghan', 'أفغاني', 'افغانی', 'Afghan'),
  option('iranian', 'إيراني', 'ایرانی', 'Iranian'),
  option('other', 'أخرى', 'سایر', 'Other')
];

const educationOptions = [
  option('primary', 'ابتدائي', 'ابتدایی', 'Primary'),
  option('middle', 'متوسط', 'متوسطه', 'Middle School'),
  option('secondary', 'إعدادي', 'دبیرستان', 'Secondary'),
  option('bachelor', 'بكالوريوس', 'کارشناسی', 'Bachelor'),
  option('master', 'ماجستير', 'کارشناسی ارشد', 'Master'),
  option('doctorate', 'دكتوراه', 'دکتری', 'Doctorate')
];

const guardianWorkOptions = [
  option('merchant', 'كاسب', 'کاسب', 'Merchant'),
  option('employee', 'موظف', 'کارمند', 'Employee'),
  option('masters_student', 'طالب ماجستير', 'دانشجوی ارشد', 'Master Student'),
  option('doctorate_student', 'طالب دكتوراه', 'دانشجوی دکتری', 'Doctorate Student'),
  option('doctor', 'طبيب', 'پزشک', 'Doctor'),
  option('engineer', 'مهندس', 'مهندس', 'Engineer'),
  option('other', 'أخرى', 'سایر', 'Other')
];

const motherWorkOptions = [
  option('homemaker', 'ربة منزل', 'خانه‌دار', 'Homemaker'),
  option('student', 'طالبة', 'دانشجو', 'Student'),
  option('employee', 'موظفة', 'کارمند', 'Employee'),
  option('teacher', 'معلمة', 'معلم', 'Teacher'),
  option('doctor', 'طبيبة', 'پزشک', 'Doctor'),
  option('engineer', 'مهندسة', 'مهندس', 'Engineer'),
  option('masters_student', 'طالبة ماجستير', 'دانشجوی ارشد', 'Master Student'),
  option('doctorate_student', 'طالبة دكتوراه', 'دانشجوی دکتری', 'Doctorate Student'),
  option('business_owner', 'صاحبة عمل', 'صاحب کسب‌وکار', 'Business Owner'),
  option('other', 'أخرى', 'سایر', 'Other')
];

const residenceOptions = [
  option('annual', 'سنوي', 'سالانه', 'Annual'),
  option('visit', 'زيارة', 'زیارتی', 'Visit')
];

const studentGenderOptions = [
  option('male', 'ذكر', 'پسر', 'Male'),
  option('female', 'أنثى', 'دختر', 'Female')
];

const studentSectionOptions = [
  option('section_a', 'أ', 'الف', 'A'),
  option('section_b', 'ب', 'ب', 'B'),
  option('section_c', 'ج', 'ج', 'C'),
  option('section_d', 'د', 'د', 'D')
];

const studentGradeOptions = [
  option('grade_1_primary', 'الأول الابتدائي', 'اول ابتدایی', 'Grade 1 Primary'),
  option('grade_2_primary', 'الثاني الابتدائي', 'دوم ابتدایی', 'Grade 2 Primary'),
  option('grade_3_primary', 'الثالث الابتدائي', 'سوم ابتدایی', 'Grade 3 Primary'),
  option('grade_4_primary', 'الرابع الابتدائي', 'چهارم ابتدایی', 'Grade 4 Primary'),
  option('grade_5_primary', 'الخامس الابتدائي', 'پنجم ابتدایی', 'Grade 5 Primary'),
  option('grade_6_primary', 'السادس الابتدائي', 'ششم ابتدایی', 'Grade 6 Primary'),
  option('grade_1_middle', 'الأول المتوسط', 'اول متوسطه', 'Grade 1 Middle'),
  option('grade_2_middle', 'الثاني المتوسط', 'دوم متوسطه', 'Grade 2 Middle'),
  option('grade_3_middle', 'الثالث المتوسط', 'سوم متوسطه', 'Grade 3 Middle'),
  option('grade_4_secondary', 'الرابع الإعدادي', 'چهارم دبیرستان', 'Grade 4 Secondary'),
  option('grade_5_secondary', 'الخامس الإعدادي', 'پنجم دبیرستان', 'Grade 5 Secondary'),
  option('grade_6_secondary', 'السادس الإعدادي', 'ششم دبیرستان', 'Grade 6 Secondary')
];

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
  family_registration_v3: {
    slug: 'family-registration-v3',
    visibility: 'public',
    printOrientation: 'portrait',
    title: {
      ar: 'تسجيل الأسرة والطلاب',
      fa: 'ثبت‌نام خانواده و دانش‌آموزان',
      en: 'Family & Students Registration'
    },
    sections: [
      { key: 'guardian', title: { ar: 'بيانات ولي الأمر', fa: 'اطلاعات ولی', en: 'Guardian Information' } },
      { key: 'mother', title: { ar: 'بيانات الأم', fa: 'اطلاعات مادر', en: 'Mother Information' } },
      { key: 'students', title: { ar: 'بطاقات الطلاب', fa: 'کارت‌های دانش‌آموزان', en: 'Student Cards' } },
      { key: 'family_context', title: { ar: 'السياق العائلي والصحي', fa: 'وضعیت خانوادگی و سلامت', en: 'Family & Health Context' } },
      { key: 'finance', title: { ar: 'الرسوم والأمور المالية', fa: 'شهریه و امور مالی', en: 'Tuition & Finance' } },
      { key: 'documents', title: { ar: 'الوثائق والمرفقات', fa: 'مدارک و پیوست‌ها', en: 'Documents & Attachments' } },
      { key: 'approval', title: { ar: 'الاعتماد والطباعة', fa: 'تأیید و چاپ', en: 'Approval & Print' } }
    ],
    fields: [
      field({ id:'guardian_given_name', type:'text', ar:'اسم ولي الأمر', fa:'نام ولی', en:'Guardian Name', required:true, width:'half', section:'guardian' }),
      field({ id:'guardian_father_name', type:'text', ar:'اسم الأب لولي الأمر', fa:'نام پدر ولی', en:'Guardian Father Name', required:true, width:'half', section:'guardian' }),
      field({ id:'family_name', type:'text', ar:'اسم العائلة', fa:'نام خانوادگی', en:'Family Name', required:true, width:'half', section:'guardian' }),
      field({ id:'guardian_username', type:'text', ar:'اسم المستخدم المقترح', fa:'نام کاربری پیشنهادی', en:'Suggested Username', width:'half', section:'guardian' }),
      field({ id:'guardian_birth_date', type:'date', ar:'تاريخ الميلاد', fa:'تاریخ تولد', en:'Date of Birth', required:true, width:'half', section:'guardian' }),
      field({ id:'guardian_nationality', type:'select', ar:'الجنسية', fa:'ملیت', en:'Nationality', required:true, width:'half', section:'guardian', options:nationalityOptions }),
      field({ id:'guardian_passport_number', type:'text', ar:'رقم جواز السفر', fa:'شماره گذرنامه', en:'Passport Number', width:'half', section:'guardian' }),
      field({ id:'guardian_phone_primary', type:'text', ar:'الهاتف الأساسي', fa:'تلفن اصلی', en:'Primary Phone', required:true, width:'half', section:'guardian', placeholder:{ ar:'مثال: +964...', fa:'مثال: +98...', en:'Example: +964...' } }),
      field({ id:'guardian_phone_whatsapp', type:'text', ar:'واتساب', fa:'واتساپ', en:'WhatsApp', width:'half', section:'guardian' }),
      field({ id:'guardian_phone_emergency', type:'text', ar:'هاتف الطوارئ', fa:'تلفن اضطراری', en:'Emergency Phone', width:'half', section:'guardian' }),
      field({ id:'guardian_education_level', type:'select', ar:'التحصيل الدراسي', fa:'تحصیلات', en:'Education Level', width:'half', section:'guardian', options:educationOptions }),
      field({ id:'guardian_education_notes', type:'text', ar:'توضيحات التحصيل الدراسي', fa:'توضیحات تحصیلی', en:'Education Notes', width:'full', section:'guardian' }),
      field({ id:'guardian_work_type', type:'select', ar:'العمل', fa:'شغل', en:'Work Type', width:'half', section:'guardian', options:guardianWorkOptions }),
      field({ id:'guardian_work_notes', type:'text', ar:'توضيح العمل', fa:'توضیح شغل', en:'Work Notes', width:'half', section:'guardian' }),
      field({ id:'residence_type', type:'select', ar:'نوع الإقامة', fa:'نوع اقامت', en:'Residence Type', width:'half', section:'guardian', options:residenceOptions }),
      field({ id:'mother_given_name', type:'text', ar:'اسم الأم', fa:'نام مادر', en:'Mother Name', width:'half', section:'mother' }),
      field({ id:'mother_father_name', type:'text', ar:'اسم الأب للأم', fa:'نام پدر مادر', en:'Mother Father Name', width:'half', section:'mother' }),
      field({ id:'mother_family_name', type:'text', ar:'اسم العائلة للأم', fa:'نام خانوادگی مادر', en:'Mother Family Name', width:'half', section:'mother' }),
      field({ id:'mother_birth_date', type:'date', ar:'تاريخ ميلاد الأم', fa:'تاریخ تولد مادر', en:'Mother Date of Birth', width:'half', section:'mother' }),
      field({ id:'mother_nationality', type:'select', ar:'الجنسية', fa:'ملیت', en:'Nationality', width:'half', section:'mother', options:nationalityOptions }),
      field({ id:'mother_passport_number', type:'text', ar:'رقم جواز السفر', fa:'شماره گذرنامه', en:'Passport Number', width:'half', section:'mother' }),
      field({ id:'mother_phone', type:'text', ar:'رقم الهاتف', fa:'شماره تلفن', en:'Phone Number', width:'half', section:'mother' }),
      field({ id:'mother_whatsapp', type:'text', ar:'واتساب', fa:'واتساپ', en:'WhatsApp', width:'half', section:'mother' }),
      field({ id:'mother_education_level', type:'select', ar:'التحصيل الدراسي', fa:'تحصیلات', en:'Education Level', width:'half', section:'mother', options:educationOptions }),
      field({ id:'mother_education_notes', type:'text', ar:'توضيحات التحصيل الدراسي', fa:'توضیحات تحصیلی', en:'Education Notes', width:'full', section:'mother' }),
      field({ id:'mother_work_type', type:'select', ar:'العمل', fa:'شغل', en:'Work Type', width:'half', section:'mother', options:motherWorkOptions }),
      field({ id:'mother_work_notes', type:'text', ar:'توضيح العمل', fa:'توضیح شغل', en:'Work Notes', width:'half', section:'mother' }),
      field({ id:'living_with_in_iran', type:'text', ar:'مع من يعيش الطالب / الطلاب في إيران', fa:'دانش‌آموزان در ایران با چه کسی زندگی می‌کنند', en:'Who the Students Live with in Iran', width:'half', section:'family_context' }),
      field({ id:'general_family_health_notes', type:'textarea', ar:'ملاحظات صحية / عائلية عامة', fa:'یادداشت‌های سلامت / خانوادگی', en:'General Health / Family Notes', width:'full', section:'family_context' }),
      field({ id:'family_attachment', type:'file', ar:'مرفق عائلي أو صحي', fa:'پیوست خانوادگی یا سلامت', en:'Family or Health Attachment', section:'documents', accept:'.pdf,.jpg,.png,.jpeg' }),
      field({ id:'document_copy_received', type:'checkbox', ar:'استلام استنساخ الوثيقة', fa:'دریافت کپی مدرک', en:'Copy of Document Received', width:'half', section:'documents' }),
      field({ id:'document_original_received', type:'checkbox', ar:'استلام النسخة الأصلية', fa:'دریافت نسخه اصلی', en:'Original Document Received', width:'half', section:'documents' }),
      field({ id:'document_notes', type:'textarea', ar:'ملاحظات الوثائق', fa:'یادداشت‌های مدارک', en:'Document Notes', width:'full', section:'documents' }),
      field({ id:'accept_terms', type:'checkbox', ar:'أوافق على اعتماد البيانات العائلية وطباعة الطلب', fa:'با ثبت اطلاعات خانوادگی و چاپ فرم موافقم', en:'I accept the family data and print approval', required:true, width:'full', section:'approval' }),
      field({ id:'guardian_signature', type:'signature', ar:'توقيع ولي الأمر', fa:'امضای ولی', en:'Guardian Signature', required:true, width:'half', section:'approval' })
    ],
    studentCardFields: [
      field({ id:'student_given_name', type:'text', ar:'اسم الطالب', fa:'نام دانش‌آموز', en:'Student Name', required:true, width:'half', section:'students' }),
      field({ id:'student_father_name', type:'text', ar:'اسم الأب', fa:'نام پدر', en:'Father Name', required:true, width:'half', section:'students' }),
      field({ id:'student_family_name', type:'text', ar:'اسم العائلة', fa:'نام خانوادگی', en:'Family Name', required:true, width:'half', section:'students' }),
      field({ id:'student_full_name', type:'text', ar:'الاسم الكامل المحسوب', fa:'نام کامل محاسبه‌شده', en:'Computed Full Name', required:true, width:'full', section:'students' }),
      field({ id:'student_birth_date', type:'date', ar:'تاريخ الميلاد', fa:'تاریخ تولد', en:'Date of Birth', required:true, width:'half', section:'students' }),
      field({ id:'student_gender', type:'select', ar:'الجنس', fa:'جنسیت', en:'Gender', required:true, width:'half', section:'students', options:studentGenderOptions }),
      field({ id:'student_grade', type:'select', ar:'الصف', fa:'پایه', en:'Grade', required:true, width:'half', section:'students', options:studentGradeOptions }),
      field({ id:'student_section', type:'select', ar:'الشعبة', fa:'کلاس / بخش', en:'Section', width:'half', section:'students', options:studentSectionOptions }),
      field({ id:'student_birth_place', type:'text', ar:'مكان الولادة', fa:'محل تولد', en:'Birth Place', width:'half', section:'students' }),
      field({ id:'student_passport_number', type:'text', ar:'رقم الجواز', fa:'شماره گذرنامه', en:'Passport Number', width:'half', section:'students' }),
      field({ id:'student_passport_expiry_date', type:'date', ar:'تاريخ انتهاء الجواز', fa:'تاریخ پایان گذرنامه', en:'Passport Expiry Date', width:'half', section:'students' }),
      field({ id:'student_previous_school', type:'text', ar:'المدرسة السابقة', fa:'مدرسه قبلی', en:'Previous School', width:'half', section:'students' }),
      field({ id:'student_address_mashhad', type:'textarea', ar:'عنوان السكن: مشهد', fa:'نشانی سکونت: مشهد', en:'Address in Mashhad', width:'full', section:'students' }),
      field({ id:'student_address_iraq', type:'textarea', ar:'عنوان السكن: العراق', fa:'نشانی سکونت: عراق', en:'Address in Iraq', width:'full', section:'students' }),
      field({ id:'student_health_notes', type:'textarea', ar:'ملاحظات صحية خاصة بالطالب', fa:'یادداشت سلامت دانش‌آموز', en:'Student Health Notes', width:'full', section:'students' }),
      field({ id:'student_photo', type:'file', ar:'صورة الطالب', fa:'عکس دانش‌آموز', en:'Student Photo', width:'half', section:'students', accept:'.jpg,.png,.jpeg,.webp' }),
      field({ id:'student_username', type:'text', ar:'اسم المستخدم المقترح', fa:'نام کاربری پیشنهادی', en:'Suggested Username', width:'half', section:'students' }),
      field({ id:'student_initial_password', type:'text', ar:'كلمة المرور الأولية', fa:'رمز عبور اولیه', en:'Initial Password', width:'half', section:'students' })
    ]
  },
  student_registration_packet: {
    slug: 'student-registration-packet-v3',
    visibility: 'public',
    printOrientation: 'portrait',
    title: {
      ar: 'استمارة التسجيل المطبوعة',
      fa: 'فرم چاپی ثبت‌نام',
      en: 'Printable Registration Packet'
    },
    sections: [
      { key: 'request', title: { ar: 'بيانات الطلب', fa: 'اطلاعات درخواست', en: 'Request Details' } },
      { key: 'student', title: { ar: 'معلومات الطالب', fa: 'اطلاعات دانش‌آموز', en: 'Student Information' } },
      { key: 'father', title: { ar: 'معلومات الأب', fa: 'اطلاعات پدر', en: 'Father Information' } },
      { key: 'mother', title: { ar: 'معلومات الأم', fa: 'اطلاعات مادر', en: 'Mother Information' } },
      { key: 'family', title: { ar: 'الوضع العائلي والصحي', fa: 'وضعیت خانوادگی و سلامتی', en: 'Family & Health Context' } },
      { key: 'finance', title: { ar: 'الرسوم والأمور المالية', fa: 'شهریه و امور مالی', en: 'Tuition & Finance' } },
      { key: 'attachments', title: { ar: 'المرفقات الداعمة', fa: 'پیوست‌های پشتیبان', en: 'Supporting Attachments' } },
      { key: 'document_status', title: { ar: 'وضع الوثيقة الدراسية', fa: 'وضعیت مدرک تحصیلی', en: 'School Document Status' } },
      { key: 'undertaking', title: { ar: 'التعهد والالتزام', fa: 'تعهد و التزام', en: 'Undertaking & Terms' } },
      { key: 'administration', title: { ar: 'اعتماد الإدارة', fa: 'تأیید مدیریت', en: 'Administrative Approval' } }
    ],
    fields: [
      field({ id:'registration_date', type:'date', ar:'تاريخ التسجيل', fa:'تاریخ ثبت‌نام', en:'Registration Date', required:true, width:'half', section:'request' }),
      field({ id:'guardian_full_name', type:'text', ar:'اسم ولي الأمر', fa:'نام ولی', en:'Guardian Full Name', required:true, width:'half', section:'request' }),
      field({ id:'registration_for', type:'select', ar:'التسجيل لـ', fa:'ثبت‌نام برای', en:'Registering For', required:true, width:'half', section:'request', options:[option('boy','ابني','پسرم','My Son'), option('girl','ابنتي','دخترم','My Daughter')] }),
      field({ id:'target_grade', type:'text', ar:'الصف المطلوب', fa:'پایه مورد درخواست', en:'Target Grade', required:true, width:'half', section:'request' }),
      field({ id:'student_full_name', type:'text', ar:'الاسم الثلاثي', fa:'نام کامل', en:'Student Full Name', required:true, width:'half', section:'student' }),
      field({ id:'student_passport_number', type:'text', ar:'رقم الجواز', fa:'شماره گذرنامه', en:'Passport Number', width:'half', section:'student' }),
      field({ id:'student_birth_date', type:'date', ar:'تاريخ الولادة', fa:'تاریخ تولد', en:'Date of Birth', required:true, width:'half', section:'student' }),
      field({ id:'student_online_study_phone', type:'text', ar:'الهاتف للدروس الإلكترونية', fa:'تلفن برای درس‌های آنلاین', en:'Phone for Online Lessons', width:'half', section:'student' }),
      field({ id:'previous_school', type:'text', ar:'المدرسة السابقة', fa:'مدرسه قبلی', en:'Previous School', width:'half', section:'student' }),
      field({ id:'student_address_mashhad', type:'textarea', ar:'عنوان السكن: مشهد', fa:'نشانی محل سکونت: مشهد', en:'Address in Mashhad', width:'full', section:'student' }),
      field({ id:'student_address_iraq', type:'textarea', ar:'عنوان السكن: العراق', fa:'نشانی محل سکونت: عراق', en:'Address in Iraq', width:'full', section:'student' }),
      field({ id:'father_full_name', type:'text', ar:'الاسم الثلاثي', fa:'نام کامل', en:'Father Full Name', required:true, width:'half', section:'father' }),
      field({ id:'father_guardian_phone', type:'text', ar:'هاتف الولي الخاص', fa:'تلفن ولی', en:'Guardian Phone', required:true, width:'half', section:'father' }),
      field({ id:'father_education', type:'text', ar:'التحصيل الدراسي', fa:'تحصیلات', en:'Education Level', width:'half', section:'father' }),
      field({ id:'father_job_address', type:'textarea', ar:'العمل وعنوان العمل', fa:'شغل و نشانی محل کار', en:'Job & Work Address', width:'full', section:'father' }),
      field({ id:'mother_full_name', type:'text', ar:'الاسم الثلاثي', fa:'نام کامل', en:'Mother Full Name', width:'half', section:'mother' }),
      field({ id:'mother_phone', type:'text', ar:'هاتف الأم', fa:'تلفن مادر', en:'Mother Phone', width:'half', section:'mother' }),
      field({ id:'mother_education', type:'text', ar:'التحصيل الدراسي', fa:'تحصیلات', en:'Education Level', width:'half', section:'mother' }),
      field({ id:'mother_job_address', type:'textarea', ar:'العمل وعنوان العمل', fa:'شغل و نشانی محل کار', en:'Job & Work Address', width:'full', section:'mother' }),
      field({ id:'medical_condition_notes', type:'textarea', ar:'الحالة الصحية / مشاكل النطق أو السمع أو الحالات المزمنة', fa:'وضعیت سلامتی / مشکلات گفتار، شنوایی یا بیماری‌های مزمن', en:'Health Notes / Speech, Hearing, or Chronic Conditions', width:'full', section:'family' }),
      field({ id:'living_with_in_iran', type:'text', ar:'مع من يعيش الطالب في إيران', fa:'دانش‌آموز در ایران با چه کسی زندگی می‌کند', en:'Who the Student Lives with in Iran', width:'half', section:'family' }),
      field({ id:'student_status', type:'textarea', ar:'وضع الطالب نفسياً وجسمياً', fa:'وضعیت روانی و جسمی دانش‌آموز', en:'Student Psychological & Physical Status', width:'full', section:'family' }),
      field({ id:'health_attachment', type:'file', ar:'ملف صحي / مستند داعم', fa:'پرونده سلامت / سند پشتیبان', en:'Health File / Supporting Attachment', section:'attachments', accept:'.pdf,.jpg,.png,.jpeg' }),
      field({ id:'document_copy_received', type:'checkbox', ar:'استلام استنساخ الوثيقة', fa:'دریافت کپی مدرک', en:'Copy of Document Received', width:'half', section:'document_status' }),
      field({ id:'document_original_received', type:'checkbox', ar:'استلام النسخة الأصلية', fa:'دریافت نسخه اصلی', en:'Original Document Received', width:'half', section:'document_status' }),
      field({ id:'document_notes', type:'textarea', ar:'توضيحات', fa:'توضیحات', en:'Notes', width:'full', section:'document_status' }),
      field({ id:'accept_terms', type:'checkbox', ar:'أوافق على التعهد والشروط', fa:'تعهد و شرایط را می‌پذیرم', en:'I accept the undertaking and terms', required:true, width:'full', section:'undertaking' }),
      field({ id:'parent_signature', type:'signature', ar:'توقيع ولي الأمر', fa:'امضای ولی', en:'Guardian Signature', required:true, width:'half', section:'undertaking' }),
      field({ id:'terms_guardian_phone', type:'text', ar:'رقم الهاتف في صفحة التعهد', fa:'شماره تلفن در صفحه تعهد', en:'Phone Number on Undertaking Page', width:'half', section:'undertaking' }),
      field({ id:'registered_by', type:'text', ar:'تم تسجيل الطالب من قبل', fa:'دانش‌آموز توسط چه کسی ثبت شد', en:'Registered By', width:'half', section:'administration' }),
      field({ id:'registered_on', type:'date', ar:'بتاريخ', fa:'در تاریخ', en:'Registered On', width:'half', section:'administration' }),
      field({ id:'registration_officer_signature', type:'signature', ar:'توقيع مسؤول التسجيل', fa:'امضای مسئول ثبت‌نام', en:'Registration Officer Signature', width:'half', section:'administration' }),
      field({ id:'finance_officer_signature', type:'signature', ar:'توقيع المسؤول المالي', fa:'امضای مسئول مالی', en:'Finance Officer Signature', width:'half', section:'administration' }),
      field({ id:'director_signature', type:'signature', ar:'توقيع مدير المجمع', fa:'امضای مدیر مجتمع', en:'Director Signature', width:'full', section:'administration' })
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
    sections: [
      { key: 'teacher', title: { ar: 'بيانات المعلم', fa: 'اطلاعات معلم', en: 'Teacher Information' } },
      { key: 'evaluation', title: { ar: 'تفاصيل التقييم', fa: 'جزئیات ارزیابی', en: 'Evaluation Details' } },
      { key: 'evidence', title: { ar: 'الشواهد والمرفقات', fa: 'شواهد و پیوست‌ها', en: 'Evidence & Attachments' } },
      { key: 'approval', title: { ar: 'اعتماد المقيم', fa: 'تایید ارزیاب', en: 'Reviewer Approval' } }
    ],
    fields: [
      field({ id:'teacher_name', type: 'text', ar: 'اسم المعلم', fa: 'نام معلم', en: 'Teacher Name', required: true, width:'half', section:'teacher' }),
      field({ id:'subject_area', type: 'text', ar: 'المادة / التخصص', fa: 'درس / تخصص', en: 'Subject / Specialization', required: true, width:'half', section:'teacher' }),
      field({ id:'evaluator_name', type: 'text', ar: 'اسم المقيم', fa: 'نام ارزیاب', en: 'Evaluator Name', required: true, width:'half', section:'teacher' }),
      field({ id:'evaluation_date', type: 'date', ar: 'تاريخ التقييم', fa: 'تاریخ ارزیابی', en: 'Evaluation Date', required: true, width:'half', section:'teacher' }),
      field({ id:'class_context', type: 'text', ar: 'الصف / السياق', fa: 'پایه / زمینه', en: 'Class / Context', width:'half', section:'teacher' }),
      field({ id:'semester', type: 'select', ar: 'الفصل الدراسي', fa: 'نیمسال', en: 'Semester', width:'half', section:'teacher', options:[option('semester_1','الفصل الأول','نیمسال اول','Semester 1'), option('semester_2','الفصل الثاني','نیمسال دوم','Semester 2')] }),
      field({ id:'criteria', type: 'select', ar: 'المعيار', fa: 'شاخص', en: 'Criteria', required: true, width:'half', section:'evaluation', options: [option('criteria_pedagogy', 'الأداء التدريسي', 'عملکرد آموزشی', 'Teaching Performance'), option('criteria_punctuality', 'الانضباط الزمني', 'نظم زمانی', 'Punctuality'), option('criteria_communication', 'التواصل', 'ارتباط', 'Communication'), option('criteria_preparation', 'التحضير والتنظيم', 'آماده‌سازی و نظم', 'Preparation & Organization')] }),
      field({ id:'score', type: 'number', ar: 'الدرجة', fa: 'امتیاز', en: 'Score', required: true, width:'half', section:'evaluation', placeholder:{ar:'من 100',fa:'از 100',en:'Out of 100'} }),
      field({ id:'strengths', type: 'text', ar: 'نقاط القوة', fa: 'نقاط قوت', en: 'Strengths', section:'evaluation' }),
      field({ id:'improvement_points', type: 'text', ar: 'مجالات التحسين', fa: 'زمینه‌های بهبود', en: 'Improvement Areas', section:'evaluation' }),
      field({ id:'recommendation', type: 'text', ar: 'التوصية النهائية', fa: 'توصیه نهایی', en: 'Final Recommendation', section:'evaluation' }),
      field({ id:'evidence_attachment', type:'file', ar:'مرفق داعم', fa:'پیوست پشتیبان', en:'Supporting Attachment', section:'evidence', accept:'.pdf,.jpg,.png,.jpeg' }),
      field({ id:'reviewer_signature', type: 'signature', ar: 'اعتماد المقيم', fa: 'تایید ارزیاب', en: 'Reviewer Signature', required: true, section:'approval' })
    ]
  },
  financial_permission: {
    slug: 'financial-permission-v3',
    visibility: 'finance_admin',
    printOrientation: 'landscape',
    title: { ar: 'استمارة استئذان مالي', fa: 'فرم مجوز مالی', en: 'Financial Permission Form' },
    sections: [
      { key: 'requestor', title: { ar: 'بيانات الجهة الطالبة', fa: 'اطلاعات درخواست‌کننده', en: 'Requestor Information' } },
      { key: 'finance', title: { ar: 'تفاصيل الطلب المالي', fa: 'جزئیات درخواست مالی', en: 'Financial Request Details' } },
      { key: 'attachments', title: { ar: 'المرفقات الداعمة', fa: 'پیوست‌های پشتیبان', en: 'Supporting Attachments' } },
      { key: 'approval', title: { ar: 'الاعتماد والتوقيع', fa: 'تایید و امضا', en: 'Approval & Signature' } }
    ],
    fields: [
      field({ id:'requesting_unit', type:'text', ar:'اسم الجهة الطالبة', fa:'نام درخواست‌کننده', en:'Requesting Unit', required:true, width:'half', section:'requestor' }),
      field({ id:'requester_name', type:'text', ar:'اسم مقدم الطلب', fa:'نام ثبت‌کننده', en:'Requester Name', required:true, width:'half', section:'requestor' }),
      field({ id:'requester_role', type:'text', ar:'الصفة / المنصب', fa:'سمت / عنوان', en:'Role / Title', width:'half', section:'requestor' }),
      field({ id:'request_date', type:'date', ar:'تاريخ الطلب', fa:'تاریخ درخواست', en:'Request Date', required:true, width:'half', section:'requestor' }),
      field({ id:'requested_amount', type:'number', ar:'المبلغ المطلوب', fa:'مبلغ درخواستی', en:'Requested Amount', required:true, width:'half', section:'finance', placeholder:{ar:'بالرقم',fa:'به‌صورت عددی',en:'Numeric amount'} }),
      field({ id:'currency', type:'select', ar:'العملة', fa:'واحد پول', en:'Currency', required:true, width:'half', section:'finance', options:[option('IQD','دينار عراقي','دینار عراق','Iraqi Dinar'), option('USD','دولار','دلار','US Dollar')] }),
      field({ id:'cost_center', type:'text', ar:'مركز الكلفة', fa:'مرکز هزینه', en:'Cost Center', width:'half', section:'finance' }),
      field({ id:'budget_line', type:'text', ar:'البند / الحساب', fa:'ردیف / حساب', en:'Budget Line / Account', width:'half', section:'finance' }),
      field({ id:'needed_by_date', type:'date', ar:'مطلوب قبل تاريخ', fa:'نیاز تا تاریخ', en:'Needed By Date', width:'half', section:'finance' }),
      field({ id:'urgency', type:'select', ar:'الأولوية', fa:'اولویت', en:'Urgency', width:'half', section:'finance', options:[option('normal','عادي','عادی','Normal'), option('high','عاجل','فوری','Urgent')] }),
      field({ id:'reason', type:'text', ar:'سبب الطلب', fa:'دلیل درخواست', en:'Reason', required:true, section:'finance' }),
      field({ id:'supporting_document', type:'file', ar:'المستند الداعم', fa:'سند پشتیبان', en:'Supporting Document', section:'attachments', accept:'.pdf,.jpg,.png,.jpeg,.xlsx' }),
      field({ id:'requester_signature', type:'signature', ar:'توقيع مقدم الطلب', fa:'امضای ثبت‌کننده', en:'Requester Signature', required:true, section:'approval' }),
      field({ id:'finance_approval_signature', type:'signature', ar:'اعتماد المالية', fa:'تایید مالی', en:'Finance Approval', section:'approval' })
    ]
  }
};

export function buildTemplateByKey(key) {
  return cloneForm(templatesMap[key] || templatesMap.student_registration);
}
