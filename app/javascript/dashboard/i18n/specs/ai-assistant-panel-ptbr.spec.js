import fs from 'fs';
import path from 'path';
import { createI18n } from 'vue-i18n';
import ptBrMessages from 'dashboard/i18n/locale/pt_BR';
import enMessages from 'dashboard/i18n/locale/en';

const ROOT = process.cwd();

const readLocale = (locale, file = 'conversation') =>
  JSON.parse(
    fs.readFileSync(
      path.resolve(
        ROOT,
        `app/javascript/dashboard/i18n/locale/${locale}/${file}.json`
      ),
      'utf-8'
    )
  );

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

// Namespaces do painel de IA. O código pede sempre com o prefixo CONVERSATION.,
// então as strings TÊM que morar dentro do objeto CONVERSATION do JSON — se
// alguém regravar na raiz, o painel volta a exibir a chave crua na tela.
const NAMESPACES = ['AI_ASSISTANT_PANEL', 'COPILOT_ERRORS'];

const SOURCE_DIRS = [
  'app/javascript/dashboard/components-next/ai-assistant',
  'app/javascript/dashboard/components/widgets/conversation',
  'app/javascript/dashboard/composables',
];

const collectFiles = dir => {
  const abs = path.resolve(ROOT, dir);
  if (!fs.existsSync(abs)) return [];
  return fs.readdirSync(abs, { withFileTypes: true }).flatMap(entry => {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) return collectFiles(full);
    return /\.(vue|js)$/.test(entry.name) ? [full] : [];
  });
};

// Casa CONVERSATION.<NS>.<CHAVE...> em qualquer contexto: t(), $t(), titleKey:, etc.
const KEY_RE = new RegExp(
  `CONVERSATION\\.(${NAMESPACES.join('|')})((?:\\.[A-Z0-9_]+)+)`,
  'g'
);

const requestedKeys = () => {
  const found = new Map(); // chave -> primeiro arquivo que pede
  SOURCE_DIRS.flatMap(collectFiles).forEach(file => {
    const content = fs.readFileSync(path.resolve(ROOT, file), 'utf-8');
    [...content.matchAll(KEY_RE)].forEach(match => {
      const key = `${match[1]}${match[2]}`;
      if (!found.has(key)) found.set(key, file);
    });
  });
  return found;
};

const presentKeys = locale => {
  const data = readLocale(locale);
  const inside = new Set();
  const atRoot = new Set();
  NAMESPACES.forEach(ns => {
    flattenKeys(data.CONVERSATION?.[ns]).forEach(k => inside.add(`${ns}.${k}`));
    flattenKeys(data[ns]).forEach(k => atRoot.add(`${ns}.${k}`));
  });
  return { inside, atRoot };
};

describe('AI assistant panel (V2) i18n', () => {
  const requested = requestedKeys();

  it('finds the panel keys in the source (guards against a broken regex)', () => {
    expect(requested.size).toBeGreaterThan(50);
  });

  it.each(['pt_BR', 'en'])(
    'resolves every key the panel asks for — %s',
    locale => {
      const { inside } = presentKeys(locale);
      const missing = [...requested.entries()]
        .filter(([key]) => !inside.has(key))
        .map(([key, file]) => `${key} (asked in ${file})`);
      expect(missing).toEqual([]);
    }
  );

  it.each(['pt_BR', 'en'])(
    'keeps the namespaces inside CONVERSATION, never at the root — %s',
    locale => {
      const { atRoot } = presentKeys(locale);
      // Duplicar na raiz é o bug original: o componente pede CONVERSATION.<ns>,
      // vue-i18n não encontra e renderiza a chave crua.
      expect([...atRoot]).toEqual([]);
    }
  );

  it('keeps pt_BR and en with the same key set', () => {
    const ptBr = [...presentKeys('pt_BR').inside].sort();
    const en = [...presentKeys('en').inside].sort();
    expect(ptBr).toEqual(en);
  });

  it.each(['pt_BR', 'en'])('has no blank string — %s', locale => {
    const data = readLocale(locale);
    const blanks = NAMESPACES.flatMap(ns =>
      flattenKeys(data.CONVERSATION?.[ns])
        .filter(k => {
          const value = k
            .split('.')
            .reduce((acc, part) => acc?.[part], data.CONVERSATION[ns]);
          return typeof value === 'string' && value.trim() === '';
        })
        .map(k => `${ns}.${k}`)
    );
    expect(blanks).toEqual([]);
  });

  it('covers the error codes the streaming endpoint emits (contract C1)', () => {
    // Contrato C1: event: error → data.code. Um code sem string vira banner mudo.
    const codes = [
      'UNAUTHORIZED',
      'RATE_LIMITED',
      'TIMEOUT',
      'PROVIDER_DOWN',
      'CANCELLED',
    ];
    ['pt_BR', 'en'].forEach(locale => {
      const errors = readLocale(locale).CONVERSATION.COPILOT_ERRORS;
      codes.forEach(code => {
        expect(errors[code]?.TITLE, `${locale} ${code}.TITLE`).toBeTruthy();
        expect(errors[code]?.BODY, `${locale} ${code}.BODY`).toBeTruthy();
      });
    });
  });

  // A prova de que a tela não mostra chave crua: vue-i18n devolve a própria
  // chave quando não acha a tradução. Se `t(key) === key`, é exatamente isso que
  // o agente veria renderizado no painel.
  it.each([
    ['pt_BR', ptBrMessages],
    ['en', enMessages],
  ])('renders no raw i18n key through vue-i18n — %s', (locale, messages) => {
    const i18n = createI18n({
      legacy: false,
      locale,
      fallbackLocale: locale,
      messages: { [locale]: messages },
      missingWarn: false,
      fallbackWarn: false,
    });
    const { t } = i18n.global;
    const raw = [...requested.keys()]
      .map(key => `CONVERSATION.${key}`)
      // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys -- a chave dinâmica é o teste: varremos as chaves lidas do fonte
      .filter(fullKey => t(fullKey) === fullKey);
    expect(raw).toEqual([]);
  });

  it('actually translates pt_BR (not a copy of en)', () => {
    const ptBr = readLocale('pt_BR').CONVERSATION;
    const en = readLocale('en').CONVERSATION;
    const sample = [
      ['AI_ASSISTANT_PANEL', 'EMPTY', 'SUBTITLE'],
      ['AI_ASSISTANT_PANEL', 'LOADING'],
      ['COPILOT_ERRORS', 'UNAUTHORIZED', 'BODY'],
      ['COPILOT_ERRORS', 'NETWORK', 'BODY'],
    ];
    sample.forEach(pathParts => {
      const read = obj => pathParts.reduce((acc, part) => acc?.[part], obj);
      expect(read(ptBr), pathParts.join('.')).not.toEqual(read(en));
    });
  });
});
