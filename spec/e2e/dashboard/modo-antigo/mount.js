/**
 * Página mínima do aceite de APARÊNCIA do bloco 4.22 — a seção "modo antigo".
 *
 * POR QUE ELA EXISTE ALÉM DOS 10 TESTES DE UNIDADE
 *
 * Os specs de `LegacyCampaigns.spec.js` rodam em jsdom e provam a LÓGICA: quem entra
 * na lista, qual aviso aparece, o que o botão chama. O que eles não podem provar é
 * que o aviso é LEGÍVEL — jsdom não resolve cascata nem custom property, então ele
 * dá verde para qualquer cor.
 *
 * A seção usa `Banner` e `Button` do design system, cujas cores vêm de tokens
 * (`--n-*`). Um token que não resolvesse deixaria o texto na cor herdada, com o
 * teste de unidade verde do mesmo jeito.
 */
import { createApp, h, ref } from 'vue';
import { createI18n } from 'vue-i18n';
import LegacyCampaigns from 'dashboard/routes/dashboard/settings/inbox/widget/triggers/LegacyCampaigns.vue';
import ptBR from 'dashboard/i18n/locale/pt_BR/inboxWidget.json';
import 'dashboard/assets/scss/app.scss';

// A seção lê o store, despacha `campaigns/get` ao montar e chama a API ao importar.
// Nada disso é assunto desta página: aqui se mede COR e NOME ACESSÍVEL, então o store
// é preso num objeto falso pelo próprio mount, já com a lista dentro.
// `id` É o `display_id` — o serializador do índice não expõe o id do banco
// (`api/v1/models/_campaign.json.jbuilder:1`).
const CAMPANHAS = [
  {
    id: 3,
    title: '🔥 Convite dos planos',
    message: 'Posso ajudar a escolher o plano ideal para o seu time?',
    enabled: true,
    campaign_type: 'ongoing',
    inbox: { id: 7, channel_type: 'Channel::WebWidget' },
  },
];

const i18n = createI18n({
  legacy: false,
  locale: 'pt_BR',
  messages: { pt_BR: ptBR },
  fallbackWarn: false,
  missingWarn: false,
});

const app = createApp({
  setup() {
    const escuro = ref(false);
    // O tema do painel é classe no `<html>`, como no widget. O teste alterna por aqui.
    window.alternarTema = valor => {
      escuro.value = valor;
      document.documentElement.classList.toggle('dark', valor);
    };
    return () =>
      h(
        'div',
        { class: 'p-6 bg-n-background min-h-screen' },
        h(LegacyCampaigns, { inboxId: 7, gatilhoAtivo: true })
      );
  },
});

// `useStore` do painel le `vm.proxy.$store` (composables/store.js:7), entao um objeto
// em `globalProperties` basta e evita arrastar o Vuex inteiro para uma pagina que so
// mede cor. Nao e dublê de conveniencia: o componente le exatamente o getter que le em
// producao, com o formato que ele recebe em producao.
app.config.globalProperties.$store = {
  dispatch: () => Promise.resolve(),
  getters: {
    'campaigns/getLiveChatCampaigns': CAMPANHAS,
    // A seção carrega a própria lista ao montar e consulta esta flag antes de
    // despachar. O objeto de flags é o que o getter devolve em produção.
    'campaigns/getUIFlags': { isFetching: false, isCreating: false },
  },
};

app.use(i18n);
app.mount('#app');
