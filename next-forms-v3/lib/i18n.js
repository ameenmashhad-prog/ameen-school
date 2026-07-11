import fs from 'fs/promises';
import path from 'path';
import { isValidLocale } from '@/lib/locale-config';

async function readLocaleUnit(locale, unit) {
  const safeLocale = isValidLocale(locale) ? locale : 'ar';
  const filePath = path.join(process.cwd(), 'locales', safeLocale, `${unit}.json`);
  const content = await fs.readFile(filePath, 'utf8');
  return JSON.parse(content);
}

export async function getDictionary(locale, unit) {
  return readLocaleUnit(locale, unit);
}

export async function getFormsHomeDictionary(locale) {
  const forms = await readLocaleUnit(locale, 'forms');
  return {
    home: forms.home
  };
}

export async function getFormsPageDictionary(locale, pageKey) {
  const forms = await readLocaleUnit(locale, 'forms');
  return {
    forms: {
      languageSwitcher: forms.languageSwitcher,
      visibility: forms.visibility,
      builder: {
        badge: forms.builder?.badge,
        printModes: forms.builder?.printModes
      },
      [pageKey]: forms[pageKey]
    }
  };
}

export async function getFormsBuilderDictionary(locale) {
  const [forms, reports, finance] = await Promise.all([
    readLocaleUnit(locale, 'forms'),
    readLocaleUnit(locale, 'reports'),
    readLocaleUnit(locale, 'finance')
  ]);

  return { forms, reports, finance };
}

export async function getFormsSuccessDictionary(locale, pageKey) {
  const forms = await readLocaleUnit(locale, 'forms');
  return {
    forms: {
      languageSwitcher: forms.languageSwitcher,
      builder: {
        badge: forms.builder?.badge
      }
    },
    labels: forms[pageKey]
  };
}
