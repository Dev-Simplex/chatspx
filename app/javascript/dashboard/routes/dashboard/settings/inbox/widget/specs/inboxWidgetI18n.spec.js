import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import ptBR from 'dashboard/i18n/locale/pt_BR/inboxWidget.json';
import en from 'dashboard/i18n/locale/en/inboxWidget.json';
import {
  KNOWN_FIELD_PATHS,
  fieldLabelKey,
} from '../composables/widgetFieldLabels';

/**
 * pt-BR e prioridade, e `en` nao pode ficar para tras: as duas arvores tem de
 * ter EXATAMENTE as mesmas chaves, e toda chave que as telas novas usam tem de
 * existir nas duas. Este teste le os arquivos da pasta `widget/` de verdade —
 * uma chave escrita no componente e esquecida no JSON falha aqui, nomeando a
 * chave e o arquivo.
 */
const widgetDir = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '..'
);

const sourceFiles = (dir, acc = []) => {
  fs.readdirSync(dir, { withFileTypes: true }).forEach(entry => {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name !== 'specs') sourceFiles(full, acc);
    } else if (/\.(vue|js)$/.test(entry.name)) {
      acc.push(full);
    }
  });
  return acc;
};

const flatten = (node, prefix = '') =>
  Object.entries(node).flatMap(([key, value]) => {
    const full = prefix ? `${prefix}.${key}` : key;
    return typeof value === 'object' && value !== null
      ? flatten(value, full)
      : [full];
  });

const lookup = (tree, dottedKey) =>
  dottedKey.split('.').reduce((node, part) => node?.[part], tree);

const usedKeys = () => {
  const keys = new Set();
  sourceFiles(widgetDir).forEach(file => {
    const content = fs.readFileSync(file, 'utf8');
    const matches = [
      ...content.matchAll(/['"`](INBOX_WIDGET\.[A-Z0-9_.]+)['"`]/g),
    ];
    matches.forEach(match => keys.add(match[1]));
  });
  return [...keys];
};

describe('i18n de INBOX_WIDGET', () => {
  it('varre as telas novas e acha pelo menos as chaves da barra de salvar', () => {
    expect(usedKeys()).toEqual(
      expect.arrayContaining([
        'INBOX_WIDGET.SAVE_BAR.PENDING',
        'INBOX_WIDGET.UNSAVED_DIALOG.TITLE',
      ])
    );
  });

  it.each(usedKeys())('%s existe em pt_BR e em en', key => {
    const relative = key.replace(/^INBOX_WIDGET\./, '');
    expect(lookup(ptBR.INBOX_WIDGET, relative)).toBeTypeOf('string');
    expect(lookup(en.INBOX_WIDGET, relative)).toBeTypeOf('string');
  });

  it.each(KNOWN_FIELD_PATHS)(
    'o campo %s tem rótulo humano nos dois idiomas',
    fieldPath => {
      const relative = fieldLabelKey(fieldPath).replace(/^INBOX_WIDGET\./, '');
      expect(lookup(ptBR.INBOX_WIDGET, relative)).toBeTypeOf('string');
      expect(lookup(en.INBOX_WIDGET, relative)).toBeTypeOf('string');
    }
  );

  it('as duas árvores têm exatamente as mesmas chaves', () => {
    expect(flatten(ptBR).sort()).toEqual(flatten(en).sort());
  });
});
