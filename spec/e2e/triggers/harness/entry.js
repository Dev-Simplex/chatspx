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

/**
 * O módulo `campaigns` do painel real está SEMPRE registrado
 * (`dashboard/store/index.js:17,89`), e dois filhos desta tela leem dele:
 * `TeaserComposer` (4.05) e `LegacyCampaigns` (4.22). Sem esses getters aqui,
 * `useMapGetter` devolve `undefined`, o computed `vinculada` estoura em
 * `campanhas.value.find` e a TELA INTEIRA morre no mount — nenhum
 * `data-testid` chega ao DOM e todos os testes deste arquivo reprovam por
 * timeout, sem que nada esteja errado no produto.
 *
 * A lista nasce VAZIA porque é o estado de uma inbox que ainda não tem
 * campanha de chat ao vivo — o mesmo estado que o painel real mostra. O que
 * depende de uma campanha vinculada (o texto do teaser, a seção "modo antigo")
 * é coberto em jsdom por `triggers/specs/TeaserComposer.spec.js` e
 * `triggers/specs/LegacyCampaigns.spec.js`; aqui o que se mede é o que só o
 * navegador computa.
 */
const campanhas = [];

const store = createStore({
  getters: {
    'inboxes/getInbox': () => () => inbox,
    'inboxes/getUIFlags': () => ({}),
    'globalConfig/get': () => ({ logoThumbnail: '', BRAND_NAME: 'ChatSPX' }),
    'campaigns/getLiveChatCampaigns': () => campanhas,
    'campaigns/getUIFlags': () => ({ isUpdating: false }),
  },
  actions: {
    'inboxes/updateInbox': () => Promise.resolve(),
    'campaigns/update': () => Promise.resolve(),
    'campaigns/get': () => Promise.resolve(),
  },
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
