/**
 * Bloco 4.03 — a garantia que o lint de i18n não consegue dar.
 *
 * `CaptureField` monta a chave da mensagem de erro a partir do `code` que
 * `validateFieldValue` devolve (`CAPTURE.VALIDATION.<code>`). O
 * `@intlify/vue-i18n/no-dynamic-keys` só sabe olhar literais, então ele avisa e
 * não verifica nada. Este spec verifica de verdade: parte do conjunto FECHADO de
 * validadores do bloco 3.13 e exige que TODO código tenha texto nos dois idiomas.
 *
 * pt-BR é prioridade da onda, e `en` entra junto — chave que só existe num dos
 * dois é a forma mais comum de vazamento de i18n.
 */
import { readFileSync } from 'node:fs';
import { VALIDATOR_NAMES } from 'shared/helpers/brMasks';

const ler = locale =>
  JSON.parse(
    readFileSync(`app/javascript/widget/i18n/locale/${locale}.json`, 'utf8')
  );

const ptBR = ler('pt_BR');
const en = ler('en');

// `REQUIRED` não é um validador: é o veredito de campo obrigatório vazio, e sai
// pela mesma porta (ver validateFieldValue).
const CODIGOS = [
  'REQUIRED',
  ...VALIDATOR_NAMES.map(nome => nome.toUpperCase()),
];

describe('4.03 — i18n do fluxo de captura', () => {
  it.each(CODIGOS)('tem texto pt-BR e en para o código %s', codigo => {
    expect(ptBR.CAPTURE.VALIDATION[codigo]).toEqual(expect.any(String));
    expect(ptBR.CAPTURE.VALIDATION[codigo].length).toBeGreaterThan(0);
    expect(en.CAPTURE.VALIDATION[codigo]).toEqual(expect.any(String));
    expect(en.CAPTURE.VALIDATION[codigo].length).toBeGreaterThan(0);
  });

  it('tem os textos fixos da tela nos dois idiomas', () => {
    ['SUBMIT', 'OPTIONAL', 'CONTACT_GROUP_HINT'].forEach(chave => {
      expect(ptBR.CAPTURE[chave].length).toBeGreaterThan(0);
      expect(en.CAPTURE[chave].length).toBeGreaterThan(0);
    });
  });

  it('não deixa texto em português vazar para o arquivo `en`', () => {
    const textoEn = JSON.stringify(en.CAPTURE);
    // Acentos e cedilha são o sinal barato e confiável de vazamento de pt-BR.
    expect(textoEn).not.toMatch(/[áàâãéêíóôõúüç]/i);
  });

  it('não deixa as duas listas divergirem em tamanho', () => {
    expect(Object.keys(en.CAPTURE.VALIDATION).sort()).toEqual(
      Object.keys(ptBR.CAPTURE.VALIDATION).sort()
    );
  });
});
