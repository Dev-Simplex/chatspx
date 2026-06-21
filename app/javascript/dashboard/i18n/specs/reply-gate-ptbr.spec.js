import fs from 'fs';
import path from 'path';

const readLocale = (locale, file = 'conversation') => {
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

// Parity by SUBTREE (never full-file): conversation.json is co-owned by several
// waves; comparing whole files would flag unrelated drift.
describe('reply gate (D-L2) pt-BR i18n parity', () => {
  const en = readLocale('en');
  const ptBr = readLocale('pt_BR');

  it('keeps REPLY_GATE_DIALOG keys aligned between en and pt_BR', () => {
    const enKeys = flattenKeys(en.CONVERSATION.REPLY_GATE_DIALOG).sort();
    const ptBrKeys = flattenKeys(ptBr.CONVERSATION.REPLY_GATE_DIALOG).sort();
    expect(ptBrKeys).toEqual(enKeys);
  });

  it('keeps REPLY_GATE_BANNER keys aligned between en and pt_BR', () => {
    const enKeys = flattenKeys(en.CONVERSATION.REPLY_GATE_BANNER).sort();
    const ptBrKeys = flattenKeys(ptBr.CONVERSATION.REPLY_GATE_BANNER).sort();
    expect(ptBrKeys).toEqual(enKeys);
  });

  it('translates the 4 dialog variants (en != pt_BR)', () => {
    ['A', 'B', 'C', 'D'].forEach(variant => {
      expect(ptBr.CONVERSATION.REPLY_GATE_DIALOG.TITLE[variant]).not.toEqual(
        en.CONVERSATION.REPLY_GATE_DIALOG.TITLE[variant]
      );
      expect(ptBr.CONVERSATION.REPLY_GATE_DIALOG.CONFIRM[variant]).not.toEqual(
        en.CONVERSATION.REPLY_GATE_DIALOG.CONFIRM[variant]
      );
    });
  });
});
