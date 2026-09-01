import {
  applyInboxConsentMode,
  consentAttributes,
  onConsentChange,
  publishDefaults,
  resetConsentForTests,
  updateConsent,
} from '../consent';

/**
 * Bloco 5.09 (T-C7.4/T-C7.6) — o consentimento ATRAVESSA para o servidor.
 *
 * O DEFEITO QUE ESTE ARQUIVO FECHA: o gate de `consent.js` era completo e estava medido — 56
 * asserções, incluindo "zero disparo antes do consentimento". Mas ele só governava o que o
 * NAVEGADOR dispara. Nada do estado saía do navegador, e a fila server-side (CAPI, Measurement
 * Protocol, Enhanced Conversions) seguia enviando o evento com `consent_block` cravado em
 * `GRANTED`. O visitante que recusou tudo tinha a recusa respeitada de um lado e desmentida do
 * outro — e o lado que desmentia era justamente o que o bloqueador de anúncio não alcança.
 *
 * As chaves aqui são o CONTRATO com `Tracking::ConsentState` no Ruby. Se um lado renomear
 * `consent_ad_user_data`, o outro passa a ler ausência — e ausência, com o modo ativo, lê-se como
 * negado: a medição do cliente desliga inteira, sem erro em lugar nenhum.
 */
describe('5.09 — o consentimento chega ao backend', () => {
  let entregues;

  beforeEach(() => {
    entregues = [];
    resetConsentForTests(() => {});
    onConsentChange(attrs => entregues.push(attrs));
  });

  it('as chaves são as que o Ruby lê: prefixo `consent_` e os quatro propósitos', () => {
    applyInboxConsentMode('basic');
    updateConsent({ ad_user_data: 'granted' });

    expect(Object.keys(consentAttributes()).sort()).toEqual([
      'consent_ad_personalization',
      'consent_ad_storage',
      'consent_ad_user_data',
      'consent_analytics_storage',
    ]);
  });

  it('a grafia é a do navegador — `granted`/`denied`, minúsculas', () => {
    applyInboxConsentMode('basic');
    updateConsent({ ad_user_data: 'granted' });

    expect(entregues.at(-1).consent_ad_user_data).toBe('granted');
    expect(entregues.at(-1).consent_ad_storage).toBe('denied');
  });

  it('o `update` da CMP atravessa — aceitar depois chega ao servidor', () => {
    applyInboxConsentMode('basic');
    expect(entregues).toHaveLength(0);

    updateConsent({ ad_user_data: 'granted', ad_storage: 'granted' });

    expect(entregues).toHaveLength(2); // o `default` implícito, e o `update`
    expect(entregues.at(-1)).toMatchObject({
      consent_ad_user_data: 'granted',
      consent_ad_storage: 'granted',
    });
  });

  // O modo `advanced` publica o `default` na própria aplicação do modo. Se o observador fosse
  // registrado depois disso, essa primeira publicação — a que diz "nada foi concedido" — se
  // perderia, e o servidor só saberia do consentimento se o visitante mexesse na CMP.
  it('no modo `advanced`, o `default` NEGADO já atravessa no boot', () => {
    applyInboxConsentMode('advanced');

    expect(entregues).toHaveLength(1);
    expect(entregues[0]).toEqual({
      consent_ad_storage: 'denied',
      consent_ad_user_data: 'denied',
      consent_ad_personalization: 'denied',
      consent_analytics_storage: 'denied',
    });
  });

  // A TRAVA. `disabled` é o valor de toda inbox da frota. Escrever quatro `consent_*` no
  // `custom_attributes` de cada conversa seria fabricar registro de consentimento para contas que
  // nunca declararam operar sob CMP — e um campo de auditoria que se inventa não audita nada.
  it('com o modo `disabled`, NADA atravessa', () => {
    applyInboxConsentMode('disabled');
    publishDefaults();
    updateConsent({ ad_user_data: 'granted' });

    expect(entregues).toEqual([]);
  });

  // A entrega real manda o MESMO objeto para contato e conversa (ver `IFrameHelper`), porque o
  // `POST /widget/events` registra o fato só com `contact:`. Aqui provamos que o payload publicado
  // serve aos dois destinos — é um objeto plano de chaves `consent_*`, sem nada aninhado que o
  // `custom_attributes` do contato não saiba guardar.
  it('publica um objeto plano, servível a contato E conversa', () => {
    applyInboxConsentMode('basic');
    updateConsent({ ad_user_data: 'granted' });

    const publicado = entregues.at(-1);
    expect(Object.values(publicado).every(v => typeof v === 'string')).toBe(
      true
    );
    expect(Object.keys(publicado)).toHaveLength(4);
  });

  it('observador que explode não derruba o widget', () => {
    onConsentChange(() => {
      throw new Error('bridge caiu');
    });
    applyInboxConsentMode('basic');

    expect(() => updateConsent({ ad_user_data: 'granted' })).not.toThrow();
  });
});
