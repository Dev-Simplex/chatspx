import {
  createConversationAPI,
  sendMessageAPI,
  getMessagesAPI,
  sendAttachmentAPI,
  toggleTyping,
  setUserLastSeenAt,
  toggleStatus,
  setCustomAttributes,
  deleteCustomAttribute,
} from 'widget/api/conversation';

import { ON_CONVERSATION_CREATED } from 'widget/constants/widgetBusEvents';
import { createTemporaryMessage, getNonDeletedMessages } from './helpers';
import { emitter } from 'shared/helpers/mitt';
import { reportWidgetError } from 'widget/helpers/telemetry';
import {
  emitLeadIdentified,
  emitSdkEvent,
  emitSdkEventOnce,
} from 'widget/helpers/sdkEventEmitter';
import {
  CHATWOOT_CONVERSATION_CREATED,
  CHATWOOT_MESSAGE_SENT,
  CHATWOOT_PRECHAT_SUBMITTED,
} from 'widget/constants/sdkEvents';

// Bloco 5.04 — os NOMES dos campos que o visitante preencheu no pré-chat.
// Nomes, nunca valores: o payload vai para o `window` do site, que qualquer
// script de terceiro lê (regra dura de `24-plano-backend-dados.md` §17.1).
// A lista é a dos campos padrão que `views/PreChatForm.vue` repassa; campo
// customizado entra por `contactCustomAttributes`/`conversationCustomAttributes`
// e é reportado pelo nome da chave, também sem valor.
const CAMPOS_PADRAO_DO_PRECHAT = ['fullName', 'emailAddress', 'phoneNumber'];

export const preChatFieldNames = (params = {}) => {
  const preenchidos = CAMPOS_PADRAO_DO_PRECHAT.filter(campo => {
    const valor = params[campo];
    return typeof valor === 'string' && valor.trim() !== '';
  });
  const customizados = [
    ...Object.keys(params.contactCustomAttributes || {}),
    ...Object.keys(params.conversationCustomAttributes || {}),
  ];

  return [...preenchidos, ...customizados];
};

export const actions = {
  createConversation: async ({ commit, dispatch }, params) => {
    commit('setConversationUIFlag', { isCreating: true });
    try {
      const { data } = await createConversationAPI(params);
      const { messages } = data;
      const [message = {}] = messages;
      commit('pushMessageToConversation', message);

      // ── Bloco 5.04, e a ORDEM aqui é o aceite ────────────────────────────
      //
      // `widget_opened → conversation_created → prechat_submitted →
      // lead_identified`. Os três últimos saem desta resposta, nesta ordem,
      // porque é esta resposta que os torna verdadeiros ao mesmo tempo: o
      // pré-chat só está CONCLUÍDO quando o servidor aceitou; se o POST
      // falhasse, nenhum dos três teria acontecido.
      //
      // `data.id` é o `display_id` da conversa (ver
      // `api/v1/widget/conversations/create.json.jbuilder`) — o mesmo id que a
      // API pública usa em `/conversations/{id}/messages`, e portanto o único
      // que serve para quem escuta do lado de fora.
      emitSdkEventOnce(
        CHATWOOT_CONVERSATION_CREATED,
        { conversation_id: data.id, inbox_id: data.inbox_id },
        CHATWOOT_CONVERSATION_CREATED
      );
      emitSdkEvent(CHATWOOT_PRECHAT_SUBMITTED, {
        fields: preChatFieldNames(params),
      });
      emitLeadIdentified({ contact: data.contact, conversationId: data.id });

      dispatch('conversationAttributes/getAttributes', {}, { root: true });
      // Emit event to notify that conversation is created and show the chat screen
      emitter.emit(ON_CONVERSATION_CREATED);
    } catch (error) {
      // Bloco 2.13. Era `// Ignore error` — o widget quebrava no site do
      // cliente e ninguém ficava sabendo. O erro continua sem interromper o
      // visitante; passa apenas a ser CONTADO.
      reportWidgetError(error, { origem: 'store/conversation' });
    } finally {
      commit('setConversationUIFlag', { isCreating: false });
    }
  },
  sendMessage: async ({ dispatch, state: conversationState }, params) => {
    const { content, replyTo } = params;
    const message = createTemporaryMessage({ content, replyTo });
    const { pendingCustomAttributes, pendingLabels } = conversationState;
    dispatch('sendMessageWithData', {
      message,
      pendingCustomAttributes,
      pendingLabels,
    });
  },
  sendMessageWithData: async (
    { commit, rootState },
    { message, pendingCustomAttributes = {}, pendingLabels = [] }
  ) => {
    const { id, content, replyTo, meta = {} } = message;
    const hasPendingMetadata =
      Object.keys(pendingCustomAttributes).length > 0 ||
      pendingLabels.length > 0;

    // Bloco 5.04 — lido ANTES dos commits, e é a diferença entre um evento
    // certo e um evento mentiroso.
    //
    // Sem pré-chat, a conversa nasce no servidor junto com a PRIMEIRA mensagem:
    // não há POST /conversations, e sem esta leitura o
    // `chatwoot:conversation-created` nunca sairia nesse caminho. Com pré-chat,
    // ou para quem volta com conversa antiga, a conversa JÁ existe — e aí o
    // evento não pode sair de novo.
    //
    // Duas leituras independentes porque nenhuma sozinha basta: `id` chega por
    // `getAttributes`, que é assíncrono e pode não ter voltado; as mensagens
    // antigas chegam por `fetchOldConversations`, que é outra chamada. Ler as
    // duas antes do `pushMessageToConversation` é obrigatório — o commit abaixo
    // insere a mensagem temporária e faria o mapa parecer não-vazio.
    const conversaJaConhecida =
      Boolean(rootState?.conversationAttributes?.id) ||
      Object.keys(rootState?.conversation?.conversations || {}).length > 0;

    commit('pushMessageToConversation', message);
    commit('updateMessageMeta', { id, meta: { ...meta, error: '' } });
    try {
      const { data } = await sendMessageAPI(content, replyTo, {
        customAttributes: hasPendingMetadata
          ? pendingCustomAttributes
          : undefined,
        labels: hasPendingMetadata ? pendingLabels : undefined,
      });
      if (hasPendingMetadata) {
        commit('clearPendingConversationMetadata');
      }

      // [VITE] Don't delete this manually, since `pushMessageToConversation` does the replacement for us anyway
      // commit('deleteMessage', message.id);
      commit('pushMessageToConversation', { ...data, status: 'sent' });

      // A conversa vem antes da mensagem: o fato "conversa criada" precede o
      // fato "mensagem enviada", mesmo tendo os dois nascido do mesmo POST.
      // `emitSdkEventOnce` usa a MESMA chave do caminho do pré-chat, então os
      // dois caminhos nunca emitem dois `conversation-created`.
      if (!conversaJaConhecida && data?.conversation_id) {
        emitSdkEventOnce(
          CHATWOOT_CONVERSATION_CREATED,
          { conversation_id: data.conversation_id },
          CHATWOOT_CONVERSATION_CREATED
        );
      }
      emitSdkEvent(CHATWOOT_MESSAGE_SENT, {
        conversation_id: data?.conversation_id,
      });
    } catch (error) {
      commit('pushMessageToConversation', { ...message, status: 'failed' });
      commit('updateMessageMeta', {
        id,
        meta: { ...meta, error: '' },
      });
    }
  },

  setLastMessageId: async ({ commit }) => {
    commit('setLastMessageId');
  },

  sendAttachment: async ({ commit, state: conversationState }, params) => {
    const {
      attachment: { thumbUrl, fileType },
      meta = {},
    } = params;
    const attachment = {
      thumb_url: thumbUrl,
      data_url: thumbUrl,
      file_type: fileType,
      status: 'in_progress',
    };
    const tempMessage = createTemporaryMessage({
      attachments: [attachment],
      replyTo: params.replyTo,
    });
    const { pendingCustomAttributes, pendingLabels } = conversationState;
    const hasPendingMetadata =
      Object.keys(pendingCustomAttributes).length > 0 ||
      pendingLabels.length > 0;

    commit('pushMessageToConversation', tempMessage);
    try {
      const { data } = await sendAttachmentAPI(params, {
        customAttributes: hasPendingMetadata
          ? pendingCustomAttributes
          : undefined,
        labels: hasPendingMetadata ? pendingLabels : undefined,
      });
      if (hasPendingMetadata) {
        commit('clearPendingConversationMetadata');
      }
      commit('updateAttachmentMessageStatus', {
        message: data,
        tempId: tempMessage.id,
      });
      commit('pushMessageToConversation', { ...data, status: 'sent' });
    } catch (error) {
      commit('pushMessageToConversation', { ...tempMessage, status: 'failed' });
      commit('updateMessageMeta', {
        id: tempMessage.id,
        meta: { ...meta, error: '' },
      });
      // Show error
    }
  },
  fetchOldConversations: async ({ commit }, { before } = {}) => {
    try {
      commit('setConversationListLoading', true);
      const {
        data: { payload, meta },
      } = await getMessagesAPI({ before });
      const { contact_last_seen_at: lastSeen } = meta;
      const formattedMessages = getNonDeletedMessages({ messages: payload });
      commit('conversation/setMetaUserLastSeenAt', lastSeen, { root: true });
      commit('setMessagesInConversation', formattedMessages);
      commit('setConversationListLoading', false);
    } catch (error) {
      commit('setConversationListLoading', false);
    }
  },

  syncLatestMessages: async ({ state, commit }) => {
    try {
      const { lastMessageId, conversations } = state;

      const {
        data: { payload, meta },
      } = await getMessagesAPI({ after: lastMessageId });

      const { contact_last_seen_at: lastSeen } = meta;
      const formattedMessages = getNonDeletedMessages({ messages: payload });
      const missingMessages = formattedMessages.filter(
        message => conversations?.[message.id] === undefined
      );
      if (!missingMessages.length) return;
      missingMessages.forEach(message => {
        conversations[message.id] = message;
      });
      // Sort conversation messages by created_at
      const updatedConversation = Object.fromEntries(
        Object.entries(conversations).sort(
          (a, b) => a[1].created_at - b[1].created_at
        )
      );
      commit('conversation/setMetaUserLastSeenAt', lastSeen, { root: true });
      commit('setMissingMessagesInConversation', updatedConversation);
    } catch (error) {
      // IgnoreError
    }
  },

  clearConversations: ({ commit }) => {
    commit('clearConversations');
  },

  addOrUpdateMessage: async ({ commit }, data) => {
    const { id, content_attributes } = data;
    if (content_attributes && content_attributes.deleted) {
      commit('deleteMessage', id);
      return;
    }
    commit('pushMessageToConversation', data);
  },

  toggleAgentTyping({ commit }, data) {
    commit('toggleAgentTypingStatus', data);
  },

  toggleUserTyping: async (_, data) => {
    try {
      await toggleTyping(data);
    } catch (error) {
      // IgnoreError
    }
  },

  setUserLastSeen: async ({ commit, getters: appGetters }) => {
    if (!appGetters.getConversationSize) {
      return;
    }

    const lastSeen = Date.now() / 1000;
    try {
      commit('setMetaUserLastSeenAt', lastSeen);
      await setUserLastSeenAt({ lastSeen });
    } catch (error) {
      // IgnoreError
    }
  },

  resolveConversation: async () => {
    await toggleStatus();
  },

  setCustomAttributes: async (
    { commit, rootGetters },
    customAttributes = {}
  ) => {
    if (!rootGetters['conversationAttributes/getConversationParams']?.id) {
      commit('setPendingCustomAttributes', customAttributes);
      return;
    }
    try {
      await setCustomAttributes(customAttributes);
    } catch (error) {
      // IgnoreError
    }
  },

  deleteCustomAttribute: async ({ commit, rootGetters }, customAttribute) => {
    if (!rootGetters['conversationAttributes/getConversationParams']?.id) {
      commit('removePendingCustomAttribute', customAttribute);
      return;
    }
    try {
      await deleteCustomAttribute(customAttribute);
    } catch (error) {
      // IgnoreError
    }
  },
};
