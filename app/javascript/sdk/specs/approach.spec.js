/**
 * Os aceites do 4.19 (degradação por familiaridade) e do 4.20 (auto-open opt-in),
 * exercidos onde eles de fato decidem: `IFrameHelper.montarTeaserSeConfigurado`.
 *
 * O teste percorre TRÊS VISITAS de verdade — remontando o host entre elas, com o
 * cookie sobrevivendo, como sobrevive num navegador. Testar `degradar()` isolado
 * provaria que um array tem índices; o que o aceite cobra é o cartão que aparece
 * na segunda visita ser menor que o da primeira, e o da terceira não existir.
 */
import Cookies from 'js-cookie';
import { MOBILE_BREAKPOINT } from '../viewport';

const CANAL = {
  avatarUrl: 'https://exemplo.test/a.png',
  // Ver a nota do 4.05 em `teaser.spec.js`: o balão lê `teaserText`, não `welcomeTagline`.
  teaserText: 'Fale com a gente',
  replyTime: 'Responde em minutos',
};

// O dublê de viewport NÃO carrega mais o número: ele vem de `viewport.js`, que é a fonte
// única do bloco 2.09. Antes estava cravado `667` aqui e na consulta abaixo, e isso escondia
// uma divergência real — o `IFrameHelper` consultava `667` (herdado do 4.06) enquanto o CSS
// já usava 767, e um dublê que repete o número errado concorda com o defeito em vez de
// denunciá-lo. Com a fonte importada, mudar o breakpoint num lugar só continua verde aqui.
const CELULAR = MOBILE_BREAKPOINT - 1;

// Cada visita remonta o grafo do SDK (`vi.resetModules()` + import dinâmico), e são
// até três por exemplo. Sob a suíte inteira isso passa dos 5 s padrão do vitest —
// o que reprova por relógio, não por comportamento.
describe('4.19 e 4.20 — a escada da abordagem', { timeout: 30_000 }, () => {
  let IFrameHelper;
  let holder;
  let aberturas;
  let enviados;

  const bootHost = async (gatilhos, { largura = 1280 } = {}) => {
    vi.resetModules();
    document.body.innerHTML = '';
    holder = document.createElement('div');
    document.body.appendChild(holder);

    // Uma página COM rolagem disponível, e o visitante no topo. Sem isto o
    // estado de scroll vaza de um teste para o outro e o gatilho composto passa
    // a disparar só com o tempo — que é exatamente o defeito que ele existe para
    // não ter.
    Object.defineProperty(document.documentElement, 'scrollHeight', {
      value: 2000,
      configurable: true,
    });
    window.innerHeight = 1000;
    window.scrollY = 0;

    window.$chatwoot = { baseDomain: undefined, position: 'right' };
    window.chatwootWebChannel = { ...CANAL, widgetTriggers: gatilhos };
    window.matchMedia = consulta => ({
      matches:
        largura <= CELULAR && consulta.includes(`max-width: ${CELULAR}px`),
    });
    global.requestAnimationFrame = cb => cb();

    ({ IFrameHelper } = await import('../IFrameHelper'));
    // O painel não existe neste teste; interessa QUANTAS vezes pediram para abrir.
    IFrameHelper.events.toggleBubble = estado => aberturas.push(estado);
    IFrameHelper.sendMessage = (evento, corpo) =>
      enviados.push({ evento, ...corpo });
    IFrameHelper.montarTeaserSeConfigurado(holder);
  };

  const dispararGatilho = () => {
    window.scrollY = 400; // 40% > 30%
    window.dispatchEvent(new Event('scroll'));
    vi.advanceTimersByTime(8000);
  };

  const cartao = () => holder.querySelector('.woot-teaser');

  beforeEach(() => {
    vi.useFakeTimers();
    aberturas = [];
    enviados = [];
    Cookies.remove('cw_approach');
    Cookies.remove('cw_teaser_dismissed');
    sessionStorage.clear();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  // ── 4.19 ────────────────────────────────────────────────────────────────────
  it('bold: 1ª visita mostra o grande, 2ª o pequeno, 3ª não mostra nada', async () => {
    await bootHost({
      enabled: true,
      approach: 'bold',
      degrade_on_return: true,
    });
    dispararGatilho();
    expect(cartao().className).toContain('woot-teaser--bold');
    expect(Cookies.get('cw_approach')).toBe('1.0');

    await bootHost({
      enabled: true,
      approach: 'bold',
      degrade_on_return: true,
    });
    dispararGatilho();
    expect(cartao().className).toContain('woot-teaser--discreet');
    expect(Cookies.get('cw_approach')).toBe('2.0');

    await bootHost({
      enabled: true,
      approach: 'bold',
      degrade_on_return: true,
    });
    dispararGatilho();
    expect(cartao()).toBeNull();
    // Não abordou, então não gastou degrau: o cookie não mexeu.
    expect(Cookies.get('cw_approach')).toBe('2.0');
  });

  it('o contador sobe quando ABORDAMOS, não quando a página carrega', async () => {
    await bootHost({ enabled: true, approach: 'bold' });
    // Visitante que não rolou e foi embora antes dos 8 s: nada aconteceu.
    expect(Cookies.get('cw_approach')).toBeUndefined();
  });

  it('converter zera o contador — e a visita seguinte volta ao nível cheio', async () => {
    await bootHost({ enabled: true, approach: 'bold' });
    dispararGatilho();
    expect(Cookies.get('cw_approach')).toBe('1.0');

    IFrameHelper.events.onEvent({
      eventIdentifier: 'chatwoot:message-sent',
      data: {},
    });
    expect(Cookies.get('cw_approach')).toBe('0.1');

    await bootHost({ enabled: true, approach: 'bold' });
    dispararGatilho();
    expect(cartao().className).toContain('woot-teaser--bold');
  });

  it('com degrade_on_return: false o nível não cai nunca', async () => {
    const gatilhos = {
      enabled: true,
      approach: 'bold',
      degrade_on_return: false,
    };
    // Três visitas, escritas em sequência e não em laço: a ORDEM é o objeto do
    // teste, e um `await` dentro de `for` esconde isso atrás de uma repetição.
    const visitar = async () => {
      await bootHost(gatilhos);
      dispararGatilho();
      return cartao().className;
    };

    expect(await visitar()).toContain('woot-teaser--bold');
    expect(await visitar()).toContain('woot-teaser--bold');
    expect(await visitar()).toContain('woot-teaser--bold');
    // O contador continua contando — é o que mantém o ordinal único na dedup.
    expect(Cookies.get('cw_approach')).toBe('3.0');
  });

  it('o cookie é de primeira parte, 30 dias, e passa pela helper de domínio', async () => {
    const espia = vi.spyOn(
      await import('../cookieHelpers'),
      'setCookieWithDomain'
    );
    const { gravarAbordagem } = await import('../tracking/approach');
    gravarAbordagem(1, false, 'exemplo.test');

    expect(espia).toHaveBeenCalledWith('cw_approach', '1.0', {
      expires: 30,
      baseDomain: 'exemplo.test',
    });
    espia.mockRestore();
  });

  it('o cookie guarda DUAS coisas, e nada mais', async () => {
    await bootHost({ enabled: true, approach: 'bold' });
    dispararGatilho();
    expect(Cookies.get('cw_approach')).toMatch(/^\d+\.[01]$/);
  });

  // ── 4.20 ────────────────────────────────────────────────────────────────────
  it('aggressive abre o painel sozinho, uma vez por sessão', async () => {
    const gatilhos = {
      enabled: true,
      approach: 'aggressive',
      degrade_on_return: false,
    };

    await bootHost(gatilhos);
    dispararGatilho();
    expect(aberturas).toEqual(['open']);
    // Sem cartão: o Agressivo não é teaser.
    expect(cartao()).toBeNull();

    // Outra página, mesma sessão.
    await bootHost(gatilhos);
    dispararGatilho();
    expect(aberturas).toEqual(['open']);
  });

  it('aggressive respeita o gatilho composto — 8 s sozinhos não abrem', async () => {
    await bootHost({ enabled: true, approach: 'aggressive' });
    vi.advanceTimersByTime(8000);
    expect(aberturas).toEqual([]);
  });

  it('sessão já usada não conta como abordagem (não gasta degrau)', async () => {
    const gatilhos = {
      enabled: true,
      approach: 'aggressive',
      degrade_on_return: false,
    };
    await bootHost(gatilhos);
    dispararGatilho();
    expect(Cookies.get('cw_approach')).toBe('1.0');

    await bootHost(gatilhos);
    dispararGatilho();
    expect(Cookies.get('cw_approach')).toBe('1.0');
  });

  it('em 375 px o painel NÃO abre sozinho — approach_mobile é lido sozinho', async () => {
    await bootHost(
      // O servidor nunca manda isto (3.20 recusa `aggressive` em
      // `approach_mobile` com 422 e `resolved_widget_approach` derruba para
      // `bold`). O teste finge um payload adulterado para provar que o SDK NÃO
      // cai para `approach` no celular — é a terceira ponta do aceite.
      { enabled: true, approach: 'aggressive', approach_mobile: 'bold' },
      { largura: 375 }
    );
    dispararGatilho();
    expect(aberturas).toEqual([]);
    expect(cartao().className).toContain('woot-teaser--bold');
  });

  it('sem approach_mobile no payload, o celular NÃO herda o aggressive do desktop', async () => {
    await bootHost({ enabled: true, approach: 'aggressive' }, { largura: 375 });
    dispararGatilho();
    expect(aberturas).toEqual([]);
  });

  it('sem `enabled: true` nada dispara, em nível nenhum', async () => {
    await bootHost({ approach: 'aggressive' });
    dispararGatilho();
    expect(aberturas).toEqual([]);
    expect(cartao()).toBeNull();
    expect(enviados).toEqual([]);
  });

  // ── 4.21 ────────────────────────────────────────────────────────────────────
  it('a exibição vira dado, com o nível e o configurado separados', async () => {
    await bootHost({ enabled: true, approach: 'bold' });
    dispararGatilho();
    await bootHost({ enabled: true, approach: 'bold' });
    dispararGatilho();

    const eventos = enviados.filter(e => e.evento === 'approach-event');
    expect(eventos).toEqual([
      {
        evento: 'approach-event',
        etapa: 'shown',
        approach: 'bold',
        approach_configured: 'bold',
        ordinal: 1,
      },
      {
        evento: 'approach-event',
        etapa: 'shown',
        approach: 'discreet',
        approach_configured: 'bold',
        ordinal: 2,
      },
    ]);
  });

  it('dispensa e abertura também viram dado, com o mesmo ordinal', async () => {
    await bootHost({ enabled: true, approach: 'bold' });
    dispararGatilho();

    holder.querySelector('.woot-teaser__fechar').click();
    const dispensa = enviados.at(-1);
    expect(dispensa.etapa).toBe('dismissed');
    expect(dispensa.ordinal).toBe(1);
  });

  it('o auto-open do aggressive também é exibição, e é o denominador dele', async () => {
    await bootHost({ enabled: true, approach: 'aggressive' });
    dispararGatilho();

    const etapas = enviados
      .filter(e => e.evento === 'approach-event')
      .map(e => e.etapa);
    expect(etapas).toEqual(['shown', 'opened']);
    expect(enviados.at(-1).approach).toBe('aggressive');
  });
});
