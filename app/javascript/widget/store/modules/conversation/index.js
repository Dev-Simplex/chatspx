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
  // `pendingLabels` segue o mesmo caminho: `sendMessage` o desestrutura e
  // `clearPendingConversationMetadata` zera os dois. Bloco 0.2 (merge da
  // v4.16.2): o produtor (`setPendingLabels`) e o removedor
  // (`removePendingLabel`) passaram a existir junto com o resto do upstream —
  // nenhuma action nossa os chama ainda, mas o estado deixa de ter metade da
  // maquina, que era o que fazia o spec congelado do upstream reprovar.
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
