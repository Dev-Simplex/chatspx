/**
 * Entrypoint do harness da tela de gatilhos (bloco 4.04).
 *
 * Monta a `TriggersPage` num Vue real, com store falso e o i18n de verdade.
 * Serve para o que o jsdom nao responde: **o que o navegador computa** — se o
 * cartao pre-selecionado esta mesmo destacado, se o dialogo abre de verdade, se
 * o aviso aparece com contraste legivel nos dois temas do painel.
 */
import { createApp } from 'vue';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n';
import TriggersPage from 'dashboard/routes/dashboard/settings/inbox/widget/triggers/TriggersPage.vue';
import 'dashboard/assets/scss/app.scss';

const parametros = new URLSearchParams(window.location.search);

/** `?stored=1` monta uma inbox que JA tem gatilhos configurados. */
const gravado = parametros.get('stored')
  ? {
      enabled: true,
      approach: 'discreet',
      degrade_on_return: false,
      triggers: [
        {
          id: 'time_on_page',
          desktop: { enabled: true, value: 12 },
          mobile: { enabled: true, value: 12 },
        },
      ],
      audience: {
        url: { operator: 'contains', values: ['/planos'] },
        device: ['desktop'],
      },
    }
  : undefined;

const inbox = {
  id: 7,
  name: 'Site da Simplex',
  widget_color: '#2dc46f',
  additional_attributes: gravado ? { widget_triggers: gravado } : {},
};

const store = createStore({
  getters: {
    'inboxes/getInbox': () => () => inbox,
    'inboxes/getUIFlags': () => ({}),
    'globalConfig/get': () => ({ logoThumbnail: '', BRAND_NAME: 'ChatSPX' }),
  },
  actions: { 'inboxes/updateInbox': () => Promise.resolve() },
});

const i18n = createI18n({
  legacy: false,
  locale: parametros.get('locale') || 'pt_BR',
  fallbackLocale: 'en',
  messages,
});

const app = createApp(TriggersPage, { inboxId: 7 });
app.use(store);
app.use(i18n);
app.mount('#app');
