import { useKanbanGlossary } from '../useKanbanGlossary';
import enKanban from 'dashboard/i18n/locale/en/kanban.json';
import ptKanban from 'dashboard/i18n/locale/pt_BR/kanban.json';

// Resolve a dotted i18n key ("KANBAN.GLOSSARY.TERMS.WIP.LABEL") against a
// locale object, returning undefined if any segment is missing.
const resolve = (obj, key) =>
  key.split('.').reduce((acc, part) => (acc == null ? acc : acc[part]), obj);

describe('useKanbanGlossary', () => {
  const { groups, allTerms } = useKanbanGlossary();

  it('exposes grouped terms and a flat list that matches', () => {
    expect(groups.length).toBeGreaterThan(0);
    const flatFromGroups = groups.flatMap(group => group.terms);
    expect(allTerms).toHaveLength(flatFromGroups.length);
  });

  it('gives every group a title key and at least one term', () => {
    groups.forEach(group => {
      expect(group.id).toBeTruthy();
      expect(group.titleKey).toMatch(/^KANBAN\.GLOSSARY\.GROUPS\./);
      expect(resolve(enKanban, group.titleKey)).toBeTruthy();
      expect(resolve(ptKanban, group.titleKey)).toBeTruthy();
      expect(group.terms.length).toBeGreaterThan(0);
    });
  });

  it('uses unique term ids', () => {
    const ids = allTerms.map(term => term.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it('points every term at i18n keys that exist in en and pt_BR', () => {
    allTerms.forEach(term => {
      [term.labelKey, term.descKey].forEach(key => {
        expect(resolve(enKanban, key), `en missing ${key}`).toBeTruthy();
        expect(resolve(ptKanban, key), `pt missing ${key}`).toBeTruthy();
      });
      if (term.adviceKey) {
        expect(resolve(enKanban, term.adviceKey)).toBeTruthy();
        expect(resolve(ptKanban, term.adviceKey)).toBeTruthy();
      }
    });
  });

  it('carries a swatch color and/or an icon for every term', () => {
    allTerms.forEach(term => {
      expect(Boolean(term.swatch) || Boolean(term.icon)).toBe(true);
    });
  });
});
