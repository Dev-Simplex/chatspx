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
