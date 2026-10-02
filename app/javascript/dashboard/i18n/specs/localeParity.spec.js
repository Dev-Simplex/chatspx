const englishFiles = import.meta.glob('../locale/en/*.json', {
  eager: true,
  import: 'default',
});
const portugueseFiles = import.meta.glob('../locale/pt_BR/*.json', {
  eager: true,
  import: 'default',
});

const leafKeys = (value, prefix = '') =>
  Object.entries(value).flatMap(([key, entry]) => {
    const path = prefix ? `${prefix}.${key}` : key;
    return entry !== null && typeof entry === 'object'
      ? leafKeys(entry, path)
      : [path];
  });

describe('dashboard translation coverage', () => {
  it.each(Object.entries(englishFiles))(
    'has every English key in pt_BR: %s',
    (path, english) => {
      const portuguese = portugueseFiles[path.replace('/en/', '/pt_BR/')];
      const translatedKeys = new Set(leafKeys(portuguese || {}));
      const missingKeys = leafKeys(english).filter(
        key => !translatedKeys.has(key)
      );

      expect(missingKeys).toEqual([]);
    }
  );
});
