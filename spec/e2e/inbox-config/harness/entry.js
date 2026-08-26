/**
 * Entrypoint do harness da tela de configuracao da caixa de entrada.
 *
 * Monta a `Settings.vue` DE VERDADE (nao uma maquete) num Vue real, com store
 * falso e o i18n de verdade. Serve para o que jsdom nao responde: **geometria
 * e cor no navegador** — quantos pixels a barra de abas transborda, quantas
 * linhas o rotulo do preview ocupa, e qual a razao de contraste real.
 *
 * A LARGURA E FIEL, e isso e o ponto do harness. Na instalacao a tela nao
 * recebe o viewport inteiro: `Wrapper.vue:33` monta o `<router-view>` com
 * `flex-1 max-w-[960px] mx-auto px-8 py-6 overflow-auto w-full`, e essa classe
 * cai na raiz da `Settings.vue` por fallthrough de atributo. E POR ISSO que a
 * barra de abas mede 912 px em 1280 e tambem em 1440. O harness repete essa
 * classe, verbatim, para medir a mesma coisa que o navegador do cliente mede.
 */
import { createApp, h } from 'vue';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import { createRouter, createWebHistory } from 'vue-router';
import messages from 'dashboard/i18n';
import Settings from 'dashboard/routes/dashboard/settings/inbox/Settings.vue';
// `woot-tabs`/`woot-input` sao globais no app real; sem o kit a barra de abas
// nem chega a renderizar e a medicao seria de um DOM que nao existe.
import WootUIKit from 'dashboard/components';
import 'dashboard/assets/scss/app.scss';

const params = new URLSearchParams(window.location.search);

const inbox = {
  id: 6,
  name: 'Suporte CHAT - SPX',
  channel_type: 'Channel::WebWidget',
  widget_color: '#2dc46f',
  website_url: 'https://simplexsolucoes.com.br',
  website_token: 'tok_fake',
  welcome_title: 'Como podemos ajudar?',
  welcome_tagline: 'Atendimento humano, simples e direto.',
  reply_time: 'in_a_few_minutes',
  selected_feature_flags: ['attachments', 'emoji_picker'],
  // A tela abre SEM foto, que e o estado do defeito: o preview mostra a
  // inicial do nome no lugar do rosto.
  avatar_url: params.get('avatar') || '',
  greeting_enabled: false,
  greeting_message: '',
  enable_email_collect: false,
  sender_name_type: 'friendly',
  business_name: '',
  lock_to_single_conversation: false,
  allow_messages_after_resolved: true,
  web_widget_script: '<script>/* snippet do servidor */</script>',
  pre_chat_form_enabled: false,
  pre_chat_form_options: {},
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
    getCurrentAccountId: () => 3,
    // Ligado: e o que faz a aba de bot existir, e a barra so transborda com
    // as 11 abas que a conta 3 tem de verdade.
    'accounts/isFeatureEnabledonAccount': () => () => true,
    'accounts/getAccount': () => () => ({
      id: 3,
      name: 'Simplex',
      locale: 'pt_BR',
    }),
    'globalConfig/isOnChatwootCloud': () => false,
    'globalConfig/get': () => ({ logoThumbnail: '', BRAND_NAME: 'ChatSPX' }),
    'inboxes/getUIFlags': () => ({ isFetching: false, isUpdating: false }),
    'inboxes/getInbox': () => () => inbox,
    'inboxes/getInstagramInboxByInstagramId': () => () => null,
    'portals/allPortals': () => [],
    'agents/getAgents': () => [],
    'teams/getTeams': () => [],
    'labels/getLabels': () => [],
  },
});
store.dispatch = () => Promise.resolve({});

const i18n = createI18n({
  legacy: true,
  allowComposition: true,
  locale: params.get('locale') || 'pt_BR',
  fallbackLocale: 'en',
  messages,
});

const tab = params.get('tab');
const path = tab
  ? `/app/accounts/3/settings/inboxes/6/${tab}`
  : '/app/accounts/3/settings/inboxes/6';

const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: '/app/accounts/:accountId/settings/inboxes/:inboxId/:tab?',
      name: 'settings_inbox_show',
      // A classe vem de `Wrapper.vue:33`. Sem ela a medicao seria de outra tela.
      component: {
        render: () => null,
      },
    },
    { path: '/:pathMatch(.*)*', component: { render: () => null } },
  ],
});

const app = createApp({
  render() {
    return h(Settings, {
      class: 'flex-1 max-w-[960px] mx-auto px-8 py-6 overflow-auto w-full',
    });
  },
});

app.use(WootUIKit);
app.use(store);
app.use(i18n);
app.use(router);
app.directive('dompurify-html', {
  mounted: (el, binding) => {
    el.innerHTML = binding.value ?? '';
  },
});
app.directive('tooltip', { mounted: () => {} });

router.push(path).then(() => {
  router.isReady().then(() => app.mount('#app'));
});
