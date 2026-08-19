import { createApp } from 'vue';

import VueDOMPurifyHTML from 'vue-dompurify-html';
import store from '../widget/store';
import App from '../widget/App.vue';
import ActionCableConnector from '../widget/helpers/actionCable';
import { carregarLocale } from '../widget/i18n';
import { i18n, registrarLocale } from '../widget/i18n/instancia';
import router from '../widget/router';
import { directive as onClickaway } from 'vue3-click-away';
import { domPurifyConfig } from '../shared/helpers/HTMLSanitizer';

const app = createApp(App);
app.use(i18n);
app.use(store);
app.use(router);
app.use(VueDOMPurifyHTML, domPurifyConfig);
app.directive('on-clickaway', onClickaway);

// O FormKit NAO entra aqui — bloco 2.18. Ele e usado so por `PreChat/Form.vue`,
// e registrado pela propria rota do pre-chat (`widget/helpers/formkitLazy.js`).
// Import estatico no entrypoint e first-paint: registrar o plugin no boot fazia
// todo visitante baixar 49.792 B gzip de uma biblioteca que a maioria das
// inboxes nem usa.

// Event Bus
// We can use the useEmitter directly
// Vue.prototype.$emitter = emitter;

// Vue.config.productionTip = false;

window.onload = async () => {
  // O idioma da inbox chega no HTML do widget, antes de qualquer render — e por
  // isso da para busca-lo ANTES do mount (bloco 2.18). Montar primeiro e
  // traduzir depois faria a tela piscar em ingles.
  const idioma = window.chatwootWebChannel?.locale;
  registrarLocale(idioma, await carregarLocale(idioma));
  window.WOOT_WIDGET = app.mount('#app');
  window.actionCable = new ActionCableConnector(
    window.WOOT_WIDGET,
    window.chatwootPubsubToken
  );
};
