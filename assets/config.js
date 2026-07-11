(function(){
  'use strict';
  window.AMIN_CONFIG = {
    schoolName: 'مدارس أمين الرضا (ع)',
    supabaseUrl: window.location.origin + '/api',
    supabaseAnonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im92Y2p6c3JxcWdqc2Jxc3d0a3JvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA2MjIxNjIsImV4cCI6MjA5NjE5ODE2Mn0._sPE8K26oTCEGlxBaG_vBk-U2yDNKFV1por5YIv8xko',
    realtimeEnabled: false,
    authStorageKey: 'amin-ovcjzsrqqgjsbqswtkro-auth-v2',
    analyticsEnabled: true,
    analyticsTable: 'ui_analytics_events',
    academicMonths: [9,10,11,12,1,2,3,4,5],
    defaultAttendanceType: 'daily',
    familyRegistrationV3Url: 'https://next-forms-v3.vercel.app/ar/forms/family-registration-v3',
    familyRegistrationV3AutoRedirect: false
  };
}());
