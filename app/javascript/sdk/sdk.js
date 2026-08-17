export const SDK_CSS = `
/* Tokens que NÃO dependem da inbox (borda, alerta, superfície do badge).
   Declarados nos NOSSOS dois containers, nunca no ':root' do host: o documento
   é do cliente, e um site com '--w-*' próprio nos sobrescreveria — é a mesma
   decisão que o bloco 1.03 tomou para os tokens que vêm do servidor.
   Os tokens de MARCA ('--w-brand', '--w-on-brand', …) não aparecem aqui de
   propósito: quem os escreve é 'applyWidgetTokens', com o valor que o servidor
   calculou para a inbox. */
#cw-widget-holder, #cw-bubble-holder {
  --w-border: #F2F3F7;
  --w-danger: #ff4040;
  --w-surface: #ffffff;

  /* As três curvas da casa (22 §D.2), repetidas aqui porque '_tokens.scss' só é
     carregado DENTRO do iframe e o lançador/holder vivem no documento do host.
     São os mesmos valores, e o spec de tokens compara os dois lados.
     'linear' fica permitido só para opacidade pura, rotação contínua e para os
     truques de 'visibility'/'bottom' com duração 0ms — nunca para 'transform'
     de uma superfície que entra ou sai, que é o que este bloco corrige. */
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
  /* Era 'transform 0.25s linear' — o painel subia a velocidade constante, que é
     o que faz uma superfície parecer empurrada em vez de aberta. A abertura usa
     a curva de entrada; a opacidade pode seguir linear, porque em opacidade pura
     'linear' é justamente o correto. */
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
  /* 'color' existe para o ícone herdar: o SVG do lançador usa
     fill="currentColor", então a cor do traço passa a vir de '--w-on-brand' —
     a mesma decisão WCAG que pinta o texto do painel.
     O fallback é '--w-surface' (branco) e vale só para a aba aberta antes do
     deploy do 1.02, que chega sem tokens: ali o ícone segue branco, que era
     exatamente o 'fill="#FFFFFF"' de antes. */
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

/* As três regras '.woot-widget-bubble-color--lighter' que viviam aqui, no 'path'
   e no 'woot--close' foram REMOVIDAS. Elas existiam para pintar de escuro
   ('--s-700: #37546D') quando a marca era clara, decisão tomada por
   'isWidgetColorLighter' — brilho 299/587/114, limiar 225, não-WCAG. Agora
   '--w-on-brand' já É essa decisão, calculada por luminância no servidor: as
   regras viraram duplicatas exatas da regra base e duplicata exata é ruído.
   A classe continua sendo aplicada pelo 1.03 (tem spec) como sinal semântico de
   "o servidor decidiu que esta marca é clara", mas não pinta mais nada. */
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

/* O ':hover' repete '--w-brand' de propósito, e é o ponto mais perigoso da onda.
   Este seletor reaplicava '#2dc46f' cravado. O literal estava MORTO porque
   'IFrameHelper' escrevia 'chatIcon.style.background' inline, e inline vence
   folha sem '!important'; ao remover o inline (é o que este bloco faz), o
   literal RESSUSCITARIA e o lançador de qualquer cliente ficaria verde ao
   passar o mouse. O feedback de hover continua vindo do box-shadow, como hoje —
   por isso a cor é a mesma de repouso, e não '--w-brand-hover': o aceite do
   bloco exige que o lançador em '#009CE0' siga 'rgb(0,156,224)' EM hover, ou
   seja, sem mudança de matiz. */
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

@media only screen and (min-width: 667px) {
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
  background-color: var(--w-on-brand);
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

@media only screen and (max-width: 667px) {
  .woot-widget-holder {
    height: 100%;
    right: 0;
    top: 0;
    width: 100%;
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
}

@media only screen and (min-width: 667px) {
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
