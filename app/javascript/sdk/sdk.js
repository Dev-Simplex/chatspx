/**
 * DOCUMENTAÇÃO DO `SDK_CSS` — mora AQUI, fora da template string, e isso não é
 * arrumação: comentário dentro de uma string é DADO, não comentário. O
 * minificador não toca no conteúdo de strings, então cada linha de explicação
 * escrita entre `/*` e `*\/` lá dentro era baixada por 100% dos visitantes de
 * todos os sites de todos os clientes.
 *
 * Medido: 5.616 B crus de comentário dentro do `SDK_CSS`, que valiam
 * **2.924 B gzip** no artefato — mais que a folga inteira do teto da A13.
 * Movê-los para cá não perdeu uma palavra e devolveu esse espaço.
 *
 * Abaixo, cada explicação com a regra que ela documenta.
 *
 * ── #cw-widget-holder, #cw-bubble-holder
 *   Tokens que NÃO dependem da inbox (borda, alerta, superfície do badge).
 *   Declarados nos NOSSOS dois containers, nunca no ':root' do host: o documento
 *   é do cliente, e um site com '--w-*' próprio nos sobrescreveria — é a mesma
 *   decisão que o bloco 1.03 tomou para os tokens que vêm do servidor.
 *   Os tokens de MARCA ('--w-brand', '--w-on-brand', …) não aparecem aqui de
 *   propósito: quem os escreve é 'applyWidgetTokens', com o valor que o servidor
 *   calculou para a inbox.
 *
 *   '--w-text', '--w-text-subtle' e '--w-text-muted' entraram no bloco 1.05 e são
 *   os três últimos literais de cor que restavam em DECLARAÇÃO do 'SDK_CSS' — os
 *   do teaser. Nomeá-los aqui não é arrumação: enquanto a cor mora na declaração,
 *   ninguém consegue trocá-la sem editar a string, e a folha volta a ser a segunda
 *   fonte de verdade de cor que esta onda existe para matar. Os valores são os
 *   mesmos de antes, byte por byte, e os contrastes foram medidos contra a
 *   superfície em que cada um pousa (fórmula WCAG, mesma do 'WidgetTokens'):
 *     --w-text        #1f2d3d sobre --w-surface (#ffffff) = 13,9907:1
 *     --w-text-subtle #37546d sobre --w-border  (#F2F3F7) =  7,1429:1
 *     --w-text-muted  #6e6f73 sobre --w-surface (#ffffff) =  5,0187:1
 *   Nenhum depende da inbox, e por isso é AQUI que eles vivem — não no servidor.
 *
 * ── background-color: var(--w-on-brand, var(--w-surface));   content: ' ';
 *   O X do botão fechar, e o fallback é o conserto do bloco 1.05.
 *   'background-color' NÃO é propriedade herdada: quando '--w-on-brand' não está
 *   escrito no holder, o 'var()' é inválido no tempo de valor computado, a
 *   declaração vira 'unset' e cai no valor INICIAL — 'transparent'. Medido em
 *   Chromium com o holder recebendo só '--w-brand', que é o caminho da aba aberta
 *   antes do deploy do 1.02: 'rgba(0, 0, 0, 0)'. Ou seja, o X do fechar SUMIA, e
 *   antes deste bloco ele era '#fff' cravado — a conversão para variável tinha
 *   sido feita pela metade e trocou um literal por um botão invisível.
 *   Repare que o rótulo do lançador expandido ('color: var(--w-on-brand)', logo
 *   acima) NÃO tem o mesmo defeito: 'color' É herdada, então o 'unset' dela busca
 *   o pai — que é '.woot-widget-bubble', onde o fallback já existe. Medido no
 *   mesmo Chromium: 'rgb(255, 255, 255)'. Por isso ali o fallback não foi
 *   repetido: em arquivo com teto de bytes, fallback que não pinta nada é peso.
 *
 * ── --w-ease-standard: cubic-bezier(0.2, 0, 0, 1);   --w-ease-enter: cubic-bezier(
 *   As três curvas da casa (22 §D.2), repetidas aqui porque '_tokens.scss' só é
 *   carregado DENTRO do iframe e o lançador/holder vivem no documento do host.
 *   São os mesmos valores, e o spec de tokens compara os dois lados.
 *   'linear' fica permitido só para opacidade pura, rotação contínua e para os
 *   truques de 'visibility'/'bottom' com duração 0ms — nunca para 'transform'
 *   de uma superfície que entra ou sai, que é o que este bloco corrige.
 *
 * ── transition: opacity 0.2s linear, transform 0.25s var(--w-ease-enter);   z-inde
 *   Era 'transform 0.25s linear' — o painel subia a velocidade constante, que é
 *   o que faz uma superfície parecer empurrada em vez de aberta. A abertura usa
 *   a curva de entrada; a opacidade pode seguir linear, porque em opacidade pura
 *   'linear' é justamente o correto.
 *
 * ── color: var(--w-on-brand, var(--w-surface));   border-radius: 100px;   border-w
 *   'color' existe para o ícone herdar: o SVG do lançador usa
 *   fill="currentColor", então a cor do traço passa a vir de '--w-on-brand' —
 *   a mesma decisão WCAG que pinta o texto do painel.
 *   O fallback é '--w-surface' (branco) e vale só para a aba aberta antes do
 *   deploy do 1.02, que chega sem tokens: ali o ícone segue branco, que era
 *   exatamente o 'fill="#FFFFFF"' de antes.
 *
 * ── .woot-widget-bubble.woot-widget--expanded svg
 *   As três regras '.woot-widget-bubble-color--lighter' que viviam aqui, no 'path'
 *   e no 'woot--close' foram REMOVIDAS. Elas existiam para pintar de escuro
 *   ('--s-700: #37546D') quando a marca era clara, decisão tomada por
 *   'isWidgetColorLighter' — brilho 299/587/114, limiar 225, não-WCAG. Agora
 *   '--w-on-brand' já É essa decisão, calculada por luminância no servidor: as
 *   regras viraram duplicatas exatas da regra base e duplicata exata é ruído.
 *   A classe continua sendo aplicada pelo 1.03 (tem spec) como sinal semântico de
 *   "o servidor decidiu que esta marca é clara", mas não pinta mais nada.
 *
 * ── .woot-widget-bubble:hover
 *   O ':hover' repete '--w-brand' de propósito, e é o ponto mais perigoso da onda.
 *   Este seletor reaplicava '#2dc46f' cravado. O literal estava MORTO porque
 *   'IFrameHelper' escrevia 'chatIcon.style.background' inline, e inline vence
 *   folha sem '!important'; ao remover o inline (é o que este bloco faz), o
 *   literal RESSUSCITARIA e o lançador de qualquer cliente ficaria verde ao
 *   passar o mouse. O feedback de hover continua vindo do box-shadow, como hoje —
 *   por isso a cor é a mesma de repouso, e não '--w-brand-hover': o aceite do
 *   bloco exige que o lançador em '#009CE0' siga 'rgb(0,156,224)' EM hover, ou
 *   seja, sem mudança de matiz.
 *
 * ── .woot-widget-bubble img.woot-widget-bubble__photo
 *   ── BLOCO 3.19 · o lançador com foto ───────────────────────────────────────
 *   Asserção 8 — recorte "object-fit: cover" no círculo de 64 px congelado (§8 item 2).
 *   A bolha já é 64x64 com "overflow: hidden" e "border-radius: 100px"; a foto herda
 *   o raio e preenche. Foto retangular é RECORTADA, nunca esticada — sem isto um
 *   retrato 3:4 entorta o lançador na página do cliente.
 *
 * ── .woot-widget-bubble.woot-widget-bubble--has-photo
 *   Asserção 7 — anel/borda com ≥ 3:1 (SC 1.4.11).
 *   São DOIS anéis, e é o que torna o aceite atingível: o lançador pousa numa página
 *   de fundo desconhecido, então nenhuma cor sozinha garante 3:1 contra "o fundo".
 *   Os dois anéis contrastam ENTRE SI, de modo que a borda do controle continua
 *   perceptível sobre qualquer fundo — claro, escuro ou a própria cor da marca.
 *
 *   Um anel de UMA cor não resolve, e isso é demonstrável: >=3:1 contra branco exige
 *   luminância <= 0,30000; contra #171717 exige >= 0,12570; contra a marca #2dc46f
 *   exige <= 0,10395. O intervalo [0,12570 ; 0,10395] é VAZIO. Daí os dois anéis.
 *   Medidos: externo x marca 3,727 · externo x claro 4,759 · externo x anel interno
 *   4,759 · interno x escuro 17,928. Nenhum par abaixo de 3:1.
 *   O interior referencia "--w-brand-border", o token que a asserção 7 nomeia. ATENÇAO,
 *   e isto foi MEDIDO no merge com o 1.03: "--w-brand-border" NAO esta em
 *   'WIDGET_TOKEN_NAMES' (IframeEventHelper.js), que e lista FECHADA — 'applyWidgetTokens'
 *   descarta nome fora dela. Enquanto 1.02/1.03 nao acrescentarem o token, quem pinta e
 *   sempre o fallback branco, e e exatamente ele que os numeros acima medem: nenhum
 *   deles e aspiracional. Quando o token entrar na lista, os pares precisam ser
 *   remedidos com o valor real. Registrado no relatorio da trilha.
 *
 * ── .woot-teaser
 *   ── TEASER (bloco 4.06) ────────────────────────────────────────────────────
 *   Vive no host, ao lado do lançador, e por isso está exposto ao CSS do site do
 *   cliente: prefixo 'woot-' em tudo, toda propriedade declarada explicitamente
 *   (nada herdado) e 'all: revert' no contêiner — o mesmo padrão do SVG do
 *   lançador.
 *   UM componente, DUAS formas: '--discreet' apenas ESCONDE foto e chip. Não há
 *   segundo cartão, e isso não é elegância: é o teto de 15 KB gzip do arquivo que
 *   100% dos visitantes de todos os sites baixa.
 *
 * ── .woot-teaser--saindo
 *   Saída: 'scale(0.96)' em 200 ms com a curva de saída — sem bounce, sem som.
 *
 * ── .woot-teaser__fechar
 *   O alvo de dispensa é 44x44 — o aceite pede >= 32x32, e o do Olark tem
 *   9,8x9,8. O 'x' é desenhado menor que o alvo de propósito: o que precisa ser
 *   grande é a área clicável, não o glifo.
 *   O anel de foco caía em '#2dc46f' quando '--w-focus-ring-color' faltava, e esse
 *   é o MESMO literal verde que o ':hover' do lançador ressuscitaria — a armadilha
 *   que dá nome a este bloco, escondida num fallback. O bloco 1.05 troca-o por
 *   'currentColor': o anel passa a herdar '--w-text-muted' (5,0187:1 contra a
 *   superfície, acima dos 3:1 da SC 1.4.11), em vez de pintar de verde o foco de um
 *   cliente cuja marca é azul.
 *
 * ── .woot-teaser--discreet .woot-teaser__foto, .woot-teaser--discreet .woot-teaser
 *   A FORMA DISCRETA. Um seletor, duas propriedades — é literalmente isto que
 *   separa o Chamativo do Discreto.
 *
 * ── @media (prefers-reduced-motion: reduce)
 *   Movimento é preferência: com 'reduce' o cartão aparece, sem animar.
 *
 * ── @media (max-width: 767px) .woot-widget-holder — height/width duplicados
 *   Dupla declaração de propósito, e a ordem importa: quem não conhece as
 *   unidades dinâmicas ignora a segunda linha e fica com a antiga. A unidade
 *   antiga (100vh) mede em celular a viewport COM a barra do navegador
 *   recolhida — o rodapé do widget fica embaixo dela, e o botão de enviar some
 *   atrás do Chrome.
 *   O 'env(safe-area-inset-*)' logo abaixo é o recorte do aparelho (notch,
 *   barra de gestos): sem ele o composer fica debaixo da barra inferior do
 *   iPhone e o visitante não consegue tocá-lo.
 *   Estas duas explicações VIVIAM dentro do 'SDK_CSS' e custavam 599 B crus
 *   baixados por 100% dos visitantes de todos os sites — comentário dentro de
 *   template string é DADO, o minificador não o toca. É a mesma lição do bloco
 *   4.06, e ela vale toda vez que alguém for documentar uma regra ali dentro.
 *
 */
export const SDK_CSS = `
#cw-widget-holder, #cw-bubble-holder {
  --w-border: #F2F3F7;
  --w-danger: #ff4040;
  --w-surface: #ffffff;
  --w-text: #1f2d3d;
  --w-text-subtle: #37546d;
  --w-text-muted: #6e6f73;

  --w-ease-standard: cubic-bezier(0.2, 0, 0, 1);
  --w-ease-enter: cubic-bezier(0.05, 0.7, 0.1, 1);
  --w-ease-exit: cubic-bezier(0.3, 0, 0.8, 0.15);
}

.woot-widget-holder {
  box-shadow: 0 5px 40px rgba(0, 0, 0, .16);
  opacity: 1;
  will-change: transform, opacity;
  transform: translateY(0);
  overflow: hidden !important;
  position: fixed !important;

  transition: opacity 0.2s linear, transform 0.25s var(--w-ease-enter);
  z-index: 2147483000 !important;
}

.woot-widget-holder.woot-widget-holder--flat {
  box-shadow: none;
  border-radius: 0;
  border: 1px solid var(--w-border);
}

.woot-widget-holder iframe {
  border: 0;
  color-scheme: normal;
  height: 100% !important;
  width: 100% !important;
  max-height: 100vh !important;
}

.woot-widget-holder.has-unread-view {
  border-radius: 0 !important;
  min-height: 80px !important;
  height: auto;
  bottom: 94px;
  box-shadow: none !important;
  border: 0;
}

.woot-widget-bubble {
  background: var(--w-brand);

  color: var(--w-on-brand, var(--w-surface));
  border-radius: 100px;
  border-width: 0px;
  bottom: 20px;
  box-shadow: 0 8px 24px rgba(0, 0, 0, .16) !important;
  cursor: pointer;
  height: 64px;
  padding: 0px;
  position: fixed;
  user-select: none;
  width: 64px;
  z-index: 2147483000 !important;
  overflow: hidden;
}

.woot-widget-bubble.woot-widget-bubble--flat {
  border-radius: 0;
}

.woot-widget-holder.woot-widget-holder--flat {
  bottom: 90px;
}

.woot-widget-bubble.woot-widget-bubble--flat {
  height: 56px;
  width: 56px;
}

.woot-widget-bubble.woot-widget-bubble--flat svg {
  margin: 16px;
}

.woot-widget-bubble.woot-widget-bubble--flat.woot--close::before,
.woot-widget-bubble.woot-widget-bubble--flat.woot--close::after {
  left: 28px;
  top: 16px;
}

.woot-widget-bubble.unread-notification::after {
  content: '';
  position: absolute;
  width: 12px;
  height: 12px;
  background: var(--w-danger);
  border-radius: 100%;
  top: 0px;
  right: 0px;
  border: 2px solid var(--w-surface);
  transition: background 0.2s ease;
}

.woot-widget-bubble.woot-widget--expanded {
  bottom: 24px;
  display: flex;
  height: 48px !important;
  width: auto !important;
  align-items: center;
}

.woot-widget-bubble.woot-widget--expanded div {
  align-items: center;
  color: var(--w-on-brand);
  display: flex;
  font-family: system-ui, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Oxygen-Sans, Ubuntu, Cantarell, Helvetica Neue, Arial, sans-serif;
  font-size: 16px;
  font-weight: 500;
  justify-content: center;
  padding-right: 20px;
  width: auto !important;
}

.woot-widget-bubble.woot-widget--expanded svg {
  height: 20px;
  margin: 14px 8px 14px 16px;
  width: 20px;
}

.woot-widget-bubble.woot-elements--left {
  left: 20px;
}

.woot-widget-bubble.woot-elements--right {
  right: 20px;
}

.woot-widget-bubble:hover {
  background: var(--w-brand);
  box-shadow: 0 8px 32px rgba(0, 0, 0, .4) !important;
}

.woot-widget-bubble svg {
  all: revert;
  height: 24px;
  margin: 20px;
  width: 24px;
}

.woot-widget-bubble img.woot-widget-bubble__photo {
  all: revert;
  display: block;
  width: 100%;
  height: 100%;
  object-fit: cover;
  object-position: center;
  border-radius: inherit;
  margin: 0;
  pointer-events: none;
  user-select: none;
}

.woot-widget-bubble.woot-widget-bubble--has-photo {
  box-shadow:
    0 0 0 2px var(--w-brand-border, var(--w-surface)),
    0 0 0 3px rgba(0, 0, 0, 0.55),
    0 8px 24px rgba(0, 0, 0, 0.16) !important;
}

.woot-widget-bubble.woot-widget--expanded img.woot-widget-bubble__photo {
  height: 32px;
  width: 32px;
  border-radius: 100px;
  margin: 8px 8px 8px 8px;
}

@media only screen and (min-width: 768px) {
  .woot-widget-holder.woot-elements--left {
    left: 20px;
 }
  .woot-widget-holder.woot-elements--right {
    right: 20px;
 }
}

.woot--close:hover {
  opacity: 1;
}

.woot--close::before, .woot--close::after {
  background-color: var(--w-on-brand, var(--w-surface));
  content: ' ';
  display: inline;
  height: 24px;
  left: 32px;
  position: absolute;
  top: 20px;
  width: 2px;
}

.woot--close::before {
  transform: rotate(45deg);
}

.woot--close::after {
  transform: rotate(-45deg);
}

.woot-teaser {
  all: revert;
  box-sizing: border-box;
  position: fixed;
  bottom: 96px;
  width: 280px;
  max-width: calc(100vw - 32px);
  display: flex;
  align-items: flex-start;
  gap: 10px;
  padding: 12px 14px;
  border-radius: 16px;
  background: var(--w-surface);
  color: var(--w-text);
  box-shadow: 0 8px 24px rgba(0, 0, 0, .16);
  cursor: pointer;
  z-index: 2147482999;
  font-family: system-ui, -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Helvetica Neue, Arial, sans-serif;
  opacity: 0;
  transform: translateY(8px);
  transition: opacity 250ms var(--w-ease-enter), transform 250ms var(--w-ease-enter);
}

.woot-teaser.woot-elements--right { right: 20px; }
.woot-teaser.woot-elements--left { left: 20px; }

.woot-teaser--visivel { opacity: 1; transform: translateY(0); }

.woot-teaser--saindo {
  opacity: 0;
  transform: scale(.96);
  transition: opacity 200ms var(--w-ease-exit), transform 200ms var(--w-ease-exit);
}

.woot-teaser__foto {
  width: 32px; height: 32px;
  border-radius: 50%;
  object-fit: cover;
  flex: 0 0 auto;
}

.woot-teaser__corpo { flex: 1 1 auto; min-width: 0; }

.woot-teaser__texto {
  margin: 0;
  font-size: 14px;
  line-height: 1.45;
  font-weight: 500;
}

.woot-teaser__chip {
  display: inline-block;
  margin-top: 6px;
  padding: 2px 8px;
  border-radius: 100px;
  background: var(--w-border);
  font-size: 12px;
  line-height: 1.5;
  color: var(--w-text-subtle);
}

.woot-teaser__fechar {
  all: revert;
  flex: 0 0 auto;
  width: 44px; height: 44px;
  margin: -10px -10px -10px 0;
  border: 0;
  background: transparent;
  color: var(--w-text-muted);
  font-size: 20px;
  line-height: 1;
  cursor: pointer;
  border-radius: 50%;
}

.woot-teaser__fechar:focus-visible {
  outline: var(--w-focus-ring-width, 2px) solid var(--w-focus-ring-color, currentColor);
  outline-offset: -2px;
}

.woot-teaser--discreet .woot-teaser__foto,
.woot-teaser--discreet .woot-teaser__chip { display: none; }

@media (prefers-reduced-motion: reduce) {
  .woot-teaser, .woot-teaser--saindo { transition: none; transform: none; }
}

.woot--hide {
  bottom: -100vh !important;
  top: unset !important;
  opacity: 0;
  visibility: hidden !important;
  z-index: -1 !important;
}

.woot-widget--without-bubble {
  bottom: 20px !important;
}
.woot-widget-holder.woot--hide{
  transform: translateY(40px);
}
.woot-widget-bubble.woot--close {
  transform: translateX(0px) scale(1) rotate(0deg);
  transition: transform 300ms var(--w-ease-enter), opacity 100ms ease, visibility 0ms linear 0ms, bottom 0ms linear 0ms;
}
.woot-widget-bubble.woot--close.woot--hide {
  transform: translateX(8px) scale(.75) rotate(45deg);
  transition: transform 300ms var(--w-ease-exit), opacity 200ms ease, visibility 0ms linear 500ms, bottom 0ms ease 200ms;
}

.woot-widget-bubble {
  transform-origin: center;
  will-change: transform, opacity;
  transform: translateX(0) scale(1) rotate(0deg);
  transition: transform 300ms var(--w-ease-enter), opacity 100ms ease, visibility 0ms linear 0ms, bottom 0ms linear 0ms;
}
.woot-widget-bubble.woot--hide {
  transform: translateX(8px) scale(.75) rotate(-30deg);
  transition: transform 300ms var(--w-ease-exit), opacity 200ms ease, visibility 0ms linear 500ms, bottom 0ms ease 200ms;
}

.woot-widget-bubble.woot-widget--expanded {
  transform: translateX(0px);
  transition: transform 300ms var(--w-ease-enter), opacity 100ms ease, visibility 0ms linear 0ms, bottom 0ms linear 0ms;
}
.woot-widget-bubble.woot-widget--expanded.woot--hide {
  transform: translateX(8px);
  transition: transform 300ms var(--w-ease-exit), opacity 200ms ease, visibility 0ms linear 500ms, bottom 0ms ease 200ms;
}
.woot-widget-bubble.woot-widget-bubble--flat.woot--close {
  transform: translateX(0px);
  transition: transform 300ms var(--w-ease-enter), opacity 10ms ease, visibility 0ms linear 0ms, bottom 0ms linear 0ms;
}
.woot-widget-bubble.woot-widget-bubble--flat.woot--close.woot--hide {
  transform: translateX(8px);
  transition: transform 300ms var(--w-ease-exit), opacity 200ms ease, visibility 0ms linear 500ms, bottom 0ms ease 200ms;
}
.woot-widget-bubble.woot-widget--expanded.woot-widget-bubble--flat {
  transform: translateX(0px);
  transition: transform 300ms var(--w-ease-enter), opacity 200ms ease, visibility 0ms linear 0ms, bottom 0ms linear 0ms;
}
.woot-widget-bubble.woot-widget--expanded.woot-widget-bubble--flat.woot--hide {
  transform: translateX(8px);
  transition: transform 300ms var(--w-ease-exit), opacity 200ms ease, visibility 0ms linear 500ms, bottom 0ms ease 200ms;
}

@media only screen and (max-width: 767px) {
  .woot-widget-holder {
    height: 100%;
    height: 100dvh;
    right: 0;
    top: 0;
    width: 100%;
    width: 100dvw;
    padding-bottom: env(safe-area-inset-bottom, 0px);
    padding-left: env(safe-area-inset-left, 0px);
    padding-right: env(safe-area-inset-right, 0px);
 }

 .woot-widget-holder iframe {
    min-height: 100% !important;
  }

 .woot-widget-holder.has-unread-view {
    height: auto;
    right: 0;
    width: auto;
    bottom: 0;
    top: auto;
    max-height: 100vh;
    padding: 0 8px;
  }

  .woot-widget-holder.has-unread-view iframe {
    min-height: unset !important;
  }

 .woot-widget-holder.has-unread-view.woot-elements--left {
    left: 0;
  }

  .woot-widget-bubble.woot--close {
    bottom: 60px;
    opacity: 0;
    visibility: hidden !important;
    z-index: -1 !important;
  }

  .woot-teaser { width: min(320px, 100vw - 32px); bottom: 88px; }
}

@media only screen and (min-width: 768px) {
  .woot-widget-holder {
    border-radius: 16px;
    bottom: 104px;
    height: calc(90% - 64px - 20px);
    max-height: 640px !important;
    min-height: 250px !important;
    width: 400px !important;
 }
}

.woot-hidden {
  display: none !important;
}
`;
