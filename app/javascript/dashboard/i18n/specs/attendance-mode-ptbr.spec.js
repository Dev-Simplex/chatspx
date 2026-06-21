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

describe('Attendance mode pt-BR i18n parity', () => {
  it('keeps GENERAL_SETTINGS.FORM.ATTENDANCE_MODE keys aligned between en and pt_BR', () => {
    const en = readLocale('en', 'generalSettings');
    const ptBr = readLocale('pt_BR', 'generalSettings');

    const enKeys = flattenKeys(en.GENERAL_SETTINGS.FORM.ATTENDANCE_MODE).sort();
    const ptBrKeys = flattenKeys(
      ptBr.GENERAL_SETTINGS.FORM.ATTENDANCE_MODE
    ).sort();

    expect(enKeys.length).toBeGreaterThan(0);
    expect(ptBrKeys).toEqual(enKeys);
  });

  it('keeps NOTIFICATIONS_PAGE.TYPE_LABEL keys aligned between en and pt_BR', () => {
    const en = readLocale('en', 'generalSettings');
    const ptBr = readLocale('pt_BR', 'generalSettings');

    const enKeys = flattenKeys(en.NOTIFICATIONS_PAGE.TYPE_LABEL).sort();
    const ptBrKeys = flattenKeys(ptBr.NOTIFICATIONS_PAGE.TYPE_LABEL).sort();

    expect(enKeys).toContain('conversation_unassignment');
    expect(ptBrKeys).toEqual(enKeys);
  });

  it('keeps PROFILE_SETTINGS.FORM.NOTIFICATIONS.TYPES keys aligned between en and pt_BR', () => {
    const en = readLocale('en', 'settings');
    const ptBr = readLocale('pt_BR', 'settings');

    const enKeys = flattenKeys(
      en.PROFILE_SETTINGS.FORM.NOTIFICATIONS.TYPES
    ).sort();
    const ptBrKeys = flattenKeys(
      ptBr.PROFILE_SETTINGS.FORM.NOTIFICATIONS.TYPES
    ).sort();

    expect(enKeys).toContain('CONVERSATION_UNASSIGNED');
    expect(ptBrKeys).toEqual(enKeys);
  });

  it('keeps the new strings actually translated in pt_BR', () => {
    const enGeneral = readLocale('en', 'generalSettings');
    const ptBrGeneral = readLocale('pt_BR', 'generalSettings');
    const enSettings = readLocale('en', 'settings');
    const ptBrSettings = readLocale('pt_BR', 'settings');

    const enMode = enGeneral.GENERAL_SETTINGS.FORM.ATTENDANCE_MODE;
    const ptBrMode = ptBrGeneral.GENERAL_SETTINGS.FORM.ATTENDANCE_MODE;

    expect(ptBrMode.TITLE).not.toEqual(enMode.TITLE);
    expect(ptBrMode.CLASSIC.DESCRIPTION).not.toEqual(
      enMode.CLASSIC.DESCRIPTION
    );
    expect(ptBrMode.GATED.DESCRIPTION).not.toEqual(enMode.GATED.DESCRIPTION);
    expect(ptBrMode.CONFIRM.GATED.TITLE).not.toEqual(
      enMode.CONFIRM.GATED.TITLE
    );
    expect(ptBrMode.CONFIRM.CLASSIC.TITLE).not.toEqual(
      enMode.CONFIRM.CLASSIC.TITLE
    );

    expect(
      ptBrGeneral.NOTIFICATIONS_PAGE.TYPE_LABEL.conversation_unassignment
    ).not.toEqual(
      enGeneral.NOTIFICATIONS_PAGE.TYPE_LABEL.conversation_unassignment
    );
    expect(
      ptBrSettings.PROFILE_SETTINGS.FORM.NOTIFICATIONS.TYPES
        .CONVERSATION_UNASSIGNED
    ).not.toEqual(
      enSettings.PROFILE_SETTINGS.FORM.NOTIFICATIONS.TYPES
        .CONVERSATION_UNASSIGNED
    );
  });
});
