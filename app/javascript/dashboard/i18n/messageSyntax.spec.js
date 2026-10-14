import { createI18n } from 'vue-i18n';

// Every text is compiled by the same vue-i18n the screen uses. A loose "@" or
// "{{ }}" does not compile: in production t() throws SyntaxError and that part
// of the screen does not render. In tests vue-i18n only logs the compilation
// error with console.error, so the spy is what catches it.
const sources = import.meta.glob(
  [
    './locale/{en,pt_BR}/*.json',
    '../../widget/i18n/locale/{en,pt_BR}.json',
    '../../survey/i18n/locale/{en,pt_BR}.json',
    '../../suggestions/i18n/{en,pt_BR}.json',
  ],
  { eager: true, import: 'default' }
);

const leafKeys = (value, prefix = '') =>
  Object.entries(value).flatMap(([key, entry]) => {
    const path = prefix ? `${prefix}.${key}` : key;
    return entry !== null && typeof entry === 'object'
      ? leafKeys(entry, path)
      : [path];
  });

const brokenKeys = messages => {
  const i18n = createI18n({
    legacy: false,
    locale: 'en',
    messages: { en: messages },
    missingWarn: false,
    fallbackWarn: false,
  });
  const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
  const broken = leafKeys(messages).filter(key => {
    errorSpy.mockClear();
    try {
      // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
      i18n.global.t(key);
    } catch {
      return true;
    }
    return errorSpy.mock.calls.length > 0;
  });
  errorSpy.mockRestore();
  return broken;
};

describe('translation message syntax', () => {
  it.each(Object.entries(sources))('every message compiles: %s', (_, json) => {
    expect(brokenKeys(json)).toEqual([]);
  });
});
