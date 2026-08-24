/**
 * A JUNÇÃO 4.05 ↔ 4.06 — o texto que o cliente escreve é o texto que o visitante lê.
 *
 * O bloco 4.05 diz "campanha é MENSAGEM, gatilho é MOMENTO", e por isso o compositor da
 * Tela 2 (`TeaserComposer.vue`) não cria campanha nenhuma: ele EDITA a campanha de chat ao
 * vivo que a inbox já tem. O preview da mesma tela (4.07) já mostra
 * `rascunho.message || campanha.message` — o contrato está escrito lá, em
 * `TriggersPage.vue:143-145`.
 *
 * O teaser de verdade, o que vive no host, mostrava `canal.welcomeTagline`, que é outro
 * campo, editado em OUTRA tela. Duas consequências, e as duas são o defeito:
 *
 *   · o cliente escreve na Tela 2 e o visitante lê o que está na Tela 1 — o preview mente;
 *   · com o gatilho novo ligado (4.22), a campanha legada para de disparar sozinha, então o
 *     texto escrito no compositor deixa de aparecer em QUALQUER lugar.
 *
 * ─── ONDE A PRECEDÊNCIA MORA, E POR QUÊ ──────────────────────────────────────────────────
 * No SERVIDOR: `Channel::WebWidget#teaser_text` resolve campanha → `welcome_tagline` →
 * `welcome_title` e manda o resultado pronto em `teaserText`. É o padrão que o host já segue
 * para cor (1.02/1.03) e para o nível de abordagem (3.20) — e devolve bytes ao `sdk.js`, que
 * tem seis de folga no gzip (A13). A cobertura da precedência é do
 * `spec/models/channel/web_widget_teaser_spec.rb`; aqui se verifica o que o host faz com o
 * valor que chega.
 *
 * ─── ESTE SPEC ACUSA, e é preciso dizer contra o quê ─────────────────────────────────────
 * Todo exemplo põe `teaserText` (a campanha resolvida) e `welcomeTagline` (o campo da Tela 1)
 * JUNTOS, com textos diferentes, e exige o primeiro. Um exemplo que mandasse só `teaserText`
 * passaria no código velho por acidente do fallback — não mediria nada.
 *
 * O segundo grupo cobre o outro elo da mesma junção: `window.chatwootWebChannel` só existe
 * dentro do IFRAME (`app/views/widgets/show.html.erb`). No documento do SITE do cliente ele
 * nunca foi definido — o canal chega ao host pela ponte, em `message.config.channelConfig`
 * (`widget/helpers/IframeEventHelper.js:49`). Por isso o exemplo APAGA o global antes de
 * bootar: é assim que a página do cliente é.
 */
import Cookies from 'js-cookie';
import { montarTeaser } from '../teaser';

// A campanha vinculada e o campo da Tela 1 dizem coisas DIFERENTES, de propósito.
const MENSAGEM_DA_CAMPANHA = 'Posso te ajudar a escolher o plano?';
const TAGLINE_DA_INBOX = 'Estamos online';

const CANAL = {
  avatarUrl: 'https://exemplo.test/a.png',
  welcomeTagline: TAGLINE_DA_INBOX,
  welcomeTitle: 'Olá!',
  replyTime: 'Responde em minutos',
};

const paginaRolavel = () => {
  Object.defineProperty(document.documentElement, 'scrollHeight', {
    value: 3000,
    configurable: true,
  });
  window.innerHeight = 1000;
  window.scrollY = 0;
};

/** O gatilho composto do 4.06: 30% de rolagem E 8 s. */
const dispararGatilhoComposto = () => {
  window.scrollY = 1000; // 50% de 2000 px roláveis
  window.dispatchEvent(new Event('scroll'));
  vi.advanceTimersByTime(8000);
};

describe('4.05 ↔ 4.06 — o teaser mostra a mensagem da campanha vinculada', () => {
  let holder;

  beforeEach(() => {
    vi.useFakeTimers();
    document.body.innerHTML = '';
    holder = document.createElement('div');
    document.body.appendChild(holder);
    Cookies.remove('cw_teaser_dismissed');
    window.scrollY = 0;
    global.requestAnimationFrame = cb => cb();
    paginaRolavel();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  const montarEExibir = canal => {
    const desmontar = montarTeaser({ holder, canal, nivel: 'bold' });
    dispararGatilhoComposto();
    const texto = holder.querySelector('.woot-teaser__texto')?.textContent;
    if (desmontar) desmontar();
    return texto;
  };

  it('mostra o texto resolvido da campanha, não o welcome_tagline da inbox', () => {
    expect(montarEExibir({ ...CANAL, teaserText: MENSAGEM_DA_CAMPANHA })).toBe(
      MENSAGEM_DA_CAMPANHA
    );
  });

  it('editar o texto da campanha muda o que o visitante lê — é o aceite do 4.05', () => {
    // O ACEITE, ao pé da letra. Não basta "o campo é lido uma vez": o cliente salva de novo
    // no compositor, o boot seguinte traz outro `teaserText`, e o visitante tem de ler o
    // texto NOVO. Se a junção estiver quebrada, os dois lados devolvem a mesma tagline e a
    // última asserção denuncia.
    const antes = montarEExibir({ ...CANAL, teaserText: 'Frete grátis hoje' });
    const depois = montarEExibir({
      ...CANAL,
      teaserText: 'Últimas unidades com 20% off',
    });

    expect(antes).toBe('Frete grátis hoje');
    expect(depois).toBe('Últimas unidades com 20% off');
    expect(depois).not.toBe(antes);
  });

  it('o host NÃO tem mais precedência própria — sem `teaserText` o balão sai vazio', () => {
    // Não é descuido, é o contrato: quem decide entre campanha, `welcome_tagline` e
    // `welcome_title` é `Channel::WebWidget#teaser_text`, e `teaserText` nunca chega ausente
    // de um servidor desta versão. Uma segunda cadeia de precedência aqui é exatamente o que
    // fez o cliente editar um campo e o visitante ler outro.
    expect(montarEExibir({ ...CANAL })).toBe('');
  });
});

describe('4.05 ↔ 4.06 — a campanha chega ao HOST pela ponte, não por variável global', () => {
  let IFrameHelper;

  const CANAL_DO_BOOT = {
    ...CANAL,
    teaserText: MENSAGEM_DA_CAMPANHA,
    widgetTriggers: { enabled: true, approach: 'bold' },
    tokens: { '--w-brand': '#009ce0', '--w-on-brand': '#000000' },
    widgetColor: '#009ce0',
  };

  beforeEach(async () => {
    vi.useFakeTimers();
    vi.resetModules();
    document.body.innerHTML = '';
    Cookies.remove('cw_teaser_dismissed');
    Cookies.remove('cw_approach');

    // ⚠️ O PONTO DESTE GRUPO. `window.chatwootWebChannel` é escrito por
    // `app/views/widgets/show.html.erb`, que é o documento do IFRAME. A página do cliente
    // nunca o teve. Apagar aqui não é fabricar um cenário — é parar de fabricar um.
    delete window.chatwootWebChannel;

    window.$chatwoot = {
      position: 'right',
      hideMessageBubble: false,
      widgetStyle: 'standard',
      type: 'standard',
      baseUrl: 'https://chat.exemplo.test',
      baseDomain: undefined,
    };
    window.matchMedia = () => ({ matches: false });
    global.requestAnimationFrame = cb => cb();
    paginaRolavel();

    // O `onLoad` real roda depois de `createFrame`, então o iframe já está na página.
    const frame = document.createElement('iframe');
    frame.id = 'chatwoot_live_chat_widget';
    document.body.appendChild(frame);

    ({ IFrameHelper } = await import('../IFrameHelper'));
    IFrameHelper.sendMessage = () => {};
    IFrameHelper.events.toggleBubble = () => {};
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('monta o teaser com a mensagem da campanha que veio em channelConfig', () => {
    // `onLoad` é o ÚNICO caminho de montagem do teaser em produção
    // (`IFrameHelper.js`, última linha de `onLoad`), e o canal que ele recebe é o que
    // atravessou o postMessage. Enquanto o host lia o global, não havia teaser nenhum em
    // site real — e o `expect(texto).not.toBeNull()` abaixo era o que denunciava.
    IFrameHelper.onLoad({
      widgetColor: CANAL_DO_BOOT.widgetColor,
      tokens: CANAL_DO_BOOT.tokens,
      channelConfig: CANAL_DO_BOOT,
    });

    dispararGatilhoComposto();

    const texto = document.querySelector('.woot-teaser__texto');
    expect(texto).not.toBeNull();
    expect(texto.textContent).toBe(MENSAGEM_DA_CAMPANHA);
  });
});
