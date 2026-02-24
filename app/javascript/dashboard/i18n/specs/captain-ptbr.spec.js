import fs from 'fs';
import path from 'path';

const readLocale = (locale, file = 'settings') => {
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

describe('Captain pt-BR i18n parity', () => {
  it('keeps CAPTAIN_SETTINGS keys aligned between en and pt_BR', () => {
    const enSettings = readLocale('en', 'settings');
    const ptBrSettings = readLocale('pt_BR', 'settings');

    const enKeys = flattenKeys(enSettings.CAPTAIN_SETTINGS).sort();
    const ptBrKeys = flattenKeys(ptBrSettings.CAPTAIN_SETTINGS).sort();

    expect(ptBrKeys).toEqual(enKeys);
  });

  it('keeps key Captain strings translated for assistant switcher and scenarios', () => {
    const enIntegrations = readLocale('en', 'integrations');
    const ptBrIntegrations = readLocale('pt_BR', 'integrations');

    expect(
      ptBrIntegrations.CAPTAIN.ASSISTANT_SWITCHER.SWITCH_ASSISTANT
    ).not.toEqual(enIntegrations.CAPTAIN.ASSISTANT_SWITCHER.SWITCH_ASSISTANT);
    expect(ptBrIntegrations.CAPTAIN.ASSISTANT_SWITCHER.NEW_ASSISTANT).not.toEqual(
      enIntegrations.CAPTAIN.ASSISTANT_SWITCHER.NEW_ASSISTANT
    );
    expect(ptBrIntegrations.CAPTAIN.ASSISTANT_SWITCHER.EMPTY_LIST).not.toEqual(
      enIntegrations.CAPTAIN.ASSISTANT_SWITCHER.EMPTY_LIST
    );

    expect(
      ptBrIntegrations.CAPTAIN.ASSISTANTS.SCENARIOS.ADD.SUGGESTED.EXAMPLES
        .PROSPECTIVE_BUYER.TITLE
    ).not.toEqual(
      enIntegrations.CAPTAIN.ASSISTANTS.SCENARIOS.ADD.SUGGESTED.EXAMPLES
        .PROSPECTIVE_BUYER.TITLE
    );
    expect(
      ptBrIntegrations.CAPTAIN.ASSISTANTS.SCENARIOS.ADD.SUGGESTED.EXAMPLES
        .PROSPECTIVE_BUYER.DESCRIPTION
    ).not.toEqual(
      enIntegrations.CAPTAIN.ASSISTANTS.SCENARIOS.ADD.SUGGESTED.EXAMPLES
        .PROSPECTIVE_BUYER.DESCRIPTION
    );
    expect(
      ptBrIntegrations.CAPTAIN.ENTERPRISE_PAYWALL.AVAILABLE_ON
    ).toBeTruthy();
  });
});
