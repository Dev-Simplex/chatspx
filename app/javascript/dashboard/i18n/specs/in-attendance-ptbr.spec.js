import fs from 'fs';
import path from 'path';

const readLocale = (locale, file) => {
  const filePath = path.resolve(
    process.cwd(),
    `app/javascript/dashboard/i18n/locale/${locale}/${file}.json`
  );
  return JSON.parse(fs.readFileSync(filePath, 'utf-8'));
};

const flattenKeys = (value, prefix = '', keys = []) => {
  if (!value || typeof value !== 'object') {
    if (prefix) keys.push(prefix);
    return keys;
  }
  Object.entries(value).forEach(([key, nested]) => {
    const nextPrefix = prefix ? `${prefix}.${key}` : key;
    flattenKeys(nested, nextPrefix, keys);
  });
  return keys;
};

// Paridade por SUBÁRVORE (nunca arquivo inteiro): contact.json/settings.json são
// co-propriedade de várias ondas; comparar o arquivo todo acusaria drift alheio.
describe('aba "Em atendimento" pt-BR i18n parity', () => {
  it('keeps CONTACTS_LAYOUT.IN_ATTENDANCE keys aligned between en and pt_BR', () => {
    const en = readLocale('en', 'contact');
    const ptBr = readLocale('pt_BR', 'contact');

    const enKeys = flattenKeys(en.CONTACTS_LAYOUT.IN_ATTENDANCE).sort();
    const ptBrKeys = flattenKeys(ptBr.CONTACTS_LAYOUT.IN_ATTENDANCE).sort();

    expect(enKeys).not.toEqual([]);
    expect(ptBrKeys).toEqual(enKeys);
  });

  it('defines the header title and empty state in both locales', () => {
    const en = readLocale('en', 'contact');
    const ptBr = readLocale('pt_BR', 'contact');

    expect(en.CONTACTS_LAYOUT.HEADER.IN_ATTENDANCE_TITLE).toBeTruthy();
    expect(ptBr.CONTACTS_LAYOUT.HEADER.IN_ATTENDANCE_TITLE).toBeTruthy();
    expect(
      en.CONTACTS_LAYOUT.EMPTY_STATE.IN_ATTENDANCE_EMPTY_STATE_TITLE
    ).toBeTruthy();
    expect(
      ptBr.CONTACTS_LAYOUT.EMPTY_STATE.IN_ATTENDANCE_EMPTY_STATE_TITLE
    ).toBeTruthy();
  });

  it('defines the sidebar label in both locales', () => {
    expect(readLocale('en', 'settings').SIDEBAR.IN_ATTENDANCE).toBeTruthy();
    expect(readLocale('pt_BR', 'settings').SIDEBAR.IN_ATTENDANCE).toBeTruthy();
  });
});
