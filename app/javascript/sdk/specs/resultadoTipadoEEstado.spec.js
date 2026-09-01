/**
 * Bloco 5.17 — o RESULTADO TIPADO (T-I4.1) e o ESTADO DO WIDGET (T-I3.3 / T-I4.3).
 *
 * O diagnostico media o bloco como PARCIAL em duas pecas nomeadas: "T-I4.1 (retorno tipado) nao
 * existe" e "T-I3.3/T-I4.3 entrega 1 de 3 getters". O contador de nao lidas ja tinha entrado pelo
 * 1.23 (item 39 da §8.1) e e re-medido aqui de proposito — o aceite deste bloco o cita, e um
 * getter que existe em outro arquivo de spec nao prova nada sobre a superficie que este bloco
 * promete.
 *
 * Por que jsdom basta: nada aqui e cascade nem layout. E contrato de objeto que atravessa para o
 * `window` do site.
 */

import Cookies from 'js-cookie';
import {
  STATUS_ACEITO,
  STATUS_ENFILEIRADO,
  STATUS_DEDUPLICADO,
  STATUS_REJEITADO_VALIDACAO,
} from '../callResult';

describe('5.17 — resultado tipado e estado do widget', () => {
  let IFrameHelper;
  let enviadas;

  beforeEach(async () => {
    document.body.innerHTML = '';
    delete window.$chatwoot;
    window.chatwootSettings = {};
    enviadas = [];

    if (!window.matchMedia) {
      window.matchMedia = () => ({
        matches: false,
        addEventListener: () => {},
        removeEventListener: () => {},
      });
    }

    // Mesma ordem do spec do 1.23, e pelo mesmo motivo: `resetModules` faz o entrypoint importar
    // uma instancia NOVA de `IFrameHelper`. Espionar a antiga nao intercepta nada e o teste ficaria
    // verde sem observar uma unica chamada.
    vi.resetModules();
    ({ IFrameHelper } = await import('../IFrameHelper'));
    vi.spyOn(IFrameHelper, 'sendMessage').mockImplementation((key, value) => {
      enviadas.push({ key, value });
    });

    await import('../../entrypoints/sdk.js');
    window.chatwootSDK.run({
      baseUrl: 'https://exemplo.test',
      websiteToken: 'tok',
    });
  }, 20000);

  afterEach(() => {
    vi.restoreAllMocks();
    Cookies.remove('cw_user_tok');
  });

  const carregarPainel = async () => {
    const iframe = document.createElement('iframe');
    iframe.id = 'chatwoot_live_chat_widget';
    iframe.src = 'https://exemplo.test/widget?website_token=tok';
    document.body.appendChild(iframe);
    Object.defineProperty(iframe, 'contentWindow', {
      value: { postMessage: () => {} },
      configurable: true,
    });
    await IFrameHelper.events.loaded({
      config: { authToken: 't', channelConfig: {} },
    });
  };

  describe('T-I4.1 — a Promise deixa de resolver com undefined', () => {
    it('chamada antes do boot resolve como ENFILEIRADA — e a espera fica visivel', async () => {
      const promessa = window.$chatwoot.setLabel('vip');
      await carregarPainel();

      const resultado = await promessa;

      expect(resultado.status).toBe(STATUS_ENFILEIRADO);
      expect(resultado.queued).toBe(true);
      expect(resultado.method).toBe('setLabel');
    });

    it('chamada depois do boot resolve como ACEITA, sem ter esperado', async () => {
      await carregarPainel();

      const resultado = await window.$chatwoot.setLabel('vip');

      expect(resultado.status).toBe(STATUS_ACEITO);
      expect(resultado.queued).toBe(false);
    });

    /**
     * A DISTINCAO QUE NAO EXISTIA. Antes deste bloco os dois casos acima resolviam com o MESMO
     * `undefined`: "saiu agora" e "esperou o boot" eram indistinguiveis de fora. A assercao e
     * escrita como desigualdade de proposito — ela cai se alguem voltar a resolver os dois iguais,
     * inclusive resolvendo os dois com o mesmo objeto.
     */
    it('as duas NAO resolvem com o mesmo valor', async () => {
      const antes = window.$chatwoot.setLabel('vip');
      await carregarPainel();
      const depois = window.$chatwoot.setLabel('ouro');

      const [a, b] = await Promise.all([antes, depois]);

      expect(a.status).not.toBe(b.status);
    });

    it('o resultado e congelado — script de terceiro nao reescreve o de quem chamou', async () => {
      await carregarPainel();

      const resultado = await window.$chatwoot.setLabel('vip');
      expect(Object.isFrozen(resultado)).toBe(true);

      // Fora de strict mode a escrita e silenciosa; o que se mede e o efeito, nao o throw.
      try {
        resultado.status = 'invadido';
      } catch {
        /* strict mode lanca; os dois caminhos sao aceitaveis */
      }
      expect(resultado.status).toBe(STATUS_ACEITO);
    });

    it('recusa da validacao rejeita com o status e o motivo no proprio erro', async () => {
      await carregarPainel();

      const erro = await window.$chatwoot.setUser('id-1', {}).catch(e => e);

      // `message` continua o que sempre foi: quem ja tratava texto nao quebra.
      expect(erro.message).toContain('should have one of the keys');
      expect(erro.result.status).toBe(STATUS_REJEITADO_VALIDACAO);
      expect(erro.result.method).toBe('setUser');
      expect(erro.result.reason).toBe(erro.message);
    });

    /**
     * O CASO MAIS CARO, e o que estava totalmente mudo.
     *
     * `setUser` deduplica por cookie: hash igual ao da ultima vez e ele retorna cedo, sem mandar
     * mensagem nenhuma. Isso resolvia identico a um envio bem-sucedido — o integrador que perguntava
     * "por que o contato nao atualizou?" nao tinha como ver que a propria SDK decidiu nao mandar.
     *
     * Nao e erro, entao RESOLVE (nao rejeita): a deduplicacao e a otimizacao funcionando.
     */
    it('setUser deduplicado diz que foi deduplicado, e nao manda mensagem', async () => {
      await carregarPainel();
      const usuario = { name: 'Ana', email: 'ana@exemplo.com.br' };

      const primeira = await window.$chatwoot.setUser('id-1', usuario);
      expect(primeira.status).toBe(STATUS_ACEITO);
      expect(enviadas.filter(m => m.key === 'set-user')).toHaveLength(1);

      const segunda = await window.$chatwoot.setUser('id-1', usuario);

      expect(segunda.status).toBe(STATUS_DEDUPLICADO);
      expect(segunda.reason).toContain('identical');
      // A prova de que a deduplicacao de fato aconteceu: nenhuma mensagem NOVA saiu.
      expect(enviadas.filter(m => m.key === 'set-user')).toHaveLength(1);
    });

    it('mudar SO o telefone NAO deduplica — o aceite do bloco, medido pelo resultado', async () => {
      // Este e o aceite escrito no PLANO-MESTRE ("mudar so o telefone e rechamar setUser ATUALIZA
      // o contato"). Aqui ele e medido pelo canal novo: se o dedupe voltar a ignorar o telefone, a
      // segunda chamada devolve `deduplicated` e este teste cai.
      await carregarPainel();

      await window.$chatwoot.setUser('id-1', { name: 'Ana' });
      const segunda = await window.$chatwoot.setUser('id-1', {
        name: 'Ana',
        phone_number: '+5511999998888',
      });

      expect(segunda.status).toBe(STATUS_ACEITO);
      expect(enviadas.filter(m => m.key === 'set-user')).toHaveLength(2);
    });
  });

  describe('T-I3.3 / T-I4.3 — os tres getters', () => {
    beforeEach(() => {
      const bolha = document.createElement('div');
      bolha.className = 'woot-widget-bubble';
      document.body.appendChild(bolha);
    });

    it('getState separa "fechado" de "ainda nao carregou"', async () => {
      // Os dois estados dao `isOpen: false` e pedem acoes OPOSTAS: com o SDK carregado `open()`
      // funciona; sem ele a chamada e engolida. `isOpen` sozinho nao responde a pergunta.
      expect(window.$chatwoot.getState()).toEqual({
        hasLoaded: false,
        isOpen: false,
        isBubbleVisible: true,
        unreadCount: 0,
      });

      await carregarPainel();

      expect(window.$chatwoot.getState().hasLoaded).toBe(true);
      expect(window.$chatwoot.getState().isOpen).toBe(false);
    });

    it('getState acompanha a abertura do painel', async () => {
      await carregarPainel();
      IFrameHelper.events.onBubbleToggle(true);
      window.$chatwoot.isOpen = true;

      expect(window.$chatwoot.getState().isOpen).toBe(true);
    });

    it('isBubbleVisible e a negacao de hideMessageBubble, nao o campo cru', async () => {
      await carregarPainel();
      expect(window.$chatwoot.getState().isBubbleVisible).toBe(true);

      window.$chatwoot.toggleBubbleVisibility('hide');

      expect(window.$chatwoot.getState().isBubbleVisible).toBe(false);
    });

    it('getState e congelado e nao expoe estado interno do SDK', async () => {
      await carregarPainel();
      const estado = window.$chatwoot.getState();

      expect(Object.isFrozen(estado)).toBe(true);
      // O ponto do getter: `window.$chatwoot` carrega muita coisa que NAO e contrato. Se estes
      // vazassem, viravam compatibilidade que ninguem prometeu.
      [
        'websiteToken',
        'baseUrl',
        'resetTriggered',
        'user',
        'identifier',
      ].forEach(chave => expect(estado).not.toHaveProperty(chave));
    });

    it('o contador de nao lidas entra no estado e no getter dedicado', async () => {
      await carregarPainel();
      IFrameHelper.events.handleNotificationDot({ unreadMessageCount: 4 });

      expect(window.$chatwoot.getUnreadCount()).toBe(4);
      expect(window.$chatwoot.getState().unreadCount).toBe(4);
    });

    it('getUser e getIdentifier devolvem null antes de qualquer identificacao', () => {
      expect(window.$chatwoot.getUser()).toBeNull();
      expect(window.$chatwoot.getIdentifier()).toBeNull();
    });

    it('getUser reflete o que updateUser MESCLOU, nao so a ultima chamada', async () => {
      await carregarPainel();

      await window.$chatwoot.updateUser('id-1', { name: 'Ana' });
      await window.$chatwoot.updateUser('id-1', {
        phone_number: '+5511999998888',
      });

      expect(window.$chatwoot.getUser()).toEqual({
        name: 'Ana',
        phone_number: '+5511999998888',
      });
      expect(window.$chatwoot.getIdentifier()).toBe('id-1');
    });
  });
});
