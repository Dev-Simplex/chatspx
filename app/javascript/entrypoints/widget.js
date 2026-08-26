import { createApp, watch } from 'vue';
import { createI18n } from 'vue-i18n';

import VueDOMPurifyHTML from 'vue-dompurify-html';
import store from '../widget/store';
import App from '../widget/App.vue';
import ActionCableConnector from '../widget/helpers/actionCable';
import i18nMessages, {
  FALLBACK_LOCALE,
  hasLocale,
  loadLocaleMessages,
} from '../widget/i18n';
import router from '../widget/router';
import { directive as onClickaway } from 'vue3-click-away';
import { domPurifyConfig } from '../shared/helpers/HTMLSanitizer';
import { getLocale } from '../widget/helpers/urlParamsHelper';
import { ROTAS_COM_FORMKIT, criarInstaladorDeFormKit } from '../widget/formkit';

const i18n = createI18n({
  legacy: false, // https://github.com/intlify/vue-i18n/issues/1902
  locale: FALLBACK_LOCALE,
  // Explícito porque agora ele é carregador, não enfeite: enquanto o chunk do
  // idioma do visitante não chega — e se nunca chegar —, é `en` que renderiza.
  fallbackLocale: FALLBACK_LOCALE,
  messages: i18nMessages,
});

const app = createApp(App);
app.use(i18n);
app.use(store);
app.use(router);
app.use(VueDOMPurifyHTML, domPurifyConfig);
app.directive('on-clickaway', onClickaway);

/* ────────────────────────────────────────────────────────────────────────────
 * i18n SOB DEMANDA — bloco 2.18
 *
 * `widget/i18n/index.js` só traz `en` no bundle de first-paint. O idioma do
 * painel entra por `setLocaleMessage()`, e há dois caminhos que o mudam:
 *
 *   BOOT   — `chatwootWebChannel.locale` (o locale da conta) e, no popout,
 *            `?locale=` da URL. Os dois são conhecidos ANTES do mount, então
 *            o carregamento é esperado antes de montar: sem isso o visitante
 *            veria o painel em inglês por um quadro e ele trocaria embaixo
 *            dos olhos dele.
 *   DEPOIS — `set-locale` pela ponte (`$chatwoot.setLocale()`) e a troca de
 *            idioma quando a inbox tem mais de um habilitado. Aí o `watch`
 *            abaixo busca o chunk e o `fallbackLocale` segura o intervalo.
 * ──────────────────────────────────────────────────────────────────────────── */

const ensureLocale = async locale => {
  if (!locale || !hasLocale(locale)) return;
  if (i18n.global.availableLocales.includes(locale)) return;
  const messages = await loadLocaleMessages(locale);
  if (messages) i18n.global.setLocaleMessage(locale, messages);
};

watch(
  () => i18n.global.locale.value,
  locale => {
    ensureLocale(locale);
  }
);

/**
 * Os candidatos de BOOT, na mesma regra que `App.vue#setLocale` aplica: o
 * locale da conta pode vir com variação (`pt_BR`) e cair para a base (`pt`)
 * quando a variação não está habilitada — os dois são pré-carregados porque
 * quem decide entre eles é o `App.vue`, no `mounted`, depois deste ponto.
 */
const localesDoBoot = () => {
  const { locale } = window.chatwootWebChannel || {};
  const daUrl = getLocale(window.location.search);
  return [...new Set([locale, locale?.split('_')[0], daUrl].filter(Boolean))];
};

/* ────────────────────────────────────────────────────────────────────────────
 * FormKit SÓ NA ROTA DO PRÉ-CHAT — bloco 2.18
 *
 * A instalação e a lista de rotas moram em `widget/formkit.js`, com o porquê
 * inteiro. Aqui fica só o gancho: `beforeResolve` roda ANTES de a navegação
 * ser confirmada, então o plugin está no app quando o componente da rota
 * renderiza.
 * ──────────────────────────────────────────────────────────────────────────── */

const ensureFormKit = criarInstaladorDeFormKit(app);

router.beforeResolve(async to => {
  if (ROTAS_COM_FORMKIT.includes(to.name)) await ensureFormKit();
});

// Event Bus
// We can use the useEmitter directly
// Vue.prototype.$emitter = emitter;

// Vue.config.productionTip = false;

window.onload = async () => {
  // O `await` é o que impede o flash de inglês: `App.vue#mounted` chama
  // `setLocale` no primeiro tique depois do mount, e as mensagens têm de
  // estar em memória antes disso.
  await Promise.all(localesDoBoot().map(ensureLocale));
  window.WOOT_WIDGET = app.mount('#app');
  window.actionCable = new ActionCableConnector(
    window.WOOT_WIDGET,
    window.chatwootPubsubToken
  );
};
