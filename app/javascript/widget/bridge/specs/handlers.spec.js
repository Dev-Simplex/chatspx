import { handlers } from '../handlers';

// Os nomes de evento do contrato site → widget: os 16 copiados da cadeia de
// `else if` que existia em App.vue:261-348 ANTES desta refatoração, mais os que
// blocos posteriores acrescentaram — cada um com o bloco anotado ao lado. A lista
// é a régua: se um nome sumir ou nascer sem querer, este arquivo reprova — e foi o
// que ele fez quando `update-user` chegou.
//
// Bloco 5.17 acrescentou `update-user`, o verbo que MESCLA. `set-user` continua sendo
// o que SUBSTITUI (legado). Dois verbos porque o site que só quer corrigir o telefone
// não deveria precisar reenviar o objeto inteiro e torcer para não esquecer um campo.
const CONTRACT_EVENTS = [
  'approach-event', // 4.21
  'config-set',
  'widget-visible',
  'change-url',
  'toggle-close-button',
  'push-event',
  'set-label',
  'remove-label',
  'set-user',
  'set-custom-attributes',
  'delete-custom-attribute',
  'set-conversation-custom-attributes',
  'delete-conversation-custom-attribute',
  'set-locale',
  'set-color-scheme',
  'toggle-open',
  'sdk-set-bubble-visibility',
  'update-user', // 5.17
  'track-event', // 5.16
];

const buildContext = (overrides = {}) => ({
  $store: { dispatch: vi.fn() },
  $route: { name: 'home' },
  router: { replace: vi.fn(() => Promise.resolve()) },
  isInWorkingHours: true,
  isMobile: false,
  messageCount: 0,
  setLocale: vi.fn(),
  setBubbleLabel: vi.fn(),
  setUnreadView: vi.fn(),
  unsetUnreadView: vi.fn(),
  setCampaignReadData: vi.fn(),
  scrollConversationToBottom: vi.fn(),
  fetchAvailableAgents: vi.fn(),
  fetchOldConversations: vi.fn(() => Promise.resolve()),
  ...overrides,
});

vi.mock('widget/api/approachEvent', () => ({
  registrarEtapaDaAbordagem: vi.fn(),
}));

describe('bridge/handlers', () => {
  beforeEach(() => {
    window.chatwootWebChannel = { websiteToken: 'token-do-site' };
    delete window.referrerURL;
  });

  it('cobre exatamente os 19 eventos do contrato, sem sobra nem falta', () => {
    expect(Object.keys(handlers).sort()).toEqual([...CONTRACT_EVENTS].sort());
  });

  it('approach-event repassa o que o host mediu, sem tocar no store (4.21)', async () => {
    const { registrarEtapaDaAbordagem } = await import(
      'widget/api/approachEvent'
    );
    const ctx = buildContext();
    const mensagem = {
      event: 'approach-event',
      etapa: 'shown',
      approach: 'discreet',
      approach_configured: 'bold',
      ordinal: 2,
    };

    handlers['approach-event'](mensagem, ctx);

    expect(registrarEtapaDaAbordagem).toHaveBeenCalledWith(mensagem);
    expect(ctx.$store.dispatch).not.toHaveBeenCalled();
  });

  // Bloco 5.17 — os dois verbos vao para acoes DIFERENTES do store. Se ambos caissem em
  // `contacts/setUser`, o `update-user` mesclaria nada e o campo omitido seria apagado — o
  // defeito que o verbo novo existe para evitar, e que nenhum teste de nome pegaria.
  it('set-user e update-user despacham acoes distintas', () => {
    const ctx = buildContext();

    handlers['set-user']({ identifier: 'u-1', user: { name: 'Ana' } }, ctx);
    handlers['update-user'](
      { identifier: 'u-1', user: { phone_number: '+5511' } },
      ctx
    );

    expect(ctx.$store.dispatch).toHaveBeenNthCalledWith(1, 'contacts/setUser', {
      identifier: 'u-1',
      user: { name: 'Ana' },
    });
    expect(ctx.$store.dispatch).toHaveBeenNthCalledWith(
      2,
      'contacts/updateUser',
      {
        identifier: 'u-1',
        user: { phone_number: '+5511' },
      }
    );
  });

  // Bloco 5.16 — `track()` do site. O verbo NOVO nao pode cair na acao do verbo antigo:
  // `push-event` vai ao barramento interno pelo nome, `track-event` vai ao registro de
  // tracking com properties e volta com `event_id`. Um teste de nome nao pegaria a troca.
  it('track-event despacha events/track com nome, properties e a chave de idempotencia', () => {
    const ctx = buildContext();

    handlers['track-event'](
      {
        event: 'track-event',
        name: 'chatspx_orcamento_pedido',
        properties: { plano: 'pro' },
        eventKey: 'k-1',
      },
      ctx
    );

    expect(ctx.$store.dispatch).toHaveBeenCalledWith('events/track', {
      name: 'chatspx_orcamento_pedido',
      properties: { plano: 'pro' },
      eventKey: 'k-1',
    });
  });

  it('push-event e track-event vao para acoes DIFERENTES do store', () => {
    const ctx = buildContext();

    handlers['push-event'](
      { event: 'push-event', eventName: 'webwidget.triggered' },
      ctx
    );
    handlers['track-event'](
      { event: 'track-event', name: 'chatspx_x', eventKey: 'k' },
      ctx
    );

    expect(ctx.$store.dispatch.mock.calls.map(c => c[0])).toEqual([
      'events/create',
      'events/track',
    ]);
  });

  it('config-set aplica locale, rótulo, config e busca as conversas antigas', async () => {
    const ctx = buildContext();
    handlers['config-set'](
      {
        event: 'config-set',
        locale: 'pt_BR',
        campaignsSnoozedTill: 1739000000000,
      },
      ctx
    );

    expect(ctx.setLocale).toHaveBeenCalledWith('pt_BR');
    expect(ctx.setBubbleLabel).toHaveBeenCalledTimes(1);
    expect(ctx.fetchAvailableAgents).toHaveBeenCalledWith('token-do-site');
    expect(ctx.$store.dispatch).toHaveBeenCalledWith('appConfig/setAppConfig', {
      event: 'config-set',
      locale: 'pt_BR',
      campaignsSnoozedTill: 1739000000000,
    });
    expect(ctx.$store.dispatch).toHaveBeenCalledWith('contacts/get');
    expect(ctx.setCampaignReadData).toHaveBeenCalledWith(1739000000000);
    await Promise.resolve();
    expect(ctx.setUnreadView).toHaveBeenCalledTimes(1);
  });

  it('widget-visible rola a conversa para o fim', () => {
    const ctx = buildContext();
    handlers['widget-visible']({ event: 'widget-visible' }, ctx);
    expect(ctx.scrollConversationToBottom).toHaveBeenCalledTimes(1);
  });

  it('change-url inicia campanhas com a URL e guarda o host de origem', () => {
    const ctx = buildContext({ isInWorkingHours: false });
    handlers['change-url'](
      {
        event: 'change-url',
        referrerURL: 'https://loja.exemplo.com/carrinho',
        referrerHost: 'loja.exemplo.com',
      },
      ctx
    );

    expect(ctx.$store.dispatch).toHaveBeenCalledWith('campaign/initCampaigns', {
      currentURL: 'https://loja.exemplo.com/carrinho',
      websiteToken: 'token-do-site',
      isInBusinessHours: false,
    });
    expect(window.referrerURL).toBe('https://loja.exemplo.com/carrinho');
    expect(ctx.$store.dispatch).toHaveBeenCalledWith(
      'appConfig/setReferrerHost',
      'loja.exemplo.com'
    );
  });

  it('toggle-close-button escreve isMobile no contexto', () => {
    const ctx = buildContext();
    handlers['toggle-close-button'](
      { event: 'toggle-close-button', isMobile: true },
      ctx
    );
    expect(ctx.isMobile).toBe(true);
  });

  it('push-event cria o evento pelo nome', () => {
    const ctx = buildContext();
    handlers['push-event'](
      { event: 'push-event', eventName: 'checkout.iniciado' },
      ctx
    );
    expect(ctx.$store.dispatch).toHaveBeenCalledWith('events/create', {
      name: 'checkout.iniciado',
    });
  });

  it('push-event NÃO cria webwidget.triggered nas views de não lidas e campanha', () => {
    const ctx = buildContext({ $route: { name: 'campaigns' } });
    handlers['push-event'](
      { event: 'push-event', eventName: 'webwidget.triggered' },
      ctx
    );
    expect(ctx.$store.dispatch).not.toHaveBeenCalled();
  });

  it('set-label cria o rótulo', () => {
    const ctx = buildContext();
    handlers['set-label']({ event: 'set-label', label: 'vip' }, ctx);
    expect(ctx.$store.dispatch).toHaveBeenCalledWith(
      'conversationLabels/create',
      'vip'
    );
  });

  it('remove-label destrói o rótulo', () => {
    const ctx = buildContext();
    handlers['remove-label']({ event: 'remove-label', label: 'vip' }, ctx);
    expect(ctx.$store.dispatch).toHaveBeenCalledWith(
      'conversationLabels/destroy',
      'vip'
    );
  });

  it('set-user repassa a mensagem inteira (identifier + user)', () => {
    const ctx = buildContext();
    const message = {
      event: 'set-user',
      identifier: 'cliente-9',
      user: { email: 'cliente@exemplo.com' },
    };
    handlers['set-user'](message, ctx);
    expect(ctx.$store.dispatch).toHaveBeenCalledWith(
      'contacts/setUser',
      message
    );
  });

  it('set-custom-attributes envia os atributos do CONTATO', () => {
    const ctx = buildContext();
    handlers['set-custom-attributes'](
      { event: 'set-custom-attributes', customAttributes: { plano: 'ouro' } },
      ctx
    );
    expect(ctx.$store.dispatch).toHaveBeenCalledWith(
      'contacts/setCustomAttributes',
      { plano: 'ouro' }
    );
  });

  it('delete-custom-attribute apaga o atributo do CONTATO pela chave', () => {
    const ctx = buildContext();
    handlers['delete-custom-attribute'](
      { event: 'delete-custom-attribute', customAttribute: 'plano' },
      ctx
    );
    expect(ctx.$store.dispatch).toHaveBeenCalledWith(
      'contacts/deleteCustomAttribute',
      'plano'
    );
  });

  it('set-conversation-custom-attributes envia os atributos da CONVERSA', () => {
    const ctx = buildContext();
    handlers['set-conversation-custom-attributes'](
      {
        event: 'set-conversation-custom-attributes',
        customAttributes: { pedido: '123' },
      },
      ctx
    );
    expect(ctx.$store.dispatch).toHaveBeenCalledWith(
      'conversation/setCustomAttributes',
      { pedido: '123' }
    );
  });

  it('delete-conversation-custom-attribute apaga o atributo da CONVERSA', () => {
    const ctx = buildContext();
    handlers['delete-conversation-custom-attribute'](
      {
        event: 'delete-conversation-custom-attribute',
        customAttribute: 'pedido',
      },
      ctx
    );
    expect(ctx.$store.dispatch).toHaveBeenCalledWith(
      'conversation/deleteCustomAttribute',
      'pedido'
    );
  });

  it('set-locale troca o idioma e reescreve o rótulo da bolha', () => {
    const ctx = buildContext();
    handlers['set-locale']({ event: 'set-locale', locale: 'es' }, ctx);
    expect(ctx.setLocale).toHaveBeenCalledWith('es');
    expect(ctx.setBubbleLabel).toHaveBeenCalledTimes(1);
  });

  it('set-color-scheme repassa o modo escuro', () => {
    const ctx = buildContext();
    handlers['set-color-scheme'](
      { event: 'set-color-scheme', darkMode: 'dark' },
      ctx
    );
    expect(ctx.$store.dispatch).toHaveBeenCalledWith(
      'appConfig/setColorScheme',
      'dark'
    );
  });

  it('toggle-open abrindo em home com mensagens vai para a lista de mensagens', () => {
    const ctx = buildContext({ $route: { name: 'home' }, messageCount: 4 });
    handlers['toggle-open']({ event: 'toggle-open', isOpen: true }, ctx);

    expect(ctx.$store.dispatch).toHaveBeenCalledWith(
      'appConfig/toggleWidgetOpen',
      true
    );
    expect(ctx.router.replace).toHaveBeenCalledWith({ name: 'messages' });
    expect(ctx.$store.dispatch).not.toHaveBeenCalledWith(
      'campaign/resetCampaign'
    );
  });

  it('toggle-open fechando na view de não lidas volta para home e zera a campanha', () => {
    const ctx = buildContext({ $route: { name: 'unread-messages' } });
    handlers['toggle-open']({ event: 'toggle-open', isOpen: false }, ctx);

    expect(ctx.$store.dispatch).toHaveBeenCalledWith(
      'conversation/setUserLastSeen'
    );
    expect(ctx.unsetUnreadView).toHaveBeenCalledTimes(1);
    expect(ctx.router.replace).toHaveBeenCalledWith({ name: 'home' });
    expect(ctx.$store.dispatch).toHaveBeenCalledWith('campaign/resetCampaign');
  });

  it('sdk-set-bubble-visibility repassa a visibilidade da bolha', () => {
    const ctx = buildContext();
    handlers['sdk-set-bubble-visibility'](
      { event: 'sdk-set-bubble-visibility', hideMessageBubble: true },
      ctx
    );
    expect(ctx.$store.dispatch).toHaveBeenCalledWith(
      'appConfig/setBubbleVisibility',
      true
    );
  });
});
