/**
 * Bloco 2.11 — o funil NÃO-LIDAS/CAMPANHA, que é por onde o `inert` escapava.
 *
 * O aceite do 2.11 diz "`inert` no fundo em mobile". A leitura ingênua disso é
 * "em celular, aplique". Está errada: em celular o painel só ocupa a tela
 * quando está ABERTO DE VERDADE. No modo não-lidas o mesmo holder recebe
 * `has-unread-view` e o CSS o encolhe para uma tirinha no rodapé
 * (`sdk.js`: `height:auto; bottom:0; top:auto; width:auto`) — a página do
 * cliente continua inteira à vista, e marcá-la `inert` a mata para toque,
 * teclado e leitor de tela sem nenhum sinal visual do porquê.
 *
 * E o caminho de volta era pior que a ida: `resetUnreadMode` parava o piscar e
 * tirava a classe, mas nunca soltava o `inert`. Campanha ou resposta de agente
 * em 375 px deixava a página morta para sempre.
 *
 * Por isso a decisão aqui não é "aplicar" nem "soltar": é RECALCULAR
 * (`syncInertBackground`) a partir do estado real do holder, em cada porta do
 * funil. As portas são as que o `App.vue` do widget aciona:
 *   · `setUnreadView`/`setCampaignView`  → `setUnreadMode`
 *   · `unsetUnreadView`                  → `resetUnreadMode`
 *   · `toggle-open` com `isOpen:false`   → `closeWindow`
 *
 * O DOM montado aqui é o REAL: o mesmo `widgetHolder` que `createFrame` põe no
 * body, com a mesma string de classes (`holderClassName`), porque
 * `addUnreadClass` procura por `.woot-widget-holder` no documento e um `div`
 * de mentira faria o teste medir outro nó que não o do produto.
 */
import { IFrameHelper } from '../IFrameHelper';
import { applyInertBackground } from '../inertBackground';
import {
  widgetHolder,
  chatBubble,
  closeBubble,
  bubbleHolder,
} from '../bubbleHelpers';

const larguraDaTela = largura => {
  window.matchMedia = query => ({
    matches: Number(/max-width:\s*(\d+)px/.exec(query)?.[1] ?? 0) >= largura,
    media: query,
    addEventListener: () => {},
    removeEventListener: () => {},
  });
};

/** A página do cliente + o widget montado como o boot monta. */
const montarPagina = () => {
  document.body.innerHTML = '';
  const conteudo = document.createElement('main');
  conteudo.innerHTML = '<a href="/precos">Preços</a>';
  document.body.appendChild(conteudo);

  // Exatamente o que `IFrameHelper.createFrame` escreve (`holderClassName`).
  widgetHolder.className = 'woot-widget-holder woot--hide woot-elements--right';
  bubbleHolder.id = 'cw-bubble-holder';
  [widgetHolder, bubbleHolder, chatBubble, closeBubble].forEach(el =>
    document.body.appendChild(el)
  );

  return conteudo;
};

describe('2.11 — inert não pode congelar a página no modo não-lidas', () => {
  let conteudo;

  beforeEach(() => {
    conteudo = montarPagina();
    window.$chatwoot = { isOpen: false, hideMessageBubble: false };
    // A ponte com o iframe não existe no jsdom, e não é o que se mede aqui:
    // só o fio é dublado — `events.setUnreadMode` e `events.resetUnreadMode`
    // continuam sendo os do produto.
    IFrameHelper.sendMessage = vi.fn();
    IFrameHelper.pushEvent = vi.fn();
    IFrameHelper.titleFlasher = { start: vi.fn(), stop: vi.fn() };
    larguraDaTela(375);
  });

  it('celular + modo não-lidas: a página do cliente CONTINUA viva', () => {
    IFrameHelper.events.setUnreadMode();

    expect(widgetHolder.classList.contains('has-unread-view')).toBe(true);
    expect(conteudo.hasAttribute('inert')).toBe(false);
  });

  it('celular + campanha: idem — é o MESMO evento e a mesma tirinha', () => {
    // `setCampaignView` do `App.vue` manda o mesmo `setUnreadMode`; o que muda
    // é só a rota dentro do iframe, que o host nem vê.
    IFrameHelper.events.setUnreadMode();

    expect(conteudo.hasAttribute('inert')).toBe(false);
  });

  it('resetUnreadMode com o painel FECHADO solta o inert grudado', () => {
    // A condição ruim é FORÇADA, não esperada: é exatamente o resíduo que a
    // versão antiga deixava — `inert` na página com o painel fora da tela,
    // porque `resetUnreadMode` só parava o piscar e tirava a classe. Sem
    // forçar, a asserção passaria pelo motivo errado (nunca houve `inert`).
    applyInertBackground();
    expect(conteudo.hasAttribute('inert')).toBe(true);

    IFrameHelper.events.resetUnreadMode();

    expect(conteudo.hasAttribute('inert')).toBe(false);
  });

  it('resetUnreadMode com o painel indo a TELA CHEIA mantém — não é um release seco', () => {
    // O outro destino do mesmo evento: o visitante tocou a tirinha, o widget
    // trocou para a conversa e o painel voltou a ocupar a tela. Aqui soltar
    // seria reabrir a página atrás de um painel de tela cheia — o defeito que
    // o 2.11 existe para corrigir.
    IFrameHelper.events.setUnreadMode();
    expect(conteudo.hasAttribute('inert')).toBe(false);

    IFrameHelper.events.resetUnreadMode();

    expect(conteudo.hasAttribute('inert')).toBe(true);
  });

  it('o ciclo real campanha → fechar devolve a página', () => {
    // Painel fechado, campanha chega (tirinha), visitante fecha pelo X de
    // dentro do iframe. Em nenhum instante a página do cliente pode morrer.
    IFrameHelper.events.setUnreadMode();
    expect(conteudo.hasAttribute('inert')).toBe(false);

    IFrameHelper.events.closeWindow();

    expect(conteudo.hasAttribute('inert')).toBe(false);
    expect(widgetHolder.classList.contains('has-unread-view')).toBe(false);
  });

  it('painel em tela cheia continua marcando — a correção não desliga o 2.11', () => {
    IFrameHelper.events.toggleBubble('open');

    expect(conteudo.hasAttribute('inert')).toBe(true);
  });

  it('desktop nunca marca, nem em tela cheia nem em não-lidas', () => {
    larguraDaTela(1280);

    IFrameHelper.events.toggleBubble('open');
    expect(conteudo.hasAttribute('inert')).toBe(false);

    IFrameHelper.events.setUnreadMode();
    expect(conteudo.hasAttribute('inert')).toBe(false);
  });
});
