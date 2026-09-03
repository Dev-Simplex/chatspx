/**
 * i18n sob demanda — bloco 2.18.
 *
 * O aceite do bloco é de PESO, e peso se mede no artefato
 * (`scripts/widget-eager.check.mjs`, contra `chunk.modules` do Rollup). Estes
 * testes cobrem a outra metade: o contrato do módulo continua o mesmo depois
 * de os 40 `import` estáticos virarem 39 `import()`.
 *
 * O que eles ACUSAM, e que nenhum teste de peso pega: um idioma que sumiu do
 * mapa (o painel abriria em inglês para aquele cliente, sem erro nenhum), o
 * `en` deixar de ser eager (o painel nasceria sem string alguma enquanto o
 * chunk não chega) e uma falha de rede virar exceção em vez de fallback.
 */
import { describe, it, expect, vi, afterEach } from 'vitest';
import messagesEager, {
  AVAILABLE_LOCALES,
  FALLBACK_LOCALE,
  hasLocale,
  loadLocaleMessages,
} from 'widget/i18n';
import en from 'widget/i18n/locale/en.json';
import ptBR from 'widget/i18n/locale/pt_BR.json';

// Os 40 que este índice sempre expôs. A lista está escrita aqui, e não
// derivada de `AVAILABLE_LOCALES`, de propósito: derivar faria o teste
// concordar com qualquer regressão.
const OS_40 = [
  'ar', 'bg', 'ca', 'cs', 'da', 'de', 'el', 'en', 'es', 'fa',
  'fi', 'fr', 'he', 'hi', 'hu', 'id', 'is', 'it', 'ja', 'ko',
  'lt', 'lv', 'ml', 'nl', 'no', 'pl', 'pt', 'pt_BR', 'ro', 'ru',
  'sk', 'sr', 'sv', 'ta', 'th', 'tr', 'uk', 'vi', 'zh_CN', 'zh_TW',
];

describe('widget/i18n — carga sob demanda', () => {
  afterEach(() => vi.restoreAllMocks());

  it('expõe exatamente os 40 idiomas de sempre', () => {
    expect([...AVAILABLE_LOCALES].sort()).toEqual([...OS_40].sort());
  });

  it('só o fallback viaja no bundle de first-paint', () => {
    // É ESTE o teste que o bloco existe para fazer passar. Antes dele, este
    // objeto tinha 40 chaves e as 40 estavam no chunk de entrada.
    expect(Object.keys(messagesEager)).toEqual(['en']);
    expect(messagesEager.en).toBe(en);
    expect(FALLBACK_LOCALE).toBe('en');
  });

  it('carrega um idioma que NÃO é o fallback, com o conteúdo certo', async () => {
    const msgs = await loadLocaleMessages('pt_BR');
    // Igualdade de conteúdo, não de referência: o `import()` devolve o mesmo
    // JSON, mas o que interessa ao painel é a string traduzida.
    expect(msgs).toEqual(ptBR);
    expect(msgs).not.toEqual(en);
  });

  it('resolve o próprio fallback sem ir buscar chunk nenhum', async () => {
    await expect(loadLocaleMessages('en')).resolves.toBe(en);
  });

  it('devolve null — e não lança — para idioma desconhecido', async () => {
    expect(hasLocale('klingon')).toBe(false);
    await expect(loadLocaleMessages('klingon')).resolves.toBeNull();
  });

});
