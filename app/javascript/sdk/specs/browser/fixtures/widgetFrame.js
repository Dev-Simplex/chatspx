/**
 * O LADO DE DENTRO DO IFRAME, para o verificador do bloco 4.20.
 *
 * O aceite do 4.20 termina em "`Esc` fecha o painel aberto por auto-open e
 * devolve o foco ao lancador (2.11)". Essa frase atravessa uma fronteira de
 * documento E de origem: o `Esc` chega ao documento do PAINEL, que roda noutra
 * origem, e quem fecha o painel e devolve o foco e o HOST. jsdom tem um
 * `document` so e nenhuma origem — nele a frase e indemonstravel, e a prova que
 * existia antes deste bloco entregava a mensagem de um lado ao outro na mao.
 *
 * Este arquivo e o painel do outro lado. Ele NAO e uma imitacao do widget: e o
 * widget de verdade menos os componentes Vue. Sao reais, importados do codigo de
 * producao:
 *
 *   · `registerWidgetListeners` — a fiacao do bridge, que registra o ouvinte de
 *     `message` E o `Esc` do 2.11 (`widget/bridge/index.js`);
 *   · `registerBridgeListeners` — a MESMA fiacao SEM o `Esc`. Nao e um dublê: e
 *     o outro export do mesmo modulo, o mundo anterior ao 2.11. E o que permite
 *     ao verificador reduzir a guarda a uma ponta e ver o vermelho;
 *   · `handlers` — os handlers reais, inclusive o `toggle-open` que liga o
 *     `isWidgetOpen` da store;
 *   · o modulo `appConfig` da store real, com a mutation real;
 *   · `loadedEventConfig` — o payload real do `loaded`, montado pela funcao de
 *     producao a partir do `window.chatwootWebChannel`. Nenhum objeto escrito a
 *     mao: a forma e a mesma que o host recebe no site do cliente.
 *
 * O QUE E REDUCAO, DECLARADO: `ViewWithHeader.vue` e `useComposer.js` levam o
 * foco para dentro do painel quando `isWidgetOpen` vira verdadeiro — um `watch`
 * sobre o getter `appConfig/getIsWidgetOpen`. Montar os dois exigiria o router,
 * o i18n e meia duzia de componentes. Aqui fica o MESMO `watch` sobre o MESMO
 * getter real, focando um `h1[tabindex="-1"]` — que e o elemento que o
 * `ViewWithHeader` foca (`this.$el?.querySelector('h1')?.focus()`), com o
 * `tabindex` que o bloco 2.06 deu a ele. A pergunta que o verificador faz nao e
 * "o Vue focou?": e "o navegador deixa um iframe de OUTRA ORIGEM puxar o foco
 * sem nenhum gesto do visitante, e o `Esc` vai parar la dentro?".
 *
 * `ctx` e o contrato que o proprio `handlers.js` documenta ("qualquer objeto com
 * os metodos usados; na producao, a instancia de `App.vue`"). Os despachos para
 * modulos nao registrados (`contacts/get`, `campaign/resetCampaign`) caem no
 * aviso do vuex e nao afetam nada do que se mede aqui.
 */
import { watch } from 'vue';
import { createStore } from 'vuex';
import appConfig from 'widget/store/modules/appConfig';
import {
  registerWidgetListeners,
  registerBridgeListeners,
} from 'widget/bridge';
import { loadedEventConfig } from 'widget/helpers/IframeEventHelper';
import { sendMessage } from 'widget/helpers/utils';

const store = createStore({ modules: { appConfig } });

const ctx = {
  $store: store,
  $route: { name: 'home' },
  router: { replace: () => {} },
  messageCount: 0,
  isMobile: false,
  isInWorkingHours: true,
  setLocale: () => {},
  setBubbleLabel: () => {},
  setUnreadView: () => {},
  unsetUnreadView: () => {},
  setCampaignReadData: () => {},
  fetchAvailableAgents: () => {},
  fetchOldConversations: () => Promise.resolve(),
  scrollConversationToBottom: () => {},
};

// A UNICA chave do verificador: com `false`, instala-se a fiacao SEM o `Esc`.
// As duas funcoes sao de producao; o que muda e qual delas roda.
const comEsc = window.wootEscLigado !== false;
(comEsc ? registerWidgetListeners : registerBridgeListeners)(ctx);

watch(
  () => store.getters['appConfig/getIsWidgetOpen'],
  aberto => {
    if (aberto) document.querySelector('h1')?.focus();
  }
);

sendMessage(loadedEventConfig());
