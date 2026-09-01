import {
  createConversationAPI,
  sendMessageAPI,
  novaChaveDeEnvio,
  getMessagesAPI,
  sendAttachmentAPI,
  toggleTyping,
  setUserLastSeenAt,
  toggleStatus,
  setCustomAttributes,
  deleteCustomAttribute,
} from 'widget/api/conversation';
import { widgetOfflineQueue } from 'widget/state';
import { isNetworkFailure } from 'widget/offline/networkFailure';

import { ON_CONVERSATION_CREATED } from 'widget/constants/widgetBusEvents';
import { createTemporaryMessage, getNonDeletedMessages } from './helpers';
import { emitter } from 'shared/helpers/mitt';
import { reportWidgetError } from 'widget/helpers/telemetry';
import { registrarConversaoDaAbordagem } from 'widget/api/approachEvent';
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

// ── Bloco 2.16 — o funil ÚNICO de "a rede caiu, guarde para depois" ──────────
//
// Todo `catch` de envio passa por aqui, inclusive os que NÃO devem ser
// guardados. É de propósito, e é o que faz o "nenhum evento de digitando em
// lote" ser uma propriedade do código e não do esquecimento de quem escreveu o
// call site: quem decide o que sobrevive é a fila (`INTENCOES` × `TRANSITORIOS`
// em `widget/offline/queue.js`), num lugar só, com teste próprio. Deixar cada
// chamador lembrar de não enfileirar o "digitando" é como o bug volta.
//
// @returns {boolean} `true` se a intenção ficou guardada para a volta da rede.
const enqueueOnNetworkFailure = (error, intent) => {
  if (!isNetworkFailure(error)) return false;
  return widgetOfflineQueue.enqueue(intent);
};

/**
 * A ENTREGA de uma mensagem — e ela LANÇA quando falha.
 *
 * Estava dentro de `sendMessageWithData`, que engole o erro para não interromper
 * o visitante. Isso é certo na primeira tentativa e é fatal na drenagem: um
 * envio que "nunca falha" faria `flush` tirar o item da fila e seguir para o
 * próximo, e a mensagem do meio sumiria — exatamente a perda que a fila para na
 * primeira falha para impedir. Por isso a entrega mora aqui, crua, e o
 * tratamento de erro fica em quem chama.
 */
const deliverMessage = async (
  { commit, rootState },
  { message, echoId, pendingCustomAttributes = {}, pendingLabels = [] }
) => {
  const { id, content, replyTo } = message;
  const hasPendingMetadata =
    Object.keys(pendingCustomAttributes).length > 0 || pendingLabels.length > 0;

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
  // antigas chegam por `fetchOldConversations`, que é outra chamada.
  //
  // Bloco 2.16: na DRENAGEM a mensagem temporária já está no mapa desde a
  // tentativa que falhou, então `conversations` nunca estaria vazio e o
  // `conversation-created` sumiria para quem mandou a primeira mensagem
  // offline. Por isso a contagem ignora as mensagens que ainda não foram
  // entregues — elas não são prova de que existe conversa no servidor.
  const entregues = Object.values(
    rootState?.conversation?.conversations || {}
  ).filter(m => m.status !== 'in_progress' && m.status !== 'failed');
  const conversaJaConhecida =
    Boolean(rootState?.conversationAttributes?.id) || entregues.length > 0;

  const { data } = await sendMessageAPI(content, replyTo, {
    customAttributes: hasPendingMetadata ? pendingCustomAttributes : undefined,
    labels: hasPendingMetadata ? pendingLabels : undefined,
    echoId,
  });
  if (hasPendingMetadata) {
    commit('clearPendingConversationMetadata');
  }

  // A temporária sai POR ID, e não pelo casamento de conteúdo que
  // `pushMessageToConversation` faz sozinho. Duas razões, e as duas são
  // defeito visível:
  //
  //  1. Aquele casamento só acha mensagem com status `in_progress`. Depois de
  //     uma falha o status é `failed`, então a temporária NÃO seria achada e a
  //     mensagem apareceria DUAS vezes na tela — a que falhou e a que chegou.
  //  2. Ele casa por CONTEÚDO. Quem manda "ok" duas vezes seguidas teria a
  //     primeira apagada pela resposta da segunda.
  commit('deleteMessage', id);
  commit('pushMessageToConversation', { ...data, status: 'sent' });

  // A conversa vem antes da mensagem: o fato "conversa criada" precede o
  // fato "mensagem enviada", mesmo tendo os dois nascido do mesmo POST.
  // `emitSdkEventOnce` usa a MESMA chave do caminho do pré-chat, então os
  // dois caminhos nunca emitem dois `conversation-created`.
  //
  // `inbox_id` vem JUNTO e não é enfeite: o contrato de
  // `chatwoot:conversation-created` declara as duas chaves
  // (`SDK_EVENT_CONTRACT`, e o documento em §3 exige `inbox_id` no
  // `chatspx_conversation_started` que este evento alimenta). Sem ela o
  // `filterByContract` não reclama — ele só conta chave a MAIS, e chave a
  // menos some calada —, e o evento chegava ao dataLayer do cliente sem
  // saber de qual caixa de entrada veio, só neste caminho.
  //
  // A resposta do POST de mensagem publica `inbox_id` no topo
  // (`api/v1/widget/messages/create.json.jbuilder`:
  // `json.inbox_id @message.inbox_id`), do mesmo jeito que a resposta do
  // POST de conversa. Os dois caminhos passam a emitir o mesmo payload.
  if (!conversaJaConhecida && data?.conversation_id) {
    emitSdkEventOnce(
      CHATWOOT_CONVERSATION_CREATED,
      { conversation_id: data.conversation_id, inbox_id: data.inbox_id },
      CHATWOOT_CONVERSATION_CREATED
    );
  }
  emitSdkEvent(CHATWOOT_MESSAGE_SENT, {
    conversation_id: data?.conversation_id,
  });
  // Bloco 4.21 — a CONVERSAO da abordagem. O visitante ENVIOU: e este o fato
  // que atribui a mensagem ao nivel de abordagem que a conquistou. Mora aqui
  // e nao no `ChatFooter` pela mesma razao do 5.04: componente monta e
  // desmonta a cada troca de rota, o store nao. E fica DEPOIS do `await` do
  // POST, porque conversao que o servidor recusou nao aconteceu.
  registrarConversaoDaAbordagem();
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
    contexto,
    { message, pendingCustomAttributes = {}, pendingLabels = [] }
  ) => {
    const { commit } = contexto;
    const { meta = {} } = message;

    // ── Bloco 2.16 + 2.15 — a chave nasce AQUI, e uma só por mensagem ────────
    //
    // Ela precisa sobreviver à falha: a tentativa que caiu e o reenvio da
    // drenagem têm de chegar ao servidor com o MESMO `echo_id`, senão a
    // idempotência do 2.15 não vale nada e a volta da rede duplica tudo que
    // estava na fila. Guardá-la NA MENSAGEM (e não só na intenção enfileirada)
    // faz o retry manual do `MessageRow.retrySendMessage` — que redispara esta
    // action com a mensagem do store — reusar a mesma chave também.
    const echoId = message.echoId || novaChaveDeEnvio();
    const mensagem = { ...message, echoId };
    const { id } = mensagem;

    commit('pushMessageToConversation', mensagem);
    commit('updateMessageMeta', { id, meta: { ...meta, error: '' } });
    try {
      await deliverMessage(contexto, {
        message: mensagem,
        echoId,
        pendingCustomAttributes,
        pendingLabels,
      });
    } catch (error) {
      commit('pushMessageToConversation', { ...mensagem, status: 'failed' });
      commit('updateMessageMeta', {
        id,
        meta: { ...meta, error: '' },
      });
      // A intenção guarda TUDO que o reenvio precisa, inclusive os metadados
      // pendentes: eles são zerados no primeiro envio bem-sucedido, e sem
      // carregá-los aqui a conversa nasceria sem os `utm_*`/`gclid` do
      // visitante que mandou a primeira mensagem offline.
      enqueueOnNetworkFailure(error, {
        type: 'send_message',
        message: mensagem,
        echoId,
        pendingCustomAttributes,
        pendingLabels,
      });
    }
  },

  /**
   * A DRENAGEM — bloco 2.16. Chamada pelo plugin do store na volta da rede.
   *
   * Ela repassa `deliverMessage` cru para o `flush`, que é o ponto: a falha
   * PRECISA propagar para a fila parar no item que caiu e não pular a mensagem
   * do meio. Um `dispatch('sendMessageWithData')` aqui teria a aparência certa
   * e o comportamento errado — aquela action engole o erro, então o `flush`
   * acharia que tudo foi entregue e esvaziaria a fila em cima de uma rede que
   * ainda está caindo.
   */
  drainOfflineQueue: async contexto =>
    widgetOfflineQueue.flush(intent => deliverMessage(contexto, intent)),

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
      // ── Bloco 2.16, e este OFERECIMENTO é o ponto do bloco ────────────────
      //
      // "Digitando" que falhou passa pelo mesmo funil da mensagem — e é
      // RECUSADO ali, por ser estado transitório. Poderia não passar: o `catch`
      // vazio de antes produzia o mesmo resultado visível.
      //
      // A diferença é que assim a recusa é um FATO MEDIDO, e não uma ausência.
      // Um teste de "nenhum digitando na volta" passa igualzinho se ninguém
      // chegou a oferecer nada — inclusive com a fila inteira desligada, que é
      // exatamente o estado em que este bloco estava. Oferecendo, a garantia
      // vira código: mesmo que alguém acrescente `typing_on` à lista de
      // intenções, `queue.spec.js` fica vermelho na hora.
      //
      // O `status` transitório também não é o que o agente precisa ver dez
      // segundos depois: um lote de três "digitando" na volta da rede descreve
      // alguém que parou de digitar faz meio minuto.
      enqueueOnNetworkFailure(error, {
        type: `typing_${data?.typingStatus === 'on' ? 'on' : 'off'}`,
      });
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
