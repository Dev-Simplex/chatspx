/**
 * Harness da tela de rastreio (bloco 5.06).
 *
 * `?stored=1` monta uma inbox que ja tem pixel, mapa e modo teste gravados —
 * inclusive um modo teste VELHO, para o desligamento automatico aparecer.
 */
import { createApp } from 'vue';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n';
import TrackingPage from 'dashboard/routes/dashboard/settings/inbox/widget/tracking/TrackingPage.vue';
import 'dashboard/assets/scss/app.scss';

const parametros = new URLSearchParams(window.location.search);

const gravado = parametros.get('stored')
  ? {
      meta_pixel_id: '123456789012345',
      ga4_measurement_id: 'G-ABC123XY',
      consent_mode: 'advanced',
      test_mode: {
        enabled: true,
        code: 'TEST12345',
        started_at: new Date(Date.now() - 8 * 864e5).toISOString(),
      },
      event_map: {
        chatspx_lead: { enabled: true, meta: 'Lead', ga4: 'generate_lead' },
      },
    }
  : undefined;

const inbox = {
  id: 7,
  name: 'Site da Simplex',
  additional_attributes: gravado
    ? {
        widget_tracking: gravado,
        tracking_kill_switch: true,
        tracking_retention_days: 90,
        tracking_dpa_accepted: true,
      }
    : {},
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

const app = createApp(TrackingPage, { inboxId: 7 });
app.use(store);
app.use(i18n);
app.mount('#app');
