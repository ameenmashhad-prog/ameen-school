"use client";

import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import LanguageSwitcher from '@/components/language-switcher';
import PreviewSheet from '@/components/preview-sheet';
import { buildTemplateByKey } from '@/lib/form-templates';
import { formatDateForLocale, localeDateLabel, localeFontClass, localeMeta } from '@/lib/locale-config';
import { nextVersionStamp } from '@/lib/utils';
import {
  listVersionsRpc,
  requestUploadTicketRpc,
  saveDraftRpc,
  submitTeacherEvaluationRpc,
  uploadAttachmentTransport
} from '@/lib/rpc/forms-rpc';

const LOCAL_LANGUAGE_KEY = 'amin_forms_v3_locale';
const LOCAL_FORM_STATE_KEY = 'amin_forms_v3_teacher_evaluation_state';
const MAX_FILE_SIZE = 10 * 1024 * 1024;

function makeInitialValues(template) {
  return template.fields.reduce((acc, field) => {
    acc[field.id] = field.type === 'file' ? null : '';
    return acc;
  }, {});
}

function SectionCard({ title, subtitle, children }) {
  return (
    <section className="rounded-[24px] border border-slate-200 bg-white p-5 shadow-soft">
      <div className="mb-4 border-b border-slate-100 pb-3">
        <h2 className="text-xl font-black text-slate-950">{title}</h2>
        {subtitle ? <p className="mt-1 text-sm leading-7 text-slate-500">{subtitle}</p> : null}
      </div>
      <div className="grid gap-4 md:grid-cols-2">{children}</div>
    </section>
  );
}

function StatusPill({ tone='slate', children }) {
  const tones={slate:'bg-slate-100 text-slate-700',brand:'bg-brand-50 text-brand-700',success:'bg-emerald-50 text-emerald-700',warning:'bg-amber-50 text-amber-700',danger:'bg-rose-50 text-rose-700'};
  return <span className={`rounded-full px-3 py-1 text-sm font-bold ${tones[tone]||tones.slate}`}>{children}</span>;
}

function InputField({ field, locale, value, error, onChange, labelMap }) {
  const label=field.label?.[locale]||field.id;
  const placeholder=field.placeholder?.[locale]||'';
  const helpText=field.helpText?.[locale];
  const wrapperClass=field.width==='full'?'md:col-span-2':'';
  const baseInputClass=`w-full rounded-2xl border px-3 py-3 text-sm ${error ? 'border-rose-300 bg-rose-50 text-rose-900' : 'border-slate-200 bg-slate-50 text-slate-900'}`;
  const meta=<>{helpText ? <small className="mt-2 block text-xs leading-6 text-slate-500">{helpText}</small> : null}{error ? <small className="mt-2 block text-xs font-bold leading-6 text-rose-600">{error}</small> : null}</>;

  if(field.type==='select') return <label className={`block ${wrapperClass}`}><span className="mb-2 block text-sm font-bold text-slate-800">{label}{field.required?' *':''}</span><select value={value||''} onChange={(e)=>onChange(field.id,e.target.value)} className={baseInputClass}><option value="">{labelMap.selectPlaceholder}</option>{(field.options||[]).map((option)=><option key={option.id} value={option.value}>{option.label?.[locale]||option.value}</option>)}</select>{meta}</label>;
  if(field.type==='file') return <label className={`block ${wrapperClass}`}><span className="mb-2 block text-sm font-bold text-slate-800">{label}{field.required?' *':''}</span><input type="file" accept={field.accept||'*'} onChange={(e)=>{const file=e.target.files?.[0]||null;onChange(field.id,file?{rawFile:file}:null);}} className={`${baseInputClass} border-dashed`} /><small className="mt-2 block text-xs leading-6 text-slate-500">{value?.name||labelMap.fileHint}</small>{error ? <small className="mt-2 block text-xs font-bold leading-6 text-rose-600">{error}</small> : null}</label>;
  if(field.type==='signature') return <label className={`block ${wrapperClass}`}><span className="mb-2 block text-sm font-bold text-slate-800">{label}{field.required?' *':''}</span><input value={value||''} onChange={(e)=>onChange(field.id,e.target.value)} className={baseInputClass} placeholder={placeholder} /><small className="mt-2 block text-xs leading-6 text-slate-500">{labelMap.signatureHint}</small>{error ? <small className="mt-2 block text-xs font-bold leading-6 text-rose-600">{error}</small> : null}</label>;
  if(field.type==='date') return <label className={`block ${wrapperClass}`}><span className="mb-2 block text-sm font-bold text-slate-800">{label}{field.required?' *':''}</span><input type="date" value={value||''} onChange={(e)=>onChange(field.id,e.target.value)} className={baseInputClass} /><small className="mt-2 block text-xs leading-6 text-slate-500">{value ? formatDateForLocale(locale,value) : labelMap.dateHint}</small>{error ? <small className="mt-2 block text-xs font-bold leading-6 text-rose-600">{error}</small> : null}</label>;
  const inputType=field.id==='evaluator_email'?'email':field.id==='score'?'number':'text';
  return <label className={`block ${wrapperClass}`}><span className="mb-2 block text-sm font-bold text-slate-800">{label}{field.required?' *':''}</span><input value={value||''} type={inputType} onChange={(e)=>onChange(field.id,e.target.value)} className={baseInputClass} placeholder={placeholder} />{meta}</label>;
}

function UploadStatusPanel({ labels, uploadTicket, uploadedAttachment, uploadState }) {
  const tone=uploadState==='uploaded'?'success':uploadState==='uploading'?'warning':uploadState==='ready'?'brand':uploadState==='error'?'danger':'slate';
  const statusText=uploadState==='uploaded'?labels.uploadDone:uploadState==='uploading'?labels.uploadingFile:uploadState==='ready'?labels.uploadPrepared:uploadState==='error'?labels.uploadTicketError:labels.uploadTicketPending;
  return <section className="rounded-[24px] border border-slate-200 bg-white p-5 shadow-soft"><div className="mb-3 flex items-center justify-between gap-3"><h3 className="text-lg font-black text-slate-950">{labels.uploadTicketTitle}</h3><StatusPill tone={tone}>{statusText}</StatusPill></div><div className="space-y-3 text-sm text-slate-700"><div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3"><div className="text-xs text-slate-500">{labels.uploadTicketId}</div><div className="mt-1 font-bold text-slate-900">{uploadTicket?.ticketId||'—'}</div></div><div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3"><div className="text-xs text-slate-500">{labels.uploadTicketExpiry}</div><div className="mt-1 font-bold text-slate-900">{uploadTicket?.expiresAtLabel||'—'}</div></div><div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3"><div className="text-xs text-slate-500">{labels.uploadObjectPath}</div><div className="mt-1 break-all font-bold text-slate-900">{uploadedAttachment?.object_path||'—'}</div></div></div><p className="mt-3 text-sm leading-7 text-slate-500">{labels.uploadGuide}</p></section>;
}

function SuccessPanel({ labels, receipt }) {
  if(!receipt)return null;
  return <section className="rounded-[24px] border border-emerald-200 bg-emerald-50 p-5 shadow-soft"><div className="flex flex-wrap items-start justify-between gap-3"><div><h3 className="text-xl font-black text-emerald-800">{labels.submitSuccessTitle}</h3><p className="mt-1 text-sm leading-7 text-emerald-700">{labels.submitSuccess}</p></div><StatusPill tone="success">{receipt.reportId}</StatusPill></div><div className="mt-4 grid gap-3 md:grid-cols-2"><div className="rounded-2xl border border-emerald-200 bg-white px-4 py-3"><div className="text-xs text-slate-500">{labels.submissionReference}</div><div className="mt-1 font-bold text-slate-900">{receipt.reportId}</div></div><div className="rounded-2xl border border-emerald-200 bg-white px-4 py-3"><div className="text-xs text-slate-500">{labels.submittedAt}</div><div className="mt-1 font-bold text-slate-900">{receipt.submittedAtLabel}</div></div></div></section>;
}

function PreviewCard({ title, rows }) {
  return <section className="rounded-[24px] border border-slate-200 bg-white p-5 shadow-soft"><h3 className="mb-4 text-lg font-black text-slate-950">{title}</h3><div className="space-y-3">{rows.map((row)=><div key={row.label} className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3"><div className="text-xs text-slate-500">{row.label}</div><div className="mt-1 font-bold text-slate-900">{row.value||'—'}</div></div>)}</div></section>;
}

function validateValues(template, values, labels, options={}) {
  const errors={};
  const requirePreparedUpload=options.requirePreparedUpload;
  template.fields.forEach((field)=>{
    const value=values[field.id];
    if(field.required){
      if(field.type==='file'&&!value?.name){errors[field.id]=labels.requiredField;return;}
      if(field.type!=='file'&&!String(value||'').trim()){errors[field.id]=labels.requiredField;return;}
    }
    if(field.id==='evaluator_email'&&value){const emailOk=/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(value));if(!emailOk)errors[field.id]=labels.invalidEmail;}
    if(field.id==='score'&&String(value||'').trim()){const n=Number(value);if(!Number.isFinite(n)||n<0||n>100)errors[field.id]=labels.invalidScore;}
    if(field.type==='file'&&value){
      if(value.size>MAX_FILE_SIZE)errors[field.id]=labels.fileTooLarge;
      if(field.accept&&value.name){const accepted=field.accept.split(',').map((item)=>item.trim().toLowerCase());const lowerName=value.name.toLowerCase();const matches=accepted.some((item)=>lowerName.endsWith(item.replace('*','')));if(!matches)errors[field.id]=labels.invalidFileType;}
      if(requirePreparedUpload&&field.id==='evidence_attachment'){errors[field.id]=labels.uploadTicketRequired;}
    }
    if(field.type==='signature'&&value&&String(value).trim().length<3){errors[field.id]=labels.signatureTooShort;}
  });
  return errors;
}

function PrintSheetPreview({ locale, template, values }) {
  const fieldsBySection=template.sections.map((section)=>({...section,fields:template.fields.filter((field)=>field.section===section.key)}));
  return <section className="rounded-[22px] border border-slate-200 bg-white p-5 shadow-sm"><div className="border-b border-slate-100 pb-3 text-center"><div className="text-xs text-slate-500">Amin Forms Studio v3</div><h4 className="mt-2 text-lg font-black text-slate-950">{template.title[locale]}</h4></div><div className="mt-4 space-y-4">{fieldsBySection.map((section)=><div key={section.key} className="rounded-2xl border border-slate-100 p-3"><div className="mb-2 text-sm font-bold text-slate-900">{section.title[locale]}</div><div className="grid gap-2 md:grid-cols-2">{section.fields.map((field)=>{const rawValue=values[field.id];let rendered=rawValue;if(field.type==='date'&&rawValue)rendered=formatDateForLocale(locale,rawValue);if(field.type==='file'&&rawValue?.name)rendered=rawValue.name;if(field.type==='select')rendered=(field.options||[]).find((option)=>option.value===rawValue)?.label?.[locale]||'';return <div key={field.id} className={`rounded-xl bg-slate-50 px-3 py-3 ${field.width==='full'?'md:col-span-2':''}`}><div className="text-[11px] text-slate-500">{field.label?.[locale]}</div><div className="mt-1 font-bold text-slate-900">{rendered||'—'}</div></div>;})}</div></div>)}</div></section>;
}

export default function TeacherEvaluationShell({ locale, dictionary }) {
  const router=useRouter();
  const forms=dictionary.forms;
  const labels=forms.teacherEvaluation;
  const template=useMemo(()=>buildTemplateByKey('teacher_evaluation'),[]);
  const [activeLocale,setActiveLocale]=useState(locale);
  const [values,setValues]=useState(()=>makeInitialValues(template));
  const [errors,setErrors]=useState({});
  const [saveState,setSaveState]=useState('idle');
  const [submitState,setSubmitState]=useState('idle');
  const [versions,setVersions]=useState([]);
  const [receipt,setReceipt]=useState(null);
  const [uploadTicket,setUploadTicket]=useState(null);
  const [uploadedAttachment,setUploadedAttachment]=useState(null);
  const [uploadState,setUploadState]=useState('idle');
  const [fileObjects,setFileObjects]=useState({});
  const meta=localeMeta[activeLocale]||localeMeta.ar;

  useEffect(()=>{const remembered=window.localStorage.getItem(LOCAL_LANGUAGE_KEY);if(remembered&&localeMeta[remembered])setActiveLocale(remembered);const raw=window.localStorage.getItem('amin_forms_v3_teacher_evaluation_state');if(raw){try{const parsed=JSON.parse(raw);if(parsed?.values)setValues(parsed.values);if(parsed?.receipt)setReceipt(parsed.receipt);if(parsed?.uploadTicket)setUploadTicket(parsed.uploadTicket);if(parsed?.uploadedAttachment)setUploadedAttachment(parsed.uploadedAttachment);}catch(error){console.error(error);}}},[]);
  useEffect(()=>{window.localStorage.setItem(LOCAL_LANGUAGE_KEY,activeLocale);document.documentElement.lang=activeLocale;document.documentElement.dir=meta.dir;},[activeLocale,meta.dir]);
  useEffect(()=>{let cancelled=false;async function loadVersions(){try{const result=await listVersionsRpc({form_slug:template.slug});if(cancelled)return;setVersions(result?.data?.versions||result?.versions||[]);}catch(error){console.error(error);}}loadVersions();return()=>{cancelled=true;};},[template.slug]);
  useEffect(()=>{const timer=setInterval(async()=>{persistLocal(values,receipt,uploadTicket,uploadedAttachment);setSaveState('saving');try{await saveDraftRpc({form_slug:template.slug,locale:activeLocale,version_label:nextVersionStamp(),visibility:template.visibility,schema:template,form_values:values,autosave:true});setSaveState('saved');}catch(error){console.error(error);setSaveState('error');}},15000);return()=>clearInterval(timer);},[values,receipt,uploadTicket,uploadedAttachment,template,activeLocale]);
  const fieldsBySection=useMemo(()=>template.sections.map((section)=>({...section,fields:template.fields.filter((field)=>field.section===section.key)})),[template]);
  const requiredFields=useMemo(()=>template.fields.filter((field)=>field.required),[template]);
  const requiredDone=requiredFields.filter((field)=>{const value=values[field.id];if(field.type==='file')return !!value?.name;return String(value||'').trim().length>0;}).length;
  const validation=useMemo(()=>validateValues(template,values,labels,{requirePreparedUpload:Boolean(values.evidence_attachment?.name&&!uploadTicket)}),[template,values,labels,uploadTicket]);
  function persistLocal(nextValues,nextReceipt=receipt,nextUploadTicket=uploadTicket,nextAttachment=uploadedAttachment){window.localStorage.setItem('amin_forms_v3_teacher_evaluation_state',JSON.stringify({values:nextValues,receipt:nextReceipt,uploadTicket:nextUploadTicket,uploadedAttachment:nextAttachment}));}
  function setFieldValue(fieldId,value){let normalizedValue=value;if(fieldId==='evidence_attachment'){setFileObjects((current)=>({...current,evidence_attachment:value?.rawFile||null}));normalizedValue=value?.rawFile?{name:value.rawFile.name,size:value.rawFile.size,type:value.rawFile.type,lastModified:value.rawFile.lastModified}:null;setUploadTicket(null);setUploadedAttachment(null);setUploadState('idle');}setValues((current)=>{const next={...current,[fieldId]:normalizedValue};persistLocal(next,receipt,fieldId==='evidence_attachment'?null:uploadTicket,fieldId==='evidence_attachment'?null:uploadedAttachment);return next;});setErrors((current)=>({...current,[fieldId]:undefined}));if(submitState!=='idle')setSubmitState('idle');}
  function resetForm(){const next=makeInitialValues(template);setValues(next);setErrors({});setReceipt(null);setUploadTicket(null);setUploadedAttachment(null);setFileObjects({});setUploadState('idle');persistLocal(next,null,null,null);setSubmitState('idle');}
  async function saveNow(){setSaveState('saving');try{await saveDraftRpc({form_slug:template.slug,locale:activeLocale,version_label:nextVersionStamp(),visibility:template.visibility,schema:template,form_values:values,autosave:false});persistLocal(values);setSaveState('saved');}catch(error){console.error(error);setSaveState('error');}}
  async function prepareUploadTicket(){if(!values.evidence_attachment?.name){setErrors((current)=>({...current,evidence_attachment:labels.requiredField}));return;}setUploadState('loading');try{const result=await requestUploadTicketRpc({form_slug:template.slug,locale:activeLocale,field_id:'evidence_attachment',file_name:values.evidence_attachment.name,content_type:values.evidence_attachment.type||'application/octet-stream',byte_size:values.evidence_attachment.size||0});if(result?.ok===false)throw new Error(result.error||'upload_ticket_failed');const ticketPayload=result?.data||result;const nextTicket={...ticketPayload,ticketId:ticketPayload?.ticket_id||ticketPayload?.upload_token||`UP-${Date.now()}`,expiresAtLabel:ticketPayload?.expires_at?formatDateForLocale(activeLocale,String(ticketPayload.expires_at).slice(0,10)):labels.uploadTicketPending};setUploadTicket(nextTicket);persistLocal(values,receipt,nextTicket,uploadedAttachment);setUploadState('ready');setErrors((current)=>({...current,evidence_attachment:undefined}));}catch(error){console.error(error);setUploadState('error');setErrors((current)=>({...current,evidence_attachment:labels.uploadTicketError}));}}
  async function submitForm(){const needUploadTicket=Boolean(values.evidence_attachment?.name&&!uploadTicket);const nextErrors=validateValues(template,values,labels,{requirePreparedUpload:needUploadTicket});setErrors(nextErrors);if(Object.keys(nextErrors).length){setSubmitState('validation_error');return;}setSubmitState('submitting');const reportId=`TE-${Date.now()}`;try{let attachmentPayload=uploadedAttachment;if(values.evidence_attachment?.name){if(!uploadTicket?.ticketId){setErrors((current)=>({...current,evidence_attachment:labels.uploadTicketRequired}));setSubmitState('validation_error');return;}if(!attachmentPayload){const rawFile=fileObjects.evidence_attachment;if(!rawFile){setErrors((current)=>({...current,evidence_attachment:labels.fileNeedsReselect}));setSubmitState('validation_error');return;}setUploadState('uploading');const uploadResult=await uploadAttachmentTransport({ticketId:uploadTicket.ticketId,formSlug:template.slug,fieldId:'evidence_attachment',file:rawFile});if(uploadResult?.ok===false)throw new Error(uploadResult.error||'upload_failed');attachmentPayload=uploadResult;setUploadedAttachment(uploadResult);setUploadState('uploaded');}}
    const result=await submitTeacherEvaluationRpc({form_slug:template.slug,locale:activeLocale,visibility:template.visibility,submission_ref:reportId,schema:template,values,upload_ticket_id:uploadTicket?.ticketId||null,uploaded_attachment:attachmentPayload?{bucket:attachmentPayload.bucket,object_path:attachmentPayload.object_path,file_name:attachmentPayload.file_name,byte_size:attachmentPayload.byte_size}:null});if(result?.ok===false)throw new Error(result.error||'submit_failed');const submittedAtIso=new Date().toISOString();const nextReceipt={reportId,submittedAt:submittedAtIso,submittedAtLabel:formatDateForLocale(activeLocale,submittedAtIso.slice(0,10)),response:result};setReceipt(nextReceipt);persistLocal(values,nextReceipt,uploadTicket,attachmentPayload||uploadedAttachment);setSubmitState('submitted');const params=new URLSearchParams({ref:reportId,submittedAt:submittedAtIso,locale:activeLocale,applicant:values.teacher_name||''});router.push(`/${activeLocale}/forms/teacher-evaluation/success?${params.toString()}`);}catch(error){console.error(error);setSubmitState('submit_error');setUploadState((current)=>(current==='uploading'?'error':current));}}
  const previewTeacherRows=[{label:labels.fields.teacher_name,value:values.teacher_name},{label:labels.fields.subject_area,value:values.subject_area},{label:labels.fields.evaluator_name,value:values.evaluator_name},{label:labels.fields.evaluation_date,value:values.evaluation_date?formatDateForLocale(activeLocale,values.evaluation_date):''}];
  const previewEvaluationRows=[{label:labels.fields.criteria,value:(template.fields.find((field)=>field.id==='criteria')?.options||[]).find((option)=>option.value===values.criteria)?.label?.[activeLocale]||''},{label:labels.fields.score,value:values.score},{label:labels.fields.strengths,value:values.strengths},{label:labels.fields.improvement_points,value:values.improvement_points},{label:labels.fields.recommendation,value:values.recommendation}];
  return (<main className={`mx-auto min-h-screen max-w-[1480px] px-4 py-6 ${localeFontClass(activeLocale)}`} dir={meta.dir}><section className="rounded-[30px] border border-slate-200 bg-white/90 p-5 shadow-soft"><div className="flex flex-wrap items-start justify-between gap-4 border-b border-slate-200 pb-5"><div><p className="mb-2 text-sm text-slate-500">{forms.builder.badge}</p><h1 className="text-3xl font-black text-slate-950">{labels.pageTitle}</h1><p className="mt-2 max-w-4xl text-sm leading-7 text-slate-600">{labels.pageSubtitle}</p><div className="mt-3 flex flex-wrap gap-2 text-sm"><StatusPill tone="brand">{meta.label}</StatusPill><StatusPill tone="slate">{localeDateLabel(activeLocale)}</StatusPill><StatusPill tone="slate">{labels.visibilityLabel}: {forms.visibility[template.visibility]}</StatusPill></div></div><div className="flex flex-wrap items-center gap-2"><LanguageSwitcher locale={activeLocale} onChange={setActiveLocale} labels={forms.languageSwitcher} /><Link href={`/${activeLocale}/forms/builder`} className="rounded-2xl border border-slate-200 px-4 py-2 font-bold text-slate-700">{labels.openBuilder}</Link><button onClick={()=>window.print()} className="rounded-2xl border border-slate-200 px-4 py-2 font-bold text-slate-700">{labels.printPreview}</button><button onClick={saveNow} className="rounded-2xl border border-slate-200 px-4 py-2 font-bold text-slate-700">{labels.saveNow}</button><button onClick={submitForm} className="rounded-2xl bg-brand-500 px-4 py-2 font-bold text-white">{labels.submit}</button></div></div><div className="mt-5 grid gap-4 xl:grid-cols-[minmax(0,1fr)_420px]"><section className="space-y-4"><div className="rounded-[24px] border border-slate-200 bg-white p-4"><div className="grid gap-3 md:grid-cols-4"><div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm"><div className="text-slate-500">{labels.statusDraft}</div><div className="mt-1 font-bold text-slate-900">{saveState==='saved'?labels.saved:saveState==='saving'?labels.saving:saveState==='error'?labels.saveError:labels.notSavedYet}</div></div><div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm"><div className="text-slate-500">{labels.requiredCoverage}</div><div className="mt-1 font-bold text-slate-900">{requiredDone} / {requiredFields.length}</div></div><div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm"><div className="text-slate-500">{labels.versionCount}</div><div className="mt-1 font-bold text-slate-900">{versions.length}</div></div><div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm"><div className="text-slate-500">{labels.errorCount}</div><div className="mt-1 font-bold text-slate-900">{Object.values(validation).filter(Boolean).length}</div></div></div></div><SuccessPanel labels={labels} receipt={receipt} />{fieldsBySection.map((section)=><SectionCard key={section.key} title={section.title[activeLocale]} subtitle={labels.sectionHints?.[section.key]}>{section.fields.map((field)=><InputField key={field.id} field={field} locale={activeLocale} value={values[field.id]} error={errors[field.id]} onChange={setFieldValue} labelMap={{selectPlaceholder:labels.selectPlaceholder,fileHint:labels.fileHint,signatureHint:labels.signatureHint,dateHint:labels.dateHint}} />)}</SectionCard>)}<div className="no-print flex flex-wrap gap-3 rounded-[24px] border border-slate-200 bg-white p-4 shadow-soft"><button onClick={resetForm} className="rounded-2xl border border-amber-200 bg-amber-50 px-4 py-2 font-bold text-amber-800">{labels.reset}</button><button onClick={prepareUploadTicket} className="rounded-2xl border border-brand-200 bg-brand-50 px-4 py-2 font-bold text-brand-800">{labels.prepareUpload}</button><button onClick={saveNow} className="rounded-2xl border border-slate-200 px-4 py-2 font-bold text-slate-700">{labels.saveNow}</button><button onClick={submitForm} className="rounded-2xl bg-brand-500 px-4 py-2 font-bold text-white">{labels.submit}</button>{submitState==='validation_error'?<span className="self-center text-sm font-bold text-red-600">{labels.validationError}</span>:null}{submitState==='submitted'?<span className="self-center text-sm font-bold text-brand-700">{labels.submitSuccess}</span>:null}{submitState==='submit_error'?<span className="self-center text-sm font-bold text-red-600">{labels.submitError}</span>:null}{submitState==='submitting'?<span className="self-center text-sm font-bold text-slate-700">{labels.submitting}</span>:null}{uploadState==='uploading'?<span className="self-center text-sm font-bold text-brand-700">{labels.uploadingFile}</span>:null}</div></section><aside className="space-y-4"><UploadStatusPanel labels={labels} uploadTicket={uploadTicket} uploadedAttachment={uploadedAttachment} uploadState={uploadState} /><PreviewCard title={labels.teacherPreviewTitle} rows={previewTeacherRows} /><PreviewCard title={labels.evaluationPreviewTitle} rows={previewEvaluationRows} /><section className="rounded-[24px] border border-slate-200 bg-white p-5 shadow-soft"><h3 className="mb-3 text-lg font-black text-slate-950">{labels.printPreviewTitle}</h3><div className="mb-3 text-xs text-slate-500">{labels.printSheetHint}</div><div className="rounded-2xl border border-slate-100 bg-slate-50 p-3"><div className="mb-3 flex items-center justify-between gap-3 text-xs text-slate-500"><span>{labels.printPaperLabel}</span><StatusPill tone="slate">{template.printOrientation==='landscape'?forms.builder.printModes.landscape:forms.builder.printModes.portrait}</StatusPill></div><div className="scale-[0.97] origin-top"><PrintSheetPreview locale={activeLocale} template={template} values={values} /></div></div><div className="print-only mt-3 rounded-2xl border border-brand-100 bg-brand-50 px-4 py-3 text-sm text-brand-800">{labels.printReceiptBanner}</div></section><section className="rounded-[24px] border border-slate-200 bg-white p-5 shadow-soft no-print"><h3 className="mb-3 text-lg font-black text-slate-950">{labels.versionListTitle}</h3><div className="space-y-2 text-sm text-slate-600">{versions.length?versions.map((version,index)=><div key={version.version_id||version.version_label||index} className="rounded-2xl border border-slate-200 px-3 py-3"><div className="font-bold text-slate-900">{version.version_label||version.label||version.saved_at||'version'}</div><div className="text-xs text-slate-500">{version.saved_at||version.source||'rpc'}</div></div>):<div>{labels.noVersions}</div>}</div></section></aside></div></section></main>);
}
