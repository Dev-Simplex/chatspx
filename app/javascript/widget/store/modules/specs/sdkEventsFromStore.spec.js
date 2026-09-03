/**
 * Bloco 5.04 — a prova de que os eventos saem DO STORE, uma vez, e na ordem.
 *
 * ── POR QUE ESTE ARQUIVO EXISTE SEPARADO ─────────────────────────────────────
 *
 * Porque o fato que ele verifica ATRAVESSA quatro módulos do store
 * (`conversation`, `contacts`, `campaign`, `message`) e um só deles não conta a
 * história. A ordem do aceite — `widget_opened → conversation_created →
 * prechat_submitted → lead_identified` — não é propriedade de nenhum módulo
 * isolado; é propriedade da sequência.
 *
 * ── E POR QUE DO STORE, E NÃO DO COMPONENTE ──────────────────────────────────
 *
 * `PreChat/Form.vue`, `ChatFooter.vue` e `ChatInputWrap.vue` são campo minado
 * (R15 §B12.3: 16 commits do upstream desde a base) e, pior que isso, são
 * componentes: montam e desmontam a cada troca de rota. Evento emitido de
 * `mounted` dispara duas vezes num re-render e zero numa navegação que reusa a
 * instância. O store não monta nem desmonta.
 */
import { actions as conversationActions } from '../conversation/actions';
import { actions as contactActions } from '../contacts';
import { actions as campaignActions } from '../campaign';
import { actions as messageActions } from '../message';
import { __resetSdkEventsForTests } from 'widget/helpers/sdkEventEmitter';
import { IFrameHelper } from 'widget/helpers/utils';
import { API } from 'widget/helpers/axios';

vi.mock('widget/helpers/axios');
vi.mock('widget/helpers/utils', () => ({
  IFrameHelper: { sendMessage: vi.fn() },
  sendMessage: vi.fn(),
}));
vi.mock('widget/helpers/telemetry', () => ({
  reportWidgetError: vi.fn(),
}));
vi.mock('shared/helpers/cache', () => ({
  getFromCache: vi.fn(() => null),
  setCache: vi.fn(),
}));
// `campaignTimer` importa `widget/store`, que importa `campaign` de volta. Sem
// este duble o ciclo faz o Vuex montar um módulo ainda não avaliado e a suíte
// morre em `assertRawModule` — antes de rodar exemplo nenhum.
vi.mock('widget/helpers/campaignTimer', () => ({
  default: { initTimers: vi.fn(), clearTimers: vi.fn() },
}));

/** Só os eventos de `window`, na ordem em que foram postados para o SDK. */
const eventosEmitidos = () =>
  IFrameHelper.sendMessage.mock.calls
    .map(([mensagem]) => mensagem)
    .filter(mensagem => mensagem?.event === 'onEvent')
    .map(({ eventIdentifier, data }) => [eventIdentifier, data]);

const nomesEmitidos = () => eventosEmitidos().map(([nome]) => nome);

const contexto = () => ({ commit: vi.fn(), dispatch: vi.fn() });

describe('eventos de window emitidos do store (bloco 5.04)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    __resetSdkEventsForTests();
    // `endPoints` lê o locale daqui para montar a query da chamada. Sem isto a
    // ação estoura ANTES do POST e o teste ficaria verde por não emitir nada —
    // verde pelo motivo errado.
    window.WOOT_WIDGET = { $root: { $i18n: { locale: 'pt_BR' } } };
  });

  describe('pré-chat: conversation-created → prechat-submitted → lead-identified', () => {
    const respostaDoPreChat = {
      data: {
        id: 314,
        inbox_id: 7,
        contact: {
          name: 'Ana Prado',
          email: 'ana@exemplo.com.br',
          phone_number: null,
        },
        messages: [{ id: 1, content: 'Preciso de um orçamento' }],
      },
    };

    it('emite os três na ordem do aceite, a partir de UMA resposta', async () => {
      API.post.mockResolvedValue(respostaDoPreChat);

      await conversationActions.createConversation(contexto(), {
        fullName: 'Ana Prado',
        emailAddress: 'ana@exemplo.com.br',
        message: 'Preciso de um orçamento',
      });

      expect(nomesEmitidos()).toEqual([
        'chatwoot:conversation-created',
        'chatwoot:prechat-submitted',
        'chatwoot:lead-identified',
      ]);
    });

    it('leva o conversation_id e o inbox_id que o servidor devolveu', async () => {
      API.post.mockResolvedValue(respostaDoPreChat);

      await conversationActions.createConversation(contexto(), {
        fullName: 'Ana Prado',
        emailAddress: 'ana@exemplo.com.br',
      });

      const [, payload] = eventosEmitidos()[0];
      // 314 é o `display_id` — o mesmo id que a API pública usa em
      // `/conversations/{id}/messages`. É o único que serve para quem escuta
      // de fora do widget.
      expect(payload).toEqual({ conversation_id: 314, inbox_id: 7 });
    });

    it('manda os NOMES dos campos do pré-chat, nunca o que o visitante digitou', async () => {
      API.post.mockResolvedValue(respostaDoPreChat);

      await conversationActions.createConversation(contexto(), {
        fullName: 'Ana Prado',
        emailAddress: 'ana@exemplo.com.br',
        phoneNumber: '',
        contactCustomAttributes: { cnpj: '00.000.000/0001-00' },
      });

      const [, prechat] = eventosEmitidos()[1];
      expect(prechat).toEqual({
        fields: ['fullName', 'emailAddress', 'cnpj'],
      });

      const serializado = JSON.stringify(eventosEmitidos());
      expect(serializado).not.toContain('ana@exemplo.com.br');
      expect(serializado).not.toContain('Ana Prado');
      expect(serializado).not.toContain('00.000.000/0001-00');
    });

    it('não emite nada quando o servidor recusou a conversa', async () => {
      API.post.mockRejectedValue(new Error('500'));

      await conversationActions.createConversation(contexto(), {
        emailAddress: 'ana@exemplo.com.br',
      });

      // O pré-chat só está CONCLUÍDO quando o servidor aceitou. Emitir na
      // intenção é o defeito que `chatwoot:on-start-conversation` já tem e que
      // este bloco existe para não repetir.
      expect(nomesEmitidos()).toEqual([]);
    });

    it('não emite lead-identified quando o pré-chat não pediu identificador', async () => {
      API.post.mockResolvedValue({
        data: {
          id: 315,
          inbox_id: 7,
          contact: { name: 'Anônimo', email: null, phone_number: null },
          messages: [{ id: 2 }],
        },
      });

      await conversationActions.createConversation(contexto(), {
        fullName: 'Anônimo',
        message: 'oi',
      });

      expect(nomesEmitidos()).toEqual([
        'chatwoot:conversation-created',
        'chatwoot:prechat-submitted',
      ]);
    });
  });

  describe('sem pré-chat: a conversa nasce da primeira mensagem', () => {
    const estadoSemConversa = {
      conversationAttributes: { id: '' },
      conversation: { conversations: {} },
    };

    it('emite conversation-created antes de message-sent', async () => {
      API.post.mockResolvedValue({
        data: { id: 900, conversation_id: 77, content: 'oi' },
      });

      await conversationActions.sendMessageWithData(
        { commit: vi.fn(), rootState: estadoSemConversa },
        { message: { id: 'temp-1', content: 'oi' } }
      );

      expect(eventosEmitidos()).toEqual([
        ['chatwoot:conversation-created', { conversation_id: 77 }],
        ['chatwoot:message-sent', { conversation_id: 77 }],
      ]);
    });

    it('NÃO repete conversation-created para quem já tinha conversa', async () => {
      API.post.mockResolvedValue({
        data: { id: 901, conversation_id: 77, content: 'segunda' },
      });

      await conversationActions.sendMessageWithData(
        {
          commit: vi.fn(),
          rootState: {
            conversationAttributes: { id: 77 },
            conversation: { conversations: {} },
          },
        },
        { message: { id: 'temp-2', content: 'segunda' } }
      );

      expect(nomesEmitidos()).toEqual(['chatwoot:message-sent']);
    });

    it('NÃO repete conversation-created quando já havia mensagens antigas', async () => {
      // Segundo sinal independente do primeiro: `fetchOldConversations` enche o
      // mapa de mensagens antes de `getAttributes` responder. Sem esta leitura,
      // uma corrida entre as duas chamadas do boot produziria um
      // `conversation-created` falso para quem voltou ao site.
      API.post.mockResolvedValue({
        data: { id: 902, conversation_id: 77, content: 'de volta' },
      });

      await conversationActions.sendMessageWithData(
        {
          commit: vi.fn(),
          rootState: {
            conversationAttributes: { id: '' },
            conversation: { conversations: { 500: { id: 500 } } },
          },
        },
        { message: { id: 'temp-3', content: 'de volta' } }
      );

      expect(nomesEmitidos()).toEqual(['chatwoot:message-sent']);
    });

    it('não emite quando o envio da mensagem falhou', async () => {
      API.post.mockRejectedValue(new Error('timeout'));

      await conversationActions.sendMessageWithData(
        { commit: vi.fn(), rootState: estadoSemConversa },
        { message: { id: 'temp-4', content: 'oi' } }
      );

      expect(nomesEmitidos()).toEqual([]);
    });
  });

  describe('lead-identified é TRANSIÇÃO, não estado', () => {
    it('não sai de contacts/get — que é leitura, e roda no boot de todo visitante', async () => {
      // Emitir daqui dispararia um Lead por carregamento de página para quem já
      // era identificado. Conversão inflada é o defeito que este plano existe
      // para não cometer.
      API.get.mockResolvedValue({
        data: { id: 19, email: 'ja-identificado@exemplo.com.br' },
      });

      await contactActions.get({ commit: vi.fn() });

      expect(nomesEmitidos()).toEqual([]);
    });

    it('sai de contacts/update, que é o visitante acabando de digitar', async () => {
      API.patch.mockResolvedValue({ data: {} });

      await contactActions.update(
        { dispatch: vi.fn() },
        { user: { email: 'nova@exemplo.com.br', name: 'Nova' } }
      );

      expect(eventosEmitidos()).toEqual([
        ['chatwoot:lead-identified', { identifiers: ['email'] }],
      ]);
    });

    it('sai do input_email respondido no meio da conversa', async () => {
      API.patch.mockResolvedValue({ data: {} });

      await messageActions.update(
        {
          commit: vi.fn(),
          dispatch: vi.fn(),
          getters: { getUIFlags: { isUpdating: false } },
        },
        { email: 'meio@exemplo.com.br', messageId: 55, submittedValues: null }
      );

      expect(eventosEmitidos()).toEqual([
        ['chatwoot:lead-identified', { identifiers: ['email'] }],
      ]);
    });
  });

  describe('CSAT', () => {
    const contextoDeMensagem = () => ({
      commit: vi.fn(),
      dispatch: vi.fn(),
      getters: { getUIFlags: { isUpdating: false } },
    });

    it('emite a nota, uma vez por pesquisa', async () => {
      API.patch.mockResolvedValue({ data: {} });
      const payload = {
        messageId: 55,
        submittedValues: {
          csat_survey_response: { rating: 4, feedback_message: '' },
        },
      };

      await messageActions.update(contextoDeMensagem(), payload);
      // O visitante responde a nota e depois escreve o comentário: duas
      // submissões, um fato.
      await messageActions.update(contextoDeMensagem(), {
        ...payload,
        submittedValues: {
          csat_survey_response: { rating: 4, feedback_message: 'ótimo' },
        },
      });

      expect(eventosEmitidos()).toEqual([
        ['chatwoot:csat-submitted', { rating: 4 }],
      ]);
    });

    it('conta por mensagem: duas pesquisas diferentes, dois eventos', async () => {
      API.patch.mockResolvedValue({ data: {} });

      await messageActions.update(contextoDeMensagem(), {
        messageId: 55,
        submittedValues: { csat_survey_response: { rating: 5 } },
      });
      await messageActions.update(contextoDeMensagem(), {
        messageId: 88,
        submittedValues: { csat_survey_response: { rating: 2 } },
      });

      expect(eventosEmitidos()).toEqual([
        ['chatwoot:csat-submitted', { rating: 5 }],
        ['chatwoot:csat-submitted', { rating: 2 }],
      ]);
    });
  });

  describe('campanha', () => {
    it('emite campaign-shown uma vez por campanha', async () => {
      API.get.mockResolvedValue({ data: [{ id: 12, title: 'Teaser' }] });
      const ctx = {
        commit: vi.fn(),
        rootState: { appConfig: { isWidgetOpen: false } },
      };

      await campaignActions.startCampaign(ctx, {
        websiteToken: 'tok',
        campaignId: 12,
      });
      await campaignActions.startCampaign(ctx, {
        websiteToken: 'tok',
        campaignId: 12,
      });

      expect(eventosEmitidos()).toEqual([
        ['chatwoot:campaign-shown', { campaign_id: 12 }],
      ]);
    });

    it('não emite com o widget aberto — a campanha nem chega a ser exibida', async () => {
      API.get.mockResolvedValue({ data: [{ id: 12 }] });

      await campaignActions.startCampaign(
        { commit: vi.fn(), rootState: { appConfig: { isWidgetOpen: true } } },
        { websiteToken: 'tok', campaignId: 12 }
      );

      expect(nomesEmitidos()).toEqual([]);
    });
  });
});
