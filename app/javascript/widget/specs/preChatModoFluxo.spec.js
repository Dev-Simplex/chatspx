/**
 * BLOCO 4.02 — O WIDGET LÊ `mode`.
 *
 * `pre_chat_form_options.mode` (vocabulário de `Channel::WebWidget::PreChatFormSchema::MODES`)
 * diz QUEM conduz o pré-chat: `simple`/`builder` são o formulário clássico e `flow` delega ao
 * motor de Automações, que entrega o fluxo de captura como MENSAGENS
 * (`Flows::WidgetPrechatResolver`).
 *
 * O servidor já respeitava o modo — o resolver só entrega fluxo quando a inbox declara
 * `mode: 'flow'` (`widget_prechat_resolver.rb#prechat_delegated_to_flow?`). O widget não lia a
 * chave: no modo `flow` ele montava o formulário clássico E recebia o fluxo, que é CAPTURA EM
 * DUPLICIDADE — dois pré-chats para o mesmo visitante.
 *
 * As três portas para o formulário clássico estão cobertas aqui, porque fechar uma só deixa o
 * defeito vivo pelas outras:
 *   1. `Home.vue#startConversation`      — o botão "iniciar conversa";
 *   2. `configMixin.shouldShowPreChatForm` — o clique na campanha (`App.vue:196`);
 *   3. `useConversationFooter#startNewConversation` — "nova conversa" no rodapé.
 *
 * A FORMA DO DUBLÊ É A REAL: `window.chatwootWebChannel.preChatFormOptions` é o
 * `pre_chat_form_options` CRU do banco — `show.html.erb:56` faz `.to_json` sem camelizar — então
 * as chaves internas são snake_case (`pre_chat_fields`, `mode`) dentro de um contêiner camelCase.
 * Que `mode` de fato chega ali é medido no servidor, contra o ERB de verdade, em
 * `spec/requests/widgets/prechat_mode_payload_spec.rb`.
 */
import { shallowMount } from '@vue/test-utils';
import { defineComponent } from 'vue';
import configMixin from 'widget/mixins/configMixin';
import HomeView from 'widget/views/Home.vue';
import { useConversationFooter } from 'widget/composables/useConversationFooter';

const replace = vi.fn();

vi.mock('vue-router', () => ({
  useRouter: () => ({ replace, push: vi.fn() }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, locale: { value: 'pt_BR' } }),
}));

vi.mock('widget/api/conversation', () => ({
  sendEmailTranscript: vi.fn(() => Promise.resolve()),
}));

const storeMock = {
  getters: {
    'agent/availableAgents': [],
    'conversation/getConversationSize': 0,
    'conversation/getUnreadMessageCount': 0,
    'conversationAttributes/getConversationParams': { status: 'open' },
    'contacts/getCurrentUser': {},
  },
  dispatch: vi.fn(),
};

vi.mock('vuex', () => ({
  useStore: () => storeMock,
  mapGetters: map =>
    Object.fromEntries(
      Object.entries(map).map(([local, path]) => [
        local,
        () => storeMock.getters[path],
      ])
    ),
}));

// Um campo HABILITADO: sem ele `shouldShowPreChatForm` já seria falso por outro motivo, e o
// exemplo do modo `flow` passaria no vácuo.
const CAMPO_HABILITADO = {
  label: 'Nome',
  name: 'fullName',
  type: 'text',
  field_type: 'standard',
  required: true,
  enabled: true,
};

const configurarCanal = mode => {
  window.chatwootWebChannel = {
    enabledFeatures: [],
    preChatFormEnabled: true,
    preChatFormOptions: {
      pre_chat_message: 'Fale com a gente',
      pre_chat_fields: [CAMPO_HABILITADO],
      ...(mode === undefined ? {} : { mode }),
    },
    allowMessagesAfterResolved: true,
  };
};

const montarComMixin = () =>
  shallowMount({
    mixins: [configMixin],
    template: '<div />',
  });

const montarRodape = () => {
  let footer;
  shallowMount(
    defineComponent({
      setup() {
        footer = useConversationFooter();
        return () => null;
      },
    })
  );
  return footer;
};

beforeEach(() => {
  replace.mockClear();
  storeMock.getters['conversation/getConversationSize'] = 0;
});

describe('4.02 — pré-chat delegado ao motor de fluxos (mode: "flow")', () => {
  describe('configMixin', () => {
    it('expõe o modo lido do canal', () => {
      configurarCanal('flow');
      expect(montarComMixin().vm.preChatFormOptions.mode).toBe('flow');
    });

    it('não monta o formulário clássico quando o modo é flow', () => {
      configurarCanal('flow');
      const vm = montarComMixin().vm;

      expect(vm.isPreChatDelegatedToFlow).toBe(true);
      expect(vm.shouldShowPreChatForm).toBe(false);
    });

    // CONTROLE — sem estes o exemplo acima passaria mesmo se a regra tivesse desligado o
    // pré-chat de TODA a frota, que seria um defeito muito maior do que o que ela conserta.
    it.each(['simple', 'builder'])(
      'continua montando o formulário clássico no modo %s',
      mode => {
        configurarCanal(mode);
        const vm = montarComMixin().vm;

        expect(vm.isPreChatDelegatedToFlow).toBe(false);
        expect(vm.shouldShowPreChatForm).toBe(true);
      }
    );

    it('trata a AUSÊNCIA de mode como o formulário clássico — é o estado de toda a frota hoje', () => {
      configurarCanal(undefined);
      const vm = montarComMixin().vm;

      expect(vm.isPreChatDelegatedToFlow).toBe(false);
      expect(vm.shouldShowPreChatForm).toBe(true);
    });

    it('trata um modo fora do enum como o formulário clássico', () => {
      configurarCanal('banana');
      expect(montarComMixin().vm.isPreChatDelegatedToFlow).toBe(false);
    });
  });

  describe('Home.vue — o botão "iniciar conversa"', () => {
    it('vai direto para as mensagens quando o pré-chat é um fluxo', () => {
      configurarCanal('flow');
      shallowMount(HomeView).vm.startConversation();

      expect(replace).toHaveBeenCalledWith({ name: 'messages' });
      expect(replace).not.toHaveBeenCalledWith({ name: 'prechat-form' });
    });

    it('continua indo para o formulário quando o modo é o clássico', () => {
      configurarCanal('simple');
      shallowMount(HomeView).vm.startConversation();

      expect(replace).toHaveBeenCalledWith({ name: 'prechat-form' });
    });
  });

  describe('useConversationFooter — "nova conversa" no rodapé', () => {
    it('vai direto para as mensagens quando o pré-chat é um fluxo', () => {
      configurarCanal('flow');
      montarRodape().startNewConversation();

      expect(replace).toHaveBeenCalledWith({ name: 'messages' });
      expect(replace).not.toHaveBeenCalledWith({ name: 'prechat-form' });
    });

    it('continua indo para o formulário quando o modo é o clássico', () => {
      configurarCanal('simple');
      montarRodape().startNewConversation();

      expect(replace).toHaveBeenCalledWith({ name: 'prechat-form' });
    });
  });
});
