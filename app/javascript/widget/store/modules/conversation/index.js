import { getters } from './getters';
import { actions } from './actions';
import { mutations } from './mutations';

const state = {
  conversations: {},
  meta: {
    userLastSeenAt: undefined,
  },
  uiFlags: {
    allMessagesLoaded: false,
    isFetchingList: false,
    isAgentTyping: false,
    isCreating: false,
  },
  lastMessageId: null,

  // Metadados capturados ANTES de existir conversa (visitante novo mandando a
  // primeira mensagem). `setCustomAttributes` guarda aqui quando
  // `conversationAttributes/getConversationParams.id` esta vazio, e `sendMessage`
  // envia junto com a primeira mensagem — e assim a conversa NASCE com o
  // `first_utm_source`/`gclid` certos (plano o3-flows-captura, linha 630).
  // `pendingLabels` existe porque `sendMessage` desestrutura e
  // `clearPendingConversationMetadata` zera os dois; o produtor de label
  // (`setPendingLabels`) nao foi trazido — nenhuma action nossa o chama.
  pendingCustomAttributes: {},
  pendingLabels: [],
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
