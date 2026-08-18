import ptBR from 'dashboard/i18n/locale/pt_BR/inboxWidget.json';
import en from 'dashboard/i18n/locale/en/inboxWidget.json';
import {
  CONDITION_OPERATORS,
  MASK_NAMES,
  MODES,
  VALIDATOR_NAMES,
} from '../preChatModel';

/**
 * As chaves de i18n do pré-chat são montadas em tempo de execução
 * (`…VALIDATION.${code}`, `…MASKS.${mask}`), e por isso o teste de varredura da
 * pasta `widget/` — que faz grep de `$t('CHAVE.LITERAL')` — **não as vê**.
 * Chave dinâmica que falta só aparece como texto cru na tela do cliente. Este
 * arquivo percorre as listas de verdade e cobra as duas árvores.
 */
const lookup = (tree, dotted) =>
  dotted.split('.').reduce((node, part) => node?.[part], tree);

const expectInBothLocales = key => {
  expect(lookup(ptBR, key), `${key} falta em pt_BR`).toBeTypeOf('string');
  expect(lookup(en, key), `${key} falta em en`).toBeTypeOf('string');
};

describe('i18n do pré-chat — as chaves dinâmicas', () => {
  it('toda máscara tem rótulo nos dois idiomas', () => {
    expect(MASK_NAMES.length).toBe(6);
    MASK_NAMES.forEach(mask =>
      expectInBothLocales(
        `INBOX_WIDGET.PRE_CHAT_FORM.MASKS.${mask.toUpperCase()}`
      )
    );
  });

  it('todo validador tem rótulo E mensagem de erro nos dois idiomas', () => {
    expect(VALIDATOR_NAMES.length).toBe(11);
    VALIDATOR_NAMES.forEach(validator => {
      expectInBothLocales(
        `INBOX_WIDGET.PRE_CHAT_FORM.VALIDATORS.${validator.toUpperCase()}`
      );
      expectInBothLocales(
        `INBOX_WIDGET.PRE_CHAT_FORM.VALIDATION.${validator.toUpperCase()}`
      );
    });
  });

  it('o código REQUIRED, que não vem de validador nenhum, também está lá', () => {
    expectInBothLocales('INBOX_WIDGET.PRE_CHAT_FORM.VALIDATION.REQUIRED');
  });

  it('todo operador de condicional tem rótulo nos dois idiomas', () => {
    expect(CONDITION_OPERATORS).toEqual(['is', 'is_not', 'contains', 'filled']);
    CONDITION_OPERATORS.forEach(operator =>
      expectInBothLocales(
        `INBOX_WIDGET.PRE_CHAT_FORM.CONDITION.OPERATORS.${operator.toUpperCase()}`
      )
    );
  });

  it('todo modo tem nome e descrição nos dois idiomas', () => {
    expect(MODES).toEqual(['simple', 'builder', 'flow']);
    MODES.forEach(mode => {
      expectInBothLocales(
        `INBOX_WIDGET.PRE_CHAT_FORM.MODES.${mode.toUpperCase()}.LABEL`
      );
      expectInBothLocales(
        `INBOX_WIDGET.PRE_CHAT_FORM.MODES.${mode.toUpperCase()}.DESCRIPTION`
      );
    });
  });

  it('pt_BR e en têm exatamente as mesmas chaves sob PRE_CHAT_FORM', () => {
    const flatten = (node, prefix = '') =>
      Object.entries(node).flatMap(([key, value]) => {
        const full = prefix ? `${prefix}.${key}` : key;
        return typeof value === 'object' && value !== null
          ? flatten(value, full)
          : [full];
      });

    const ptKeys = flatten(ptBR.INBOX_WIDGET.PRE_CHAT_FORM).sort();
    const enKeys = flatten(en.INBOX_WIDGET.PRE_CHAT_FORM).sort();

    expect(ptKeys).toEqual(enKeys);
    expect(ptKeys.length).toBeGreaterThan(60);
  });

  it('nenhuma string de pt_BR ficou igual à de en por esquecimento de traduzir', () => {
    // Rótulos que são iguais nos dois idiomas de propósito (siglas).
    const legitimatelyEqual = new Set(['CPF', 'CNPJ']);

    const compare = (a, b, prefix = '') =>
      Object.entries(a).flatMap(([key, value]) => {
        const full = prefix ? `${prefix}.${key}` : key;
        if (typeof value === 'object' && value !== null) {
          return compare(value, b?.[key] ?? {}, full);
        }
        return value === b?.[key] && !legitimatelyEqual.has(value)
          ? [full]
          : [];
      });

    expect(
      compare(ptBR.INBOX_WIDGET.PRE_CHAT_FORM, en.INBOX_WIDGET.PRE_CHAT_FORM)
    ).toEqual([]);
  });
});
