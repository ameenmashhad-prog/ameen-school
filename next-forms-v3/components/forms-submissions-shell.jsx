"use client";

import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import LanguageSwitcher from '@/components/language-switcher';
import { formatDateForLocale, localeDateLabel, localeFontClass, localeMeta } from '@/lib/locale-config';
import { getSubmissionRpc, listSubmissionsRpc, updateSubmissionStatusRpc } from '@/lib/rpc/forms-rpc';

function Badge({ tone = 'slate', children }) {
  const tones = {
    slate: 'bg-slate-100 text-slate-700',
    blue: 'bg-blue-50 text-blue-700',
    gold: 'bg-amber-50 text-amber-700',
    green: 'bg-emerald-50 text-emerald-700',
    red: 'bg-rose-50 text-rose-700'
  };
  return <span className={`rounded-full px-3 py-1 text-sm font-bold ${tones[tone] || tones.slate}`}>{children}</span>;
}

function statusTone(status) {
  return ({ received:'gold', reviewed:'blue', issued:'green', rejected:'red', archived:'slate' })[status] || 'slate';
}

function statusLabel(status, labels) {
  return labels.statuses?.[status] || status || '—';
}

function csvCell(value) {
  const text = String(value ?? '').replace(/"/g, '""');
  return /[",\n]/.test(text) ? `"${text}"` : text;
}

function downloadCsv(filename, headers, rows) {
  const csv = '\ufeff' + [headers.map(csvCell).join(','), ...rows.map((row) => headers.map((header) => csvCell(row[header])).join(','))].join('\n');
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function SubmissionItem({ item, labels, locale, selected, onSelect }) {
  return (
    <button
      onClick={() => onSelect(item.id)}
      className={`w-full rounded-[22px] border px-4 py-4 text-start transition ${selected ? 'border-brand-500 bg-brand-50' : 'border-slate-200 bg-white hover:border-slate-300'}`}
    >
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <div className="font-black text-slate-950">{item.applicant_name || item.submission_ref}</div>
          <div className="mt-1 text-sm text-slate-500">{item.form_slug} · {formatDateForLocale(locale, String(item.created_at).slice(0, 10))}</div>
          <div className="mt-1 text-xs text-slate-500">{item.guardian_name || labels.noGuardian}</div>
        </div>
        <Badge tone={statusTone(item.status)}>{statusLabel(item.status, labels)}</Badge>
      </div>
    </button>
  );
}

function buildSections(detail, locale, labels) {
  const schema = detail?.schema_snapshot || {};
  const values = detail?.submission_values || {};
  const sections = schema.sections || [];
  const fields = schema.fields || [];

  return sections.map((section) => ({
    key: section.key,
    title: section.title?.[locale] || section.key,
    rows: fields.filter((field) => field.section === section.key).map((field) => {
      let value = values[field.id];
      if (field.type === 'select') value = (field.options || []).find((option) => option.value === value)?.label?.[locale] || value;
      if (field.type === 'date' && value) value = formatDateForLocale(locale, value);
      if (field.type === 'file' && value?.name) value = value.name;
      return { label: field.label?.[locale] || field.id, value: value || labels.emptyValue };
    })
  })).filter((section) => section.rows.length);
}

export default function FormsSubmissionsShell({ locale, dictionary }) {
  const forms = dictionary.forms;
  const labels = forms.submissions;
  const [activeLocale, setActiveLocale] = useState(locale);
  const [items, setItems] = useState([]);
  const [selectedId, setSelectedId] = useState(null);
  const [detail, setDetail] = useState(null);
  const [loading, setLoading] = useState(true);
  const [detailLoading, setDetailLoading] = useState(false);
  const [actionState, setActionState] = useState('idle');
  const [reviewNote, setReviewNote] = useState('');
  const [filters, setFilters] = useState({ formSlug: '', visibility: 'all', status: 'all', search: '', from: '', to: '' });
  const meta = localeMeta[activeLocale] || localeMeta.ar;

  useEffect(() => {
    document.documentElement.lang = activeLocale;
    document.documentElement.dir = meta.dir;
  }, [activeLocale, meta.dir]);

  async function loadSubmissions() {
    setLoading(true);
    try {
      const result = await listSubmissionsRpc({
        p_form_slug: filters.formSlug || null,
        p_visibility: filters.visibility === 'all' ? null : filters.visibility,
        p_status: filters.status === 'all' ? null : filters.status,
        p_created_from: filters.from || null,
        p_created_to: filters.to || null,
        p_limit: 100
      });
      const nextItems = result?.data?.items || result?.items || [];
      setItems(nextItems);
      setSelectedId((current) => current && nextItems.some((item) => item.id === current) ? current : nextItems[0]?.id || null);
    } catch (error) {
      console.error(error);
      setItems([]);
      setSelectedId(null);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    loadSubmissions();
  }, [filters.formSlug, filters.visibility, filters.status, filters.from, filters.to]);

  useEffect(() => {
    if (!selectedId) {
      setDetail(null);
      setReviewNote('');
      return;
    }
    let cancelled = false;
    setDetailLoading(true);
    getSubmissionRpc({ p_submission_id: selectedId })
      .then((result) => {
        if (cancelled) return;
        const item = result?.data?.item || result?.item || null;
        setDetail(item);
        setReviewNote(item?.review_note || '');
      })
      .catch((error) => {
        console.error(error);
        if (!cancelled) {
          setDetail(null);
          setReviewNote('');
        }
      })
      .finally(() => {
        if (!cancelled) setDetailLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [selectedId]);

  async function updateStatus(nextStatus) {
    if (!selectedId) return;
    setActionState('saving');
    try {
      await updateSubmissionStatusRpc({
        p_submission_id: selectedId,
        p_status: nextStatus,
        p_review_note: reviewNote || null
      });
      await loadSubmissions();
      const refreshed = await getSubmissionRpc({ p_submission_id: selectedId });
      const item = refreshed?.data?.item || refreshed?.item || null;
      setDetail(item);
      setReviewNote(item?.review_note || '');
      setActionState('saved');
    } catch (error) {
      console.error(error);
      setActionState('error');
    }
  }

  const filteredItems = useMemo(() => {
    const query = String(filters.search || '').trim().toLowerCase();
    if (!query) return items;
    return items.filter((item) => [item.applicant_name, item.guardian_name, item.submission_ref, item.form_slug].join(' ').toLowerCase().includes(query));
  }, [items, filters.search]);

  const kpis = useMemo(() => {
    const by = (key) => filteredItems.filter((item) => item.status === key).length;
    return {
      total: filteredItems.length,
      received: by('received'),
      reviewed: by('reviewed'),
      issued: by('issued')
    };
  }, [filteredItems]);

  const sections = useMemo(() => buildSections(detail, activeLocale, labels), [detail, activeLocale, labels]);

  function exportCurrentCsv() {
    if (!filteredItems.length) return;
    const rows = filteredItems.map((item) => ({
      submission_ref: item.submission_ref,
      form_slug: item.form_slug,
      visibility: item.visibility,
      status: item.status,
      applicant_name: item.applicant_name,
      guardian_name: item.guardian_name,
      created_at: item.created_at
    }));
    downloadCsv('forms-v3-submissions.csv', ['submission_ref','form_slug','visibility','status','applicant_name','guardian_name','created_at'], rows);
  }

  function printDetail() {
    window.print();
  }

  return (
    <main className={`mx-auto min-h-screen max-w-[1500px] px-4 py-6 ${localeFontClass(activeLocale)}`} dir={meta.dir}>
      <section className="rounded-[30px] border border-slate-200 bg-white/90 p-5 shadow-soft">
        <div className="flex flex-wrap items-start justify-between gap-4 border-b border-slate-200 pb-5">
          <div>
            <p className="mb-2 text-sm text-slate-500">{forms.builder.badge}</p>
            <h1 className="text-3xl font-black text-slate-950">{labels.pageTitle}</h1>
            <p className="mt-2 max-w-4xl text-sm leading-7 text-slate-600">{labels.pageSubtitle}</p>
            <div className="mt-3 flex flex-wrap gap-2 text-sm">
              <Badge tone="blue">{meta.label}</Badge>
              <Badge>{localeDateLabel(activeLocale)}</Badge>
            </div>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <LanguageSwitcher locale={activeLocale} onChange={setActiveLocale} labels={forms.languageSwitcher} />
            <Link href={`/${activeLocale}/forms/student-registration`} className="rounded-2xl border border-slate-200 px-4 py-2 font-bold text-slate-700">{labels.openStudentForm}</Link>
            <button onClick={exportCurrentCsv} className="rounded-2xl border border-slate-200 px-4 py-2 font-bold text-slate-700">{labels.actions.exportCsv}</button>
          </div>
        </div>

        <div className="mt-5 grid gap-3 md:grid-cols-4">
          <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4"><div className="text-xs text-slate-500">{labels.kpis.total}</div><div className="mt-2 font-black text-slate-900">{kpis.total}</div></div>
          <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4"><div className="text-xs text-slate-500">{labels.kpis.received}</div><div className="mt-2 font-black text-slate-900">{kpis.received}</div></div>
          <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4"><div className="text-xs text-slate-500">{labels.kpis.reviewed}</div><div className="mt-2 font-black text-slate-900">{kpis.reviewed}</div></div>
          <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4"><div className="text-xs text-slate-500">{labels.kpis.issued}</div><div className="mt-2 font-black text-slate-900">{kpis.issued}</div></div>
        </div>

        <div className="mt-5 grid gap-4 xl:grid-cols-[380px_minmax(0,1fr)]">
          <aside className="space-y-4 rounded-[24px] border border-slate-200 bg-slate-50 p-4">
            <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-1">
              <input className="rounded-2xl border border-slate-200 bg-white px-3 py-3 text-sm" placeholder={labels.filters.search} value={filters.search} onChange={(e) => setFilters((c) => ({ ...c, search: e.target.value }))} />
              <input className="rounded-2xl border border-slate-200 bg-white px-3 py-3 text-sm" placeholder={labels.filters.formSlug} value={filters.formSlug} onChange={(e) => setFilters((c) => ({ ...c, formSlug: e.target.value }))} />
              <select className="rounded-2xl border border-slate-200 bg-white px-3 py-3 text-sm" value={filters.visibility} onChange={(e) => setFilters((c) => ({ ...c, visibility: e.target.value }))}>
                <option value="all">{labels.filters.allVisibilities}</option>
                <option value="public">{forms.visibility.public}</option>
                <option value="administrative">{forms.visibility.administrative}</option>
                <option value="finance_admin">{forms.visibility.finance_admin}</option>
              </select>
              <select className="rounded-2xl border border-slate-200 bg-white px-3 py-3 text-sm" value={filters.status} onChange={(e) => setFilters((c) => ({ ...c, status: e.target.value }))}>
                <option value="all">{labels.filters.allStatuses}</option>
                <option value="received">{labels.statuses.received}</option>
                <option value="reviewed">{labels.statuses.reviewed}</option>
                <option value="issued">{labels.statuses.issued}</option>
                <option value="rejected">{labels.statuses.rejected}</option>
                <option value="archived">{labels.statuses.archived}</option>
              </select>
              <input type="date" className="rounded-2xl border border-slate-200 bg-white px-3 py-3 text-sm" value={filters.from} onChange={(e) => setFilters((c) => ({ ...c, from: e.target.value }))} />
              <input type="date" className="rounded-2xl border border-slate-200 bg-white px-3 py-3 text-sm" value={filters.to} onChange={(e) => setFilters((c) => ({ ...c, to: e.target.value }))} />
            </div>

            <div className="flex flex-wrap gap-2 no-print">
              <button onClick={() => setFilters({ formSlug:'', visibility:'all', status:'all', search:'', from:'', to:'' })} className="rounded-2xl border border-slate-200 bg-white px-4 py-2 text-sm font-bold text-slate-700">{labels.actions.resetFilters}</button>
              <button onClick={loadSubmissions} className="rounded-2xl border border-brand-200 bg-brand-50 px-4 py-2 text-sm font-bold text-brand-800">{labels.actions.refresh}</button>
            </div>

            <div className="space-y-3">
              {loading ? <div className="rounded-2xl border border-slate-200 bg-white px-4 py-6 text-sm text-slate-500">{labels.loading}</div> : null}
              {!loading && !filteredItems.length ? <div className="rounded-2xl border border-dashed border-slate-300 bg-white px-4 py-6 text-sm text-slate-500">{labels.empty}</div> : null}
              {!loading && filteredItems.map((item) => (
                <SubmissionItem key={item.id} item={item} labels={labels} locale={activeLocale} selected={item.id === selectedId} onSelect={setSelectedId} />
              ))}
            </div>
          </aside>

          <section className="space-y-4">
            {!selectedId ? (
              <div className="rounded-[24px] border border-dashed border-slate-300 bg-white px-6 py-12 text-center text-sm text-slate-500">{labels.noSelection}</div>
            ) : detailLoading ? (
              <div className="rounded-[24px] border border-slate-200 bg-white px-6 py-12 text-center text-sm text-slate-500">{labels.loadingDetail}</div>
            ) : detail ? (
              <>
                <section className="rounded-[24px] border border-slate-200 bg-white p-5 shadow-soft">
                  <div className="flex flex-wrap items-start justify-between gap-4">
                    <div>
                      <h2 className="text-2xl font-black text-slate-950">{detail.applicant_name || detail.submission_ref}</h2>
                      <p className="mt-2 text-sm text-slate-500">{detail.form_slug} · {formatDateForLocale(activeLocale, String(detail.created_at).slice(0,10))}</p>
                    </div>
                    <Badge tone={statusTone(detail.status)}>{statusLabel(detail.status, labels)}</Badge>
                  </div>
                  <div className="mt-5 grid gap-3 md:grid-cols-2">
                    <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4"><div className="text-xs text-slate-500">{labels.detail.submissionRef}</div><div className="mt-2 font-black text-slate-900">{detail.submission_ref}</div></div>
                    <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4"><div className="text-xs text-slate-500">{labels.detail.visibility}</div><div className="mt-2 font-black text-slate-900">{forms.visibility[detail.visibility] || detail.visibility}</div></div>
                    <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4"><div className="text-xs text-slate-500">{labels.detail.guardian}</div><div className="mt-2 font-black text-slate-900">{detail.guardian_name || labels.emptyValue}</div></div>
                    <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-4"><div className="text-xs text-slate-500">{labels.detail.attachment}</div><div className="mt-2 break-all font-black text-slate-900">{detail.uploaded_attachment?.object_path || labels.emptyValue}</div></div>
                  </div>
                  <div className="mt-5 rounded-2xl border border-slate-200 bg-slate-50 p-4 no-print">
                    <label className="mb-2 block text-sm font-bold text-slate-800">{labels.reviewNote}</label>
                    <textarea value={reviewNote} onChange={(e) => setReviewNote(e.target.value)} className="min-h-24 w-full rounded-2xl border border-slate-200 bg-white px-3 py-3 text-sm text-slate-900" placeholder={labels.reviewNotePlaceholder}></textarea>
                  </div>
                  <div className="mt-5 flex flex-wrap gap-2 no-print">
                    <button onClick={() => updateStatus('reviewed')} className="rounded-2xl border border-blue-200 bg-blue-50 px-4 py-2 text-sm font-bold text-blue-800">{labels.actions.markReviewed}</button>
                    <button onClick={() => updateStatus('issued')} className="rounded-2xl border border-emerald-200 bg-emerald-50 px-4 py-2 text-sm font-bold text-emerald-800">{labels.actions.markIssued}</button>
                    <button onClick={() => updateStatus('rejected')} className="rounded-2xl border border-rose-200 bg-rose-50 px-4 py-2 text-sm font-bold text-rose-800">{labels.actions.markRejected}</button>
                    <button onClick={printDetail} className="rounded-2xl border border-slate-200 px-4 py-2 text-sm font-bold text-slate-700">{labels.actions.print}</button>
                    {actionState === 'saved' ? <span className="self-center text-sm font-bold text-emerald-700">{labels.actions.statusSaved}</span> : null}
                    {actionState === 'error' ? <span className="self-center text-sm font-bold text-rose-700">{labels.actions.statusError}</span> : null}
                  </div>
                </section>

                {sections.map((section) => (
                  <section key={section.key} className="rounded-[24px] border border-slate-200 bg-white p-5 shadow-soft">
                    <h3 className="mb-4 text-lg font-black text-slate-950">{section.title}</h3>
                    <div className="grid gap-3 md:grid-cols-2">
                      {section.rows.map((row) => (
                        <div key={row.label} className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3">
                          <div className="text-xs text-slate-500">{row.label}</div>
                          <div className="mt-2 font-bold text-slate-900">{row.value}</div>
                        </div>
                      ))}
                    </div>
                  </section>
                ))}
              </>
            ) : (
              <div className="rounded-[24px] border border-dashed border-slate-300 bg-white px-6 py-12 text-center text-sm text-slate-500">{labels.loadError}</div>
            )}
          </section>
        </div>
      </section>
    </main>
  );
}
