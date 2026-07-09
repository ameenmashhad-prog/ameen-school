import fs from 'fs/promises';
import path from 'path';
import { isValidLocale } from '@/lib/locale-config';

export async function getDictionary(locale, unit) {
  const safeLocale = isValidLocale(locale) ? locale : 'ar';
  const filePath = path.join(process.cwd(), 'locales', safeLocale, `${unit}.json`);
  const content = await fs.readFile(filePath, 'utf8');
  return JSON.parse(content);
}
