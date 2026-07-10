"use client";

import { usePathname, useRouter, useSearchParams } from 'next/navigation';

export default function LanguageSwitcher({ locale, onChange, labels }) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();

  function buildLocalizedPath(code) {
    if (!pathname) return null;
    const segments = pathname.split('/').filter(Boolean);
    if (segments.length && ['ar', 'fa', 'en'].includes(segments[0])) {
      segments[0] = code;
    } else {
      segments.unshift(code);
    }
    const nextPath = `/${segments.join('/')}`;
    const query = searchParams?.toString();
    return query ? `${nextPath}?${query}` : nextPath;
  }

  function handleChange(code) {
    try {
      window.localStorage.setItem('amin_forms_v3_locale', code);
    } catch (error) {
      console.error(error);
    }

    if (typeof onChange === 'function') {
      onChange(code);
    }

    const nextPath = buildLocalizedPath(code);
    if (nextPath && nextPath !== `${pathname}${searchParams?.toString() ? `?${searchParams.toString()}` : ''}`) {
      router.push(nextPath);
    }
  }

  return (
    <div className="flex overflow-hidden rounded-2xl border border-slate-200 bg-white">
      {['ar', 'fa', 'en'].map((code) => (
        <button
          key={code}
          onClick={() => handleChange(code)}
          className={`px-4 py-2 text-sm font-bold transition ${locale === code ? 'bg-brand-500 text-white' : 'text-slate-600 hover:bg-slate-50'}`}
        >
          {labels[code]}
        </button>
      ))}
    </div>
  );
}
