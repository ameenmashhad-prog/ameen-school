/* Amin Platform Module Registry — single source of truth for portal + command search.
   Vanilla JS only, no external libraries/CDN. */
(function(){
  'use strict';
  if(window.AMIN_PLATFORM && window.AMIN_PLATFORM.version) return;

  const GROUPS = [
    { key:'main', color:'cyan', icon:'grid', title:{ar:'الواجهات الرئيسية', fa:'رابط‌های اصلی', en:'Main Interfaces'}, desc:{ar:'أهم المداخل اليومية حسب صلاحيتك', fa:'ورودی‌های اصلی روزانه بر اساس دسترسی شما', en:'Daily entry points by permission'} },
    { key:'finance', color:'teal', icon:'wallet', title:{ar:'المالية', fa:'امور مالی', en:'Finance'}, desc:{ar:'الرسوم، الأقساط، التحصيل، الصندوق والتقارير', fa:'شهریه، اقساط، وصول، صندوق و گزارش‌ها', en:'Fees, installments, collection, cashbox and reports'} },
    { key:'academic', color:'indigo', icon:'school', title:{ar:'الأكاديمي والجداول', fa:'آموزشی و برنامه‌ها', en:'Academic & Scheduling'}, desc:{ar:'الدرجات، الحصص، الشعب والإسنادات', fa:'نمرات، کلاس‌ها، بخش‌ها و تخصیص‌ها', en:'Grades, sessions, sections and assignments'} },
    { key:'assignmentsExams', color:'orange', icon:'exam', title:{ar:'الواجبات والاختبارات', fa:'تکالیف و آزمون‌ها', en:'Assignments & Exams'}, desc:{ar:'الواجبات، بنك الأسئلة، الاختبارات والنزاهة', fa:'تکالیف، بانک سوال، آزمون‌ها و سلامت آزمون', en:'Homework, question bank, exams and integrity'} },
    { key:'resources', color:'violet', icon:'archive', title:{ar:'الموارد والمرافق', fa:'منابع و امکانات', en:'Resources & Facilities'}, desc:{ar:'المكتبة، المخزون، الأصول، النقل، المختبرات والوثائق', fa:'کتابخانه، انبار، اموال، حمل‌ونقل، آزمایشگاه و اسناد', en:'Library, inventory, assets, transport, labs and documents'} },
    { key:'people', color:'emerald', icon:'people', title:{ar:'الموارد البشرية والخدمات', fa:'منابع انسانی و خدمات', en:'People & Services'}, desc:{ar:'الموظفون، التسجيلات، التفويضات والإشعارات', fa:'کارکنان، ثبت‌نام‌ها، دسترسی‌ها و اعلان‌ها', en:'HR, registrations, permissions and notifications'} },
    { key:'analyticsAdmin', color:'rose', icon:'chart', title:{ar:'التحليلات وإدارة النظام', fa:'تحلیل و مدیریت سیستم', en:'Analytics & System'}, desc:{ar:'المؤشرات، الإعلانات، الجاهزية والصيانة', fa:'شاخص‌ها، اطلاعیه‌ها، آمادگی و نگهداری', en:'Metrics, announcements, readiness and maintenance'} }
  ];

  const MODULES = [
    {key:'smartCalendar', group:'main', perms:['calendar','student','teacher','parent','staff.dashboard','academic','counseling'], color:'cyan', icon:'calendar', href:'smart-calendar.html?lite=1', title:{ar:'التقويم الذكي',fa:'تقویم هوشمند',en:'Smart Calendar'}, desc:{ar:'تقويم ثلاثي، أجندتي، الإنجازات',fa:'تقویم سه‌گانه، دستورکار من، دستاوردها',en:'Triple calendar, agenda and achievements'}},
    {key:'achievements', group:'main', perms:['achievements','teacher','student','parent','staff.dashboard','academic','users'], color:'gold', icon:'trophy', href:'achievements.html?lite=1', title:{ar:'الإنجازات والشارات',fa:'دستاوردها و نشان‌ها',en:'Achievements & Badges'}, desc:{ar:'شارات تحفيزية للطلاب والمعلمين ولوحة صدارة',fa:'نشان‌های انگیزشی برای دانش‌آموزان و معلمان و جدول برترین‌ها',en:'Motivational badges for students and teachers with leaderboards'}},
    {key:'counselor', group:'people', perms:['counseling','counseling.full'], color:'violet', icon:'heart', href:'counselor.html?lite=1', title:{ar:'الإرشاد النفسي',fa:'مشاوره روان‌شناختی',en:'Psychological Counseling'}, desc:{ar:'حالات الطلاب، جلسات SOAP، أهداف، تنبيهات وقفل خصوصية',fa:'پرونده‌های دانش‌آموزان، جلسات SOAP، اهداف، هشدارها و قفل محرمانگی',en:'Student caseload, SOAP sessions, goals, alerts and privacy lock'}},
    {key:'counselingReport', group:'analyticsAdmin', perm:'counseling.report', color:'teal', icon:'heart', href:'counseling-report.html?lite=1', title:{ar:'تقرير البرنامج التربوي',fa:'گزارش برنامه تربیتی',en:'Educational Program Report'}, desc:{ar:'مؤشرات مجمعة دون أسماء لبرنامج تطوير المهارات',fa:'شاخص‌های تجمیعی بدون نام برای برنامه توسعه مهارت‌ها',en:'Anonymous aggregate indicators for the skills development program'}},
    {key:'staff', group:'main', perm:'staff.dashboard', color:'violet', icon:'grid', href:'staff.html?lite=1', title:{ar:'واجهة الإدارة',fa:'رابط مدیریت',en:'Admin Interface'}, desc:{ar:'لوحة الإدارة التشغيلية حسب صلاحيتك',fa:'داشبورد عملیاتی بر اساس دسترسی شما',en:'Operational admin board by permission'}},
    {key:'super', group:'main', perm:'admin', color:'gold', icon:'crown', href:'super-admin.html?lite=1', badge:'SUPER', title:{ar:'المسؤول الأعلى',fa:'مدیر ارشد',en:'Super Admin'}, desc:{ar:'إدارة شاملة للنظام',fa:'مدیریت کامل سیستم',en:'Full system administration'}},
    {key:'teacher', group:'main', perm:'teacher', color:'emerald', icon:'teacher', href:'teacher.html?lite=1', title:{ar:'لوحة المعلم',fa:'داشبورد معلم',en:'Teacher Board'}, desc:{ar:'حضور، واجبات، درجات، طلاب',fa:'حضور، تکلیف، نمره، دانش‌آموزان',en:'Attendance, homework, grades and students'}},
    {key:'student', group:'main', perm:'student', color:'indigo', icon:'student', href:'student.html?lite=1', title:{ar:'بوابة الطالب',fa:'پورتال دانش‌آموز',en:'Student Portal'}, desc:{ar:'درجات، حضور، واجبات، اختبارات',fa:'نمرات، حضور، تکالیف، آزمون‌ها',en:'Grades, attendance, homework and exams'}},

    {key:'finance', group:'finance', perm:'finance', color:'teal', icon:'wallet', href:'finance-pro.html?lite=1', title:{ar:'النظام المالي',fa:'سیستم مالی',en:'Financial System'}, desc:{ar:'الرسوم، الأقساط، المدفوعات',fa:'شهریه، اقساط، پرداخت‌ها',en:'Fees, installments and payments'}},
    {key:'cashbox', group:'finance', perm:'finance', color:'emerald', icon:'cash', href:'finance-cashbox.html?lite=1', title:{ar:'صندوق اليومية',fa:'صندوق روزانه',en:'Daily Cash'}, desc:{ar:'إغلاق يومي حسب مستلم المبلغ',fa:'بستن روزانه بر اساس دریافت‌کننده',en:'Daily close by receiver'}},
    {key:'receiverReports', group:'finance', perm:'finance', color:'cyan', icon:'receipt', href:'finance-receiver-reports.html?lite=1', title:{ar:'تقارير المستلمين',fa:'گزارش دریافت‌کنندگان',en:'Receiver Reports'}, desc:{ar:'مدفوعات وإلغاء وتدقيق حسب المستلم',fa:'پرداخت، ابطال و حسابرسی بر اساس دریافت‌کننده',en:'Payments, voiding and audit by receiver'}},
    {key:'financeExec', group:'finance', perm:'finance', color:'violet', icon:'chart', href:'finance-executive.html?lite=1', title:{ar:'المركز المالي التنفيذي',fa:'مرکز مالی اجرایی',en:'Executive Finance'}, desc:{ar:'لوحة مالية شاملة وتحليل متأخرات',fa:'داشبورد مالی جامع و تحلیل معوقات',en:'Executive dashboard and overdue analysis'}},
    {key:'collections', group:'finance', perm:'finance', color:'rose', icon:'phone', href:'finance-collections.html?lite=1', title:{ar:'التحصيل والمتابعة',fa:'وصول و پیگیری',en:'Collections'}, desc:{ar:'متأخرات، وعود دفع، تذكيرات',fa:'معوقات، تعهد پرداخت، یادآوری‌ها',en:'Overdues, promises and reminders'}},
    {key:'creditReport', group:'finance', perm:'finance', color:'gold', icon:'credit', href:'finance-credit-report.html?lite=1', title:{ar:'الرصيد الدائن',fa:'مانده بستانکار',en:'Credit Balance'}, desc:{ar:'تقرير المدفوعات الزائدة والرصيد الدائن',fa:'گزارش اضافه پرداخت و مانده بستانکار',en:'Overpayment and credit report'}},
    {key:'financeRules', group:'finance', perm:'finance', color:'slate', icon:'settings', href:'admin-finance-rules.html?lite=1', title:{ar:'قواعد المالية',fa:'قوانین مالی',en:'Finance Rules'}, desc:{ar:'رسوم الصفوف وأسعار المعلمين',fa:'شهریه پایه‌ها و نرخ معلمان',en:'Class fees and teacher rates'}},

    {key:'academic', group:'academic', perm:'academic', color:'indigo', icon:'school', href:'academic-pro.html?lite=1', title:{ar:'النظام الأكاديمي',fa:'سیستم آموزشی',en:'Academic System'}, desc:{ar:'الدرجات، الإعفاءات، التحليلات',fa:'نمرات، معافیت‌ها، تحلیل‌ها',en:'Grades, exemptions and analytics'}},
    {key:'curriculumPlanner', group:'academic', perms:['teacher','academic','schedule'], color:'gold', icon:'book', href:'curriculum-planner.html?lite=1', title:{ar:'مخطط المنهج الذكي',fa:'برنامه‌ریز هوشمند درس',en:'Smart Curriculum Planner'}, desc:{ar:'استيراد المنهج وتوزيعه مع تعديل كامل من المعلم',fa:'وارد کردن درس و توزیع آن با ویرایش کامل معلم',en:'Import and distribute curriculum with full teacher edit control'}},
    {key:'schedule', group:'academic', perm:'schedule', color:'cyan', icon:'calendar', href:'schedule-management.html?lite=1', title:{ar:'الجداول والحصص',fa:'جداول درسی',en:'Timetable & Sessions'}, desc:{ar:'إدارة الجدول وتوليد الجلسات',fa:'مدیریت برنامه و تولید جلسات',en:'Schedule management and session generation'}},
    {key:'sections', group:'academic', perm:'sections', color:'violet', icon:'sections', href:'section-assignment-management.html?lite=1', title:{ar:'الشعب والإسنادات',fa:'کلاس‌ها و تخصیص',en:'Sections & Assignments'}, desc:{ar:'الشعب، الطلاب، إسناد المعلمين',fa:'کلاس‌ها، دانش‌آموزان، تخصیص معلمان',en:'Sections, students and teacher assignments'}},

    {key:'homework', group:'assignmentsExams', perm:'homework', color:'orange', icon:'book', href:'student-homeworks.html?lite=1', title:{ar:'الواجبات',fa:'تکالیف',en:'Assignments'}, desc:{ar:'واجبات وتسليمات الطلاب',fa:'تکالیف و ارسال‌های دانش‌آموزان',en:'Homework and submissions'}},
    {key:'homeworkReports', group:'assignmentsExams', perm:'homework.reports', color:'rose', icon:'chart', href:'homework-reports.html?lite=1', title:{ar:'تقارير الواجبات',fa:'گزارش تکالیف',en:'Assignment Reports'}, desc:{ar:'إنجاز، متأخرون، تذكيرات',fa:'انجام‌شده، تأخیرها، یادآوری‌ها',en:'Completion, delays and reminders'}},
    {key:'homeworkAudit', group:'assignmentsExams', perm:'homework.audit', color:'slate', icon:'audit', href:'homework-audit.html?lite=1', title:{ar:'سجل الواجبات',fa:'سابقه تکالیف',en:'Assignment Log'}, desc:{ar:'عمليات وأخطاء الواجبات',fa:'عملیات و خطاهای تکالیف',en:'Homework operations and errors'}},
    {key:'questionBank', group:'assignmentsExams', perm:'question_bank', color:'indigo', icon:'question', href:'teacher-exams.html?lite=1', title:{ar:'بنك الأسئلة',fa:'بانک سوال',en:'Question Bank'}, desc:{ar:'أسئلة واختبارات إلكترونية',fa:'سوال‌ها و آزمون‌های آنلاین',en:'Questions and online exams'}},
    {key:'onlineExams', group:'assignmentsExams', perm:'online_exams', color:'cyan', icon:'exam', href:'online-exams.html?lite=1', title:{ar:'الاختبارات الإلكترونية',fa:'آزمون آنلاین',en:'E-Exams'}, desc:{ar:'دخول الطالب للاختبارات',fa:'ورود دانش‌آموز به آزمون‌ها',en:'Student online exam entry'}},
    {key:'integrity', group:'assignmentsExams', perm:'exam_integrity', color:'rose', icon:'shield', href:'exam-integrity.html?lite=1', title:{ar:'نزاهة الاختبارات',fa:'سلامت آزمون',en:'Exam Integrity'}, desc:{ar:'تشابه، نسخ، مؤشرات AI',fa:'شباهت، کپی، شاخص‌های هوش مصنوعی',en:'Similarity, copy events and AI indicators'}},

    {key:'library', group:'resources', perm:'library', color:'orange', icon:'book', href:'library.html?lite=1', title:{ar:'المكتبة',fa:'کتابخانه',en:'Library'}, desc:{ar:'فهرس وإعارة وحجز',fa:'فهرست، امانت و رزرو',en:'Catalog, loans and reservations'}},
    {key:'inventory', group:'resources', perm:'inventory', color:'violet', icon:'box', href:'inventory.html?lite=1', title:{ar:'المخزون والمشتريات',fa:'انبار و خرید',en:'Inventory & Purchases'}, desc:{ar:'أصناف، موردون، طلبات شراء',fa:'اقلام، تأمین‌کنندگان، سفارش خرید',en:'Items, suppliers and purchase requests'}},
    {key:'assets', group:'resources', perm:'assets', color:'gold', icon:'tag', href:'fixed-assets.html?lite=1', title:{ar:'الأصول والعهد',fa:'اموال و تعهدات',en:'Assets & Custody'}, desc:{ar:'أصول، عهد، صيانة',fa:'اموال، امانت، نگهداری',en:'Assets, custody and maintenance'}},
    {key:'labsActivities', group:'resources', perms:['labs','activities'], color:'teal', icon:'lab', href:'labs-activities.html?lite=1', title:{ar:'المختبرات والأنشطة',fa:'آزمایشگاه‌ها و فعالیت‌ها',en:'Labs & Activities'}, desc:{ar:'مختبرات، تجارب، سلامة وأنشطة مدرسية',fa:'آزمایشگاه، تجربه، ایمنی و فعالیت‌ها',en:'Labs, experiments, safety and activities'}},
    {key:'transport', group:'resources', perm:'transport', color:'cyan', icon:'bus', href:'transportation.html?lite=1', title:{ar:'النقل المدرسي',fa:'حمل‌ونقل مدرسه',en:'School Transport'}, desc:{ar:'حافلات، مسارات، رحلات',fa:'اتوبوس‌ها، مسیرها، سفرها',en:'Buses, routes and trips'}},
    {key:'documents', group:'resources', perm:'documents', color:'indigo', icon:'archive', href:'documents.html?lite=1', title:{ar:'الوثائق والأرشفة',fa:'اسناد و آرشیو',en:'Documents & Archive'}, desc:{ar:'ملفات الطلاب والموظفين والأرشيف',fa:'پرونده‌های دانش‌آموزان، کارکنان و آرشیو',en:'Student, staff files and archive'}},

    {key:'hr', group:'people', perm:'hr', color:'emerald', icon:'people', href:'hr.html?lite=1', title:{ar:'الموارد البشرية',fa:'منابع انسانی',en:'HR'}, desc:{ar:'موظفون، حضور، إجازات، رواتب',fa:'کارکنان، حضور، مرخصی، حقوق',en:'Employees, attendance, leaves and payroll'}},
    {key:'registrations', group:'people', perm:'registrations', color:'gold', icon:'forms', href:'registrations-admin.html?lite=1', title:{ar:'مراجعة التسجيلات',fa:'بررسی ثبت‌نام‌ها',en:'Registration Review'}, desc:{ar:'طلبات أولياء الأمور والمعلمين',fa:'درخواست‌های والدین و معلمان',en:'Parent and teacher applications'}},
    {key:'permissions', group:'people', perm:'users', color:'rose', icon:'lock', href:'permissions-management.html?lite=1', title:{ar:'إدارة التفويضات',fa:'مدیریت دسترسی',en:'Permissions Management'}, desc:{ar:'منح وإلغاء صلاحيات المستخدمين',fa:'اعطا و لغو دسترسی کاربران',en:'Grant and revoke user permissions'}},
    {key:'notifications', group:'people', perm:'notifications', color:'cyan', icon:'bell', href:'notifications.html?lite=1', title:{ar:'الإشعارات',fa:'اعلان‌ها',en:'Notifications'}, desc:{ar:'إشعاراتك الخاصة فقط',fa:'اعلان‌های اختصاصی شما',en:'Your private notifications'}},

    {key:'analytics', group:'analyticsAdmin', perm:'analytics', color:'violet', icon:'chart', href:'analytics-center.html?lite=1', title:{ar:'مركز التحليلات',fa:'مرکز تحلیل',en:'Analytics Center'}, desc:{ar:'مؤشرات المؤسسة والتنبيهات الذكية',fa:'شاخص‌های سازمان و هشدارهای هوشمند',en:'Institution KPIs and smart alerts'}},
    {key:'announcements', group:'analyticsAdmin', perm:'announcements', color:'rose', icon:'megaphone', href:'announcements.html?lite=1', title:{ar:'الإعلانات الجماعية',fa:'اطلاعیه‌های گروهی',en:'Announcements'}, desc:{ar:'نشر إعلان وإرساله كإشعار',fa:'انتشار اطلاعیه و ارسال به‌صورت اعلان',en:'Publish announcement as notification'}},
    {key:'finalReadiness', group:'analyticsAdmin', perm:'system', color:'emerald', icon:'check', href:'final-readiness.html?lite=1', title:{ar:'جاهزية النظام',fa:'آمادگی سیستم',en:'System Readiness'}, desc:{ar:'فحص نهائي للوحدات والصفحات وRLS',fa:'بررسی نهایی ماژول‌ها، صفحات و RLS',en:'Final modules, pages and RLS check'}},
    {key:'securityGovernance', group:'analyticsAdmin', perms:['system','admin'], color:'rose', icon:'shield', href:'security-governance.html?lite=1', title:{ar:'حوكمة الأمن',fa:'حاکمیت امنیت',en:'Security Governance'}, desc:{ar:'فحص مركزي للصلاحيات وRLS وكلمات المرور',fa:'بررسی مرکزی دسترسی‌ها، RLS و رمزها',en:'Central checks for permissions, RLS and passwords'}},
    {key:'system', group:'analyticsAdmin', perm:'system', color:'slate', icon:'settings', href:'system-maintenance.html?lite=1', title:{ar:'صيانة النظام',fa:'نگهداری سیستم',en:'System Maintenance'}, desc:{ar:'فحص صحة النظام والتنظيف',fa:'بررسی سلامت سیستم و پاکسازی',en:'Health check and cleanup'}}
  ];

  const iconPaths = {
    grid:'M4 5h7v7H4zM13 5h7v7h-7zM4 14h7v5H4zM13 14h7v5h-7z',
    calendar:'M7 3v3M17 3v3M4 8h16M6 5h12a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z',
    crown:'M4 8l4 4 4-7 4 7 4-4v10H4z',
    teacher:'M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4 21a8 8 0 0 1 16 0M18 8h3v8h-3',
    student:'M12 3 3 8l9 5 9-5-9-5zM6 11v5c2 2 10 2 12 0v-5',
    wallet:'M4 7h15a1 1 0 0 1 1 1v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h12M16 12h5v4h-5a2 2 0 0 1 0-4z',
    cash:'M4 7h16v10H4zM8 11h.01M16 13h.01M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z',
    receipt:'M6 3h12v18l-3-2-3 2-3-2-3 2zM9 8h6M9 12h6M9 16h4',
    chart:'M4 19V5M8 17v-6M12 17V8M16 17v-4M20 19H4',
    phone:'M7 4h4l2 5-3 2a13 13 0 0 0 5 5l2-3 5 2v4c0 1-1 2-2 2A18 18 0 0 1 5 6c0-1 1-2 2-2z',
    credit:'M4 6h16v12H4zM4 10h16M8 15h5',
    settings:'M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8zM4 12h2M18 12h2M12 4v2M12 18v2M6.3 6.3l1.4 1.4M16.3 16.3l1.4 1.4M17.7 6.3l-1.4 1.4M7.7 16.3l-1.4 1.4',
    school:'M3 10l9-6 9 6-9 6zM6 13v5h12v-5M9 18v-3h6v3',
    sections:'M5 5h6v6H5zM13 5h6v6h-6zM5 13h6v6H5zM13 13h6v6h-6z',
    book:'M5 4h10a4 4 0 0 1 4 4v12H8a3 3 0 0 1-3-3zM5 4v13a3 3 0 0 0 3 3M9 8h6M9 12h6',
    audit:'M7 3h10v18H7zM9 7h6M9 11h6M9 15h3M16 15l3 3 4-6',
    question:'M12 17h.01M9.5 9a2.5 2.5 0 1 1 4.2 1.8c-1.5 1.1-1.7 1.7-1.7 3.2M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20z',
    exam:'M6 3h9l3 3v15H6zM14 3v4h4M9 12h6M9 16h6',
    shield:'M12 3l8 4v5c0 5-3.5 8-8 9-4.5-1-8-4-8-9V7zM9 12l2 2 4-5',
    box:'M4 8l8-4 8 4-8 4zM4 8v8l8 4 8-4V8M12 12v8',
    tag:'M4 6v6l8 8 8-8-8-8H6a2 2 0 0 0-2 2zM8 8h.01',
    lab:'M9 3h6M10 3v6l-5 9a2 2 0 0 0 2 3h10a2 2 0 0 0 2-3l-5-9V3M8 15h8',
    bus:'M6 4h12a2 2 0 0 1 2 2v10H4V6a2 2 0 0 1 2-2zM4 11h16M7 18h.01M17 18h.01M7 20h2M15 20h2',
    archive:'M4 5h16v4H4zM6 9h12v10H6zM9 13h6',
    people:'M8 11a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM16 11a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM3 21a5 5 0 0 1 10 0M11 21a5 5 0 0 1 10 0',
    heart:'M20.8 5.6a5.2 5.2 0 0 0-7.4 0L12 7l-1.4-1.4a5.2 5.2 0 0 0-7.4 7.4L12 21l8.8-8a5.2 5.2 0 0 0 0-7.4z',
    leaf:'M20 4c-7 0-12 5-12 12 0 3 2 5 5 5 7 0 7-10 7-17zM4 20c3-6 7-9 13-12',
    pulse:'M4 13h4l2-6 4 12 2-6h4',
    forms:'M6 3h12v18H6zM9 8h6M9 12h6M9 16h4',
    lock:'M7 10V8a5 5 0 0 1 10 0v2M6 10h12v10H6zM12 14v3',
    bell:'M12 22a2 2 0 0 0 2-2h-4a2 2 0 0 0 2 2zM5 17h14l-2-3V9a5 5 0 0 0-10 0v5z',
    megaphone:'M4 13V9h4l9-4v12l-9-4zM8 13l2 6h3l-2-6M19 9l2-2M19 13l2 2',
    trophy:'M8 4h8v3h4a4 4 0 0 1-4 4h-.5A5.5 5.5 0 0 1 13 15.3V18h3v2H8v-2h3v-2.7A5.5 5.5 0 0 1 8.5 11H8a4 4 0 0 1-4-4h4zM8 7H6a2 2 0 0 0 2 2M16 7h2a2 2 0 0 1-2 2M8 4v5a4 4 0 0 0 8 0V4',
    medal:'M12 15a5 5 0 1 0 0-10 5 5 0 0 0 0 10zM9 14l-2 7 5-3 5 3-2-7M10 3L8 1M14 3l2-2',
    star:'M12 3l2.8 5.7 6.2.9-4.5 4.4 1.1 6.1L12 17.8 6.4 21l1.1-6.1L3 10.6l6.2-.9z',
    sparkle:'M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8zM19 16l.9 2.1L22 19l-2.1.9L19 22l-.9-2.1L16 19l2.1-.9z',
    check:'M20 6L9 17l-5-5',
  };

  function lang(){
    const l=(localStorage.getItem('amin_ui_lang')||document.documentElement.lang||'ar').slice(0,2).toLowerCase();
    return ['ar','fa','en'].includes(l)?l:'ar';
  }
  function text(obj, fallback){
    if(!obj) return fallback||'';
    const l=lang();
    return obj[l]||obj.ar||obj.en||fallback||'';
  }
  function esc(v){ return String(v==null?'':v).replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m])); }
  function iconSvg(name){
    const d=iconPaths[name]||iconPaths.grid;
    const fillOnly = /^[MLHVCSQTAZmlhvcsqtaz0-9.,\-\s]+$/.test(d) && !d.includes('a') && !d.includes('A') && ['grid'].includes(name);
    if(fillOnly) return `<svg aria-hidden="true" viewBox="0 0 24 24"><path d="${d}" fill="currentColor"></path></svg>`;
    return `<svg aria-hidden="true" viewBox="0 0 24 24"><path d="${d}" fill="none" stroke="currentColor" stroke-width="1.85" stroke-linecap="round" stroke-linejoin="round"></path></svg>`;
  }
  function iconHtml(modOrGroup, cls){
    const color=(modOrGroup&&modOrGroup.color)||'indigo';
    const icon=(modOrGroup&&modOrGroup.icon)||'grid';
    return `<span class="nav-icon-wrap icon-${esc(color)} ${cls||''}">${iconSvg(icon)}</span>`;
  }
  function moduleMatchesPermission(module, hasFn){
    if(!hasFn) return true;
    if(module.perms && module.perms.some(p=>hasFn(p))) return true;
    return hasFn(module.perm);
  }
  function uniqueModules(list){
    const seen=new Set();
    return (list||[]).filter(m=>{
      const key=m.key||m.href||text(m.title);
      if(seen.has(key)) return false;
      seen.add(key);
      return true;
    });
  }
  function searchModules(query, list){
    const q=String(query||'').trim().toLowerCase();
    if(!q) return list||MODULES;
    return (list||MODULES).filter(m=>[
      m.key, m.href, text(m.title), text(m.desc), m.title?.ar, m.title?.fa, m.title?.en, m.desc?.ar, m.desc?.fa, m.desc?.en
    ].join(' ').toLowerCase().includes(q));
  }
  window.AMIN_PLATFORM = {version:'2026.06.prompt-unified', groups:GROUPS, modules:MODULES, lang, text, esc, iconSvg, iconHtml, moduleMatchesPermission, uniqueModules, searchModules};
})();
