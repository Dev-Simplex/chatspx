/**
 * Mecanismo de aceite do bloco 1.23 — a fila pré-boot do SDK.
 *
 * ACEITE (§2.2): "Os 7 métodos chamados antes do boot são aplicados depois com o
 * mesmo efeito; chamada malformada dentro de tag do GTM não derruba as tags
 * seguintes."
 *
 * Por que jsdom basta: o defeito é de LÓGICA (a mensagem se perde ou explode
 * quando o iframe ainda não existe), não de cascade nem de layout.
 */

// Os SETE métodos de dados da API pública. Configuração (`setLocale`,
// `setColorScheme`) e janela (`toggle`, `popoutChatWindow`) ficam de fora: eles
// não carregam dado do cliente.
const METODOS_DE_DADOS = [
  ['setUser', ['id-1', { name: 'Ana', email: 'ana@example.com' }]],
  ['setCustomAttributes', [{ plano: 'ouro' }]],
  ['deleteCustomAttribute', ['plano']],
  ['setConversationCustomAttributes', [{ pedido: '123' }]],
  ['deleteConversationCustomAttribute', ['pedido']],
  ['setLabel', ['vip']],
  ['removeLabel', ['vip']],
];

describe('1.23 — os 7 métodos de dados chamados antes do boot', () => {
  let enviadas;
  let IFrameHelper;

  beforeEach(async () => {
    document.body.innerHTML = '';
    delete window.$chatwoot;
    window.chatwootSettings = {};
    enviadas = [];

    // jsdom não tem matchMedia, e `loaded` passa por ele.
    if (!window.matchMedia) {
      window.matchMedia = () => ({
        matches: false,
        addEventListener: () => {},
        removeEventListener: () => {},
      });
    }

    // Espiona a ponte registrando TAMBÉM se o app já havia carregado no momento
    // do envio. É esse o ponto: o defeito não é exceção — o `postMessage` sai
    // para um iframe que ainda não tem quem escute, e a mensagem se PERDE em
    // silêncio. Registrar `hasLoaded` é o que torna a perda visível no teste.
    // A ORDEM IMPORTA. `resetModules` faz o entrypoint importar uma instância
    // NOVA de `IFrameHelper`; espionar a instância antiga não intercepta nada, e
    // o teste ficaria verde sem observar uma única chamada. Reseta, importa o
    // módulo fresco, espiona ELE, e só então carrega o entrypoint.
    vi.resetModules();
    ({ IFrameHelper } = await import('../IFrameHelper'));
    vi.spyOn(IFrameHelper, 'sendMessage').mockImplementation((key, value) => {
      enviadas.push({ key, value, hasLoaded: !!window.$chatwoot?.hasLoaded });
    });

    await import('../../entrypoints/sdk.js');
    window.chatwootSDK.run({
      baseUrl: 'https://exemplo.test',
      websiteToken: 'tok',
    });
    // `resetModules` + dois imports dinâmicos passam dos 10s padrão quando este
    // arquivo roda junto da suíte inteira.
  }, 20000);

  afterEach(() => {
    vi.restoreAllMocks();
  });

  // O painel monta: cria o iframe e sinaliza `loaded`, que é o gatilho da
  // drenagem.
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

  it('nenhum dos 7 é despachado para o vazio antes do boot', () => {
    // O defeito que este bloco fecha: hoje a mensagem sai imediatamente, para um
    // iframe que ainda não montou o app. Ninguém escuta, e o dado do cliente
    // some sem erro, sem log e sem retry.
    METODOS_DE_DADOS.forEach(([nome, args]) => {
      try {
        window.$chatwoot[nome](...args);
      } catch {
        /* medido no teste do GTM */
      }
    });

    const perdidas = enviadas.filter(m => !m.hasLoaded).map(m => m.key);
    expect(perdidas).toEqual([]);
  });

  it('os 7 são aplicados depois do boot, com o mesmo efeito', async () => {
    METODOS_DE_DADOS.forEach(([nome, args]) => {
      try {
        window.$chatwoot[nome](...args);
      } catch {
        /* medido no teste acima */
      }
    });

    // Nada pode ter saído ainda: não há quem escute.
    expect(enviadas).toEqual([]);

    await carregarPainel();

    // E agora a fila drena, na ordem e com o mesmo conteúdo.
    //
    // Filtra pelos eventos de DADOS: o próprio `loaded` emite `config-set` e
    // `change-url`, que são configuração e não têm relação com a fila. Comparar
    // a lista inteira misturaria as duas coisas e tornaria o teste frágil a
    // qualquer mensagem nova de boot.
    const EVENTOS_DE_DADOS = [
      'set-user',
      'set-custom-attributes',
      'delete-custom-attribute',
      'set-conversation-custom-attributes',
      'delete-conversation-custom-attribute',
      'set-label',
      'remove-label',
    ];
    const dados = enviadas.filter(m => EVENTOS_DE_DADOS.includes(m.key));

    expect(dados.map(m => m.key)).toEqual([
      'set-user',
      'set-custom-attributes',
      'delete-custom-attribute',
      'set-conversation-custom-attributes',
      'delete-conversation-custom-attribute',
      'set-label',
      'remove-label',
    ]);
    expect(dados[0].value).toEqual({
      identifier: 'id-1',
      user: { name: 'Ana', email: 'ana@example.com' },
    });
    expect(dados[3].value).toEqual({ customAttributes: { pedido: '123' } });
    // E todas saíram DEPOIS do boot — nenhuma para o vazio.
    expect(dados.every(m => m.hasLoaded)).toBe(true);
  });

  it('chamada malformada não derruba as tags seguintes do GTM', () => {
    // O container do GTM executa tags em sequência no MESMO contexto: um throw
    // síncrono numa tag impede as próximas de rodar. É o cenário real.
    const executouDepois = [];
    const container = [
      () => window.$chatwoot.setUser({ nao: 'e string' }, { name: 'X' }),
      () => window.$chatwoot.setCustomAttributes(),
      () => window.$chatwoot.deleteCustomAttribute(''),
      () => executouDepois.push('tag-seguinte'),
    ];

    expect(() => container.forEach(tag => tag())).not.toThrow();
    expect(executouDepois).toEqual(['tag-seguinte']);
  });

  it('a Promise resolve quando a mensagem SAI, não quando é chamada', async () => {
    let resolvida = false;
    const p = window.$chatwoot.setLabel('vip').then(() => {
      resolvida = true;
    });

    // Ainda na fila: nada saiu, logo nada pode ter resolvido.
    await Promise.resolve();
    expect(resolvida).toBe(false);

    await carregarPainel();
    await p;
    expect(resolvida).toBe(true);
  });

  it('o set-user NÃO sai duas vezes — a re-hidratação não duplica a fila', async () => {
    // A armadilha da §12.1: uma segunda fila por cima faz o atributo ser enviado
    // duas vezes. Aqui o risco equivalente é a re-hidratação do `loaded`, que
    // reenviava `window.$chatwoot.user` por conta própria.
    window.$chatwoot.setUser('id-1', { name: 'Ana' });
    await carregarPainel();

    const setUsers = enviadas.filter(m => m.key === 'set-user');
    expect(setUsers).toHaveLength(1);
    // E com o formato do contrato: a re-hidratação mandava o `user` cru, sem
    // `identifier`, produzindo o mesmo evento em dois formatos.
    expect(setUsers[0].value).toEqual({
      identifier: 'id-1',
      user: { name: 'Ana' },
    });
  });

  it('updateUser antes do boot manda UMA identidade — e é a de MESCLA', async () => {
    // A GUARDA ERA POR RÓTULO CRAVADO (`!drenados.includes('setUser')`), e
    // `updateUser` passava por baixo dela: o despacho da fila grava
    // `window.$chatwoot.user`, e a re-hidratação logo abaixo via o objeto
    // preenchido e mandava `set-user` por cima. Duas identidades pelo mesmo
    // gesto do integrador — e a segunda é o verbo que SUBSTITUI o contato, que
    // é exatamente o que `updateUser` existe para não fazer (5.17).
    //
    // Cenário real: telefone corrigido por `updateUser` numa tag do GTM que
    // dispara junto do `run()`. O `set-user` de re-hidratação chegaria depois
    // com o mesmo objeto e apagaria os campos que não estavam nele.
    window.$chatwoot.updateUser('id-1', { phone_number: '+5511999998888' });
    await carregarPainel();

    const identidade = enviadas.filter(
      m => m.key === 'set-user' || m.key === 'update-user'
    );
    expect(identidade.map(m => m.key)).toEqual(['update-user']);
    expect(identidade[0].value).toEqual({
      identifier: 'id-1',
      user: { phone_number: '+5511999998888' },
    });
  });

  it('a re-hidratação CONTINUA saindo quando a fila não cobriu a identidade', async () => {
    // O par negativo do teste acima, e ele existe porque a correção mais barata
    // — apagar a re-hidratação — deixaria o teste anterior verde e quebraria o
    // caso que a re-hidratação atende: iframe recriado (`reset()`, navegação)
    // com o SDK já identificado, sem nada na fila. Sem este teste, "não
    // duplicou" também passaria com "não mandou nada".
    window.$chatwoot.identifier = 'id-9';
    window.$chatwoot.user = { name: 'Bia' };
    await carregarPainel();

    const setUsers = enviadas.filter(m => m.key === 'set-user');
    expect(setUsers).toHaveLength(1);
    expect(setUsers[0].value).toEqual({
      identifier: 'id-9',
      user: { name: 'Bia' },
    });
  });

  describe('chatwoot:error — o SDK deixa de ser mudo TAMBÉM no window', () => {
    let erros;
    let ouvinte;

    beforeEach(() => {
      erros = [];
      ouvinte = evento => erros.push(evento.detail);
      window.addEventListener('chatwoot:error', ouvinte);
    });

    afterEach(() => {
      window.removeEventListener('chatwoot:error', ouvinte);
    });

    // O `catch` interno reporta num microtask; um tick basta para ele correr.
    const proximoTick = () =>
      new Promise(resolve => {
        setTimeout(resolve, 0);
      });

    it('chamada malformada emite chatwoot:error com o método e o motivo', async () => {
      // Até aqui o erro morria num `console.error`. Quem integra por GTM não
      // olha o console do visitante: o sinal precisa chegar ao `window`, que é
      // onde o site já escuta `chatwoot:ready` e `chatwoot:error` do painel.
      window.$chatwoot.setUser({ nao: 'e string' }, { name: 'Ana' });
      await proximoTick();

      expect(erros).toHaveLength(1);
      expect(erros[0].method).toBe('setUser');
      expect(erros[0].message).toMatch(/Identifier should be a string/);
      // O `window` do site é legível por qualquer script de terceiro da página
      // (regra RC5): nome de método e motivo sim, valor de PII nunca. O nome
      // que o integrador passou NÃO pode viajar no evento.
      expect(JSON.stringify(erros[0])).not.toContain('Ana');
    });

    it('`method` distingue o erro da API do erro do painel', async () => {
      // O mesmo nome de evento passa a carregar duas formas, e sem um
      // discriminador isso é a §12.7 se repetindo: quem escuta teria de
      // adivinhar qual das duas chegou. `method` existe só na nossa.
      window.$chatwoot.setCustomAttributes();
      IFrameHelper.events.error({
        errorType: 'OUTRO',
        data: { message: 'veio do painel' },
      });
      await proximoTick();

      expect(erros).toHaveLength(2);
      const daApi = erros.filter(e => e && e.method);
      const doPainel = erros.filter(e => !e || !e.method);
      expect(daApi).toHaveLength(1);
      expect(daApi[0].method).toBe('setCustomAttributes');
      expect(doPainel).toHaveLength(1);
      expect(doPainel[0]).toEqual({ message: 'veio do painel' });
    });

    it('chamada VÁLIDA não emite chatwoot:error', async () => {
      // A trava contra o emissor que dispara sempre: um `chatwoot:error` em
      // toda chamada faria o site do cliente tratar sucesso como falha, e o
      // teste acima passaria igual.
      window.$chatwoot.setUser('id-1', { name: 'Ana' });
      await carregarPainel();
      await proximoTick();

      expect(erros).toEqual([]);
    });
  });

  describe('contador de não lidas na API pública (item 39 da §8.1)', () => {
    beforeEach(() => {
      // `handleNotificationDot` decora a bolha; sem ela no DOM o próprio
      // decorador estoura antes de qualquer coisa.
      const bolha = document.createElement('div');
      bolha.className = 'woot-widget-bubble';
      document.body.appendChild(bolha);
    });

    it('começa em 0 e acompanha o que o painel manda', () => {
      expect(window.$chatwoot.getUnreadCount()).toBe(0);

      IFrameHelper.events.handleNotificationDot({ unreadMessageCount: 3 });
      expect(window.$chatwoot.getUnreadCount()).toBe(3);

      IFrameHelper.events.handleNotificationDot({ unreadMessageCount: 0 });
      expect(window.$chatwoot.getUnreadCount()).toBe(0);
    });

    it('conta mesmo com a bolha escondida — o número não é o enfeite', () => {
      // `hideMessageBubble` sai cedo do decorador. Quem esconde a bolha é
      // justamente quem desenha o próprio contador no site, e é quem mais
      // precisa do número: contar depois desse `return` entregaria 0 para ele.
      window.$chatwoot.hideMessageBubble = true;

      IFrameHelper.events.handleNotificationDot({ unreadMessageCount: 5 });

      expect(window.$chatwoot.getUnreadCount()).toBe(5);
    });
  });

  it('REGISTRO: setLocale/setColorScheme antes do boot AINDA se perdem', () => {
    // Este teste não celebra o comportamento — ele o CONGELA, com o número
    // medido, para que mudá-lo seja uma decisão e não um acidente.
    //
    // O QUE FOI MEDIDO: os dois saem com `hasLoaded: false`, ou seja, um
    // `postMessage` para um iframe que ainda não tem quem escute. Some sem
    // erro, sem log e sem nova tentativa — o mesmo defeito que a fila fechou
    // para os 7 métodos de DADOS. Eles ficaram de fora porque não carregam dado
    // do cliente (é o critério do próprio bloco, no topo deste arquivo).
    //
    // POR QUE NÃO FOI CORRIGIDO AQUI, e isto é o que importa para quem pegar:
    // enfileirá-los do jeito óbvio produz um defeito PIOR e silencioso. Em
    // `IFrameHelper.events.loaded` o `drenar()` roda ANTES do `config-set`, e o
    // `config-set` reenvia `locale` e `darkMode` lidos de `window.$chatwoot` —
    // o handler do painel (`bridge/handlers.js:30`) chama `ctx.setLocale(
    // message.locale)` com eles. Resultado: o `set-locale` drenado seria
    // aplicado e sobrescrito uma linha depois pelo valor do snippet, que aqui é
    // `undefined`. A correção certa tem de gravar TAMBÉM `window.$chatwoot.
    // locale` / `.darkMode`, e isso muda o contrato de dois métodos públicos —
    // decisão, não detalhe de implementação.
    window.$chatwoot.setLocale('pt_BR');
    window.$chatwoot.setColorScheme('dark');

    const perdidas = enviadas.filter(m => !m.hasLoaded).map(m => m.key);
    expect(perdidas).toEqual(['set-locale', 'set-color-scheme']);
  });

  describe('open() e close() idempotentes (item 37 da §8.1)', () => {
    let alternancias;

    beforeEach(() => {
      alternancias = [];
      vi.spyOn(IFrameHelper.events, 'toggleBubble').mockImplementation(estado =>
        alternancias.push(estado)
      );
    });

    it('open() duas vezes abre uma vez só', () => {
      window.$chatwoot.isOpen = false;
      window.$chatwoot.open();
      window.$chatwoot.isOpen = true; // o painel confirma a abertura
      window.$chatwoot.open();

      expect(alternancias).toEqual(['open']);
    });

    it('close() com o painel já fechado não faz nada', () => {
      window.$chatwoot.isOpen = false;
      window.$chatwoot.close();

      expect(alternancias).toEqual([]);
    });

    it('close() fecha quando está aberto', () => {
      window.$chatwoot.isOpen = true;
      window.$chatwoot.close();

      expect(alternancias).toEqual(['close']);
    });
  });
});
