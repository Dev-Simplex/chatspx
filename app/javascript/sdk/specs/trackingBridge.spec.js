import { IFrameHelper } from '../IFrameHelper';

/**
 * Blocos 5.10 e 5.16 — a junção no HOST: um evento que sobe do widget, dois vocabulários.
 *
 * O `IFrameHelper.events.onEvent` é o ponto por onde TUDO passa. O que este arquivo verifica é a
 * arbitragem A9 em funcionamento: o mesmo fato vira um `CustomEvent` no `window` do site (o
 * contrato `chatwoot:*`, que já estava em produção) **e** um evento de tracking `chatspx_*` —
 * sem que um dependa do outro.
 */
describe('5.10/5.16 — a saída dos eventos de tracking no host', () => {
  beforeEach(() => {
    window.dataLayer = [];
    IFrameHelper.tagBridge = null;
  });

  afterEach(() => {
    IFrameHelper.tagBridge = null;
  });

  describe('#publishTrackingEvent', () => {
    it('sem a ponte carregada, o `dataLayer` recebe assim mesmo', () => {
      // É o modo "somente `dataLayer`" (T-C4.10) na sua forma real: quem integra por GTM não
      // configura Pixel ID nenhum, então o artefato da ponte nem é baixado. Se o `push`
      // dependesse dele, esse cliente ficaria sem evento — e é o cliente que o modo atende.
      IFrameHelper.publishTrackingEvent(
        'chatspx_lead',
        { value: 10 },
        'uuid-1'
      );

      expect(window.dataLayer).toEqual([
        { event: 'chatspx_lead', value: 10, event_id: 'uuid-1' },
      ]);
    });

    it('sem `event_id`, a chave não aparece vazia', () => {
      IFrameHelper.publishTrackingEvent('chatspx_lead', {});
      expect(window.dataLayer[0]).toEqual({ event: 'chatspx_lead' });
    });

    it('com a ponte carregada, quem publica é ela — e só ela', () => {
      const ponte = vi.fn();
      IFrameHelper.tagBridge = ponte;

      IFrameHelper.publishTrackingEvent('chatspx_lead', { value: 3 }, 'uuid-2');

      expect(ponte).toHaveBeenCalledWith(
        'chatspx_lead',
        { value: 3 },
        'uuid-2'
      );
      // Sem publicação dupla: a ponte já empurra para o `dataLayer` por dentro.
      expect(window.dataLayer).toEqual([]);
    });
  });

  describe('#events.onEvent — dois vocabulários, uma emissão', () => {
    it('emite o `CustomEvent` do site E o evento de tracking', () => {
      const ouvinte = vi.fn();
      window.addEventListener('chatwoot:lead-identified', ouvinte);

      IFrameHelper.events.onEvent({
        eventIdentifier: 'chatwoot:lead-identified',
        data: { conversation_id: 12, identifiers: ['email'] },
        tracking: 'chatspx_lead',
      });

      expect(ouvinte).toHaveBeenCalledTimes(1);
      expect(ouvinte.mock.calls[0][0].detail).toEqual({
        conversation_id: 12,
        identifiers: ['email'],
      });
      expect(window.dataLayer).toEqual([
        { event: 'chatspx_lead', conversation_id: 12, identifiers: ['email'] },
      ]);

      window.removeEventListener('chatwoot:lead-identified', ouvinte);
    });

    it('`tracking: null` é estado declarado: o site recebe, o tracking não', () => {
      // `chatwoot:csat-submitted` existe no contrato de `window` e NÃO tem contrapartida de
      // tracking — o contrato §6 ponto 1 manda não criar `chatspx_csat_submitted` antes de o
      // produto decidir parâmetros e política de PII.
      const ouvinte = vi.fn();
      window.addEventListener('chatwoot:csat-submitted', ouvinte);

      IFrameHelper.events.onEvent({
        eventIdentifier: 'chatwoot:csat-submitted',
        data: { rating: 5 },
        tracking: null,
      });

      expect(ouvinte).toHaveBeenCalledTimes(1);
      expect(window.dataLayer).toEqual([]);

      window.removeEventListener('chatwoot:csat-submitted', ouvinte);
    });

    it('o `track()` do site não vira evento de `window` — só de tracking', () => {
      const espiao = vi.spyOn(window, 'dispatchEvent');

      IFrameHelper.events.onEvent({
        eventIdentifier: null,
        data: { valor: 990 },
        tracking: 'chatspx_orcamento_pedido',
        eventId: 'uuid-3',
      });

      expect(espiao).not.toHaveBeenCalled();
      expect(window.dataLayer).toEqual([
        { event: 'chatspx_orcamento_pedido', valor: 990, event_id: 'uuid-3' },
      ]);

      espiao.mockRestore();
    });

    it('evento antigo, sem a chave `tracking`, continua saindo como sempre saiu', () => {
      // Os sete nomes que já estavam em produção não têm entrada de tracking e não podem
      // ganhar uma por acidente: o SDK antigo conversando com painel novo (e o contrário)
      // é o caso normal durante um rollout.
      const ouvinte = vi.fn();
      window.addEventListener('chatwoot:on-message', ouvinte);

      IFrameHelper.events.onEvent({
        eventIdentifier: 'chatwoot:on-message',
        data: { content: 'oi' },
      });

      expect(ouvinte).toHaveBeenCalledTimes(1);
      expect(window.dataLayer).toEqual([]);

      window.removeEventListener('chatwoot:on-message', ouvinte);
    });
  });
});
