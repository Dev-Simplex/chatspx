/**
 * Entrypoint do harness da tela de aparência.
 *
 * Monta APENAS a `AppearancePage` num Vue real, com um store falso e o i18n de
 * verdade. Serve para o que o jsdom não consegue responder: **como o CSS se
 * comporta no navegador** — se o tema do preview funciona sem o tema do
 * dashboard, se algum texto ficou ilegível, se sobrou chave de i18n crua.
 */
import { createApp } from 'vue';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n';
import AppearancePage from 'dashboard/routes/dashboard/settings/inbox/widget/appearance/AppearancePage.vue';
import 'dashboard/assets/scss/app.scss';

const inbox = {
  id: 7,
  name: 'Site da Simplex',
  widget_color: '#2dc46f',
  welcome_title: 'Como podemos ajudar?',
  welcome_tagline: 'Atendimento humano, simples e direto.',
  reply_time: 'in_a_few_minutes',
  selected_feature_flags: ['attachments', 'emoji_picker'],
  avatar_url: '',
  web_widget_script: '<script>/* snippet do servidor */</script>',
  additional_attributes: {
    widget_profile: 'support',
    widget_appearance: {
      theme: 'auto',
      position: 'right',
      offset_x: 20,
      offset_y: 20,
      launcher_type: 'standard',
      launcher_text: '',
      hide_bubble: false,
      panel_style: 'standard',
      launcher_icon: 'default',
    },
  },
};

const store = createStore({
  getters: {
    'inboxes/getInbox': () => () => inbox,
    'inboxes/getUIFlags': () => ({}),
    'globalConfig/get': () => ({ logoThumbnail: '', BRAND_NAME: 'ChatSPX' }),
    getCurrentAccountId: () => 1,
  },
  actions: {
    'inboxes/updateInbox': () => Promise.resolve(),
  },
});

const i18n = createI18n({
  legacy: false,
  locale: new URLSearchParams(window.location.search).get('locale') || 'pt_BR',
  fallbackLocale: 'en',
  messages,
});

const app = createApp(AppearancePage, { inboxId: 7 });
app.use(store);
app.use(i18n);
app.directive('dompurify-html', {
  mounted: (el, binding) => {
    el.innerHTML = binding.value ?? '';
  },
});
app.mount('#app');
