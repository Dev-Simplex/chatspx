import endPoints from 'widget/api/endPoints';
import { API } from 'widget/helpers/axios';

/**
 * A chave de um envio.
 *
 * `crypto.randomUUID` quando existe; caso contrario, tempo + aleatorio. O
 * fallback nao e enfeite: `randomUUID` exige contexto seguro, e o widget roda
 * dentro do site do cliente — um cliente ainda em http teria a chave `undefined`
 * em toda mensagem, e todas as mensagens dele viveriam colididas.
 */
export const novaChaveDeEnvio = () =>
  window.crypto?.randomUUID?.() ??
  `w-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;

const createConversationAPI = async content => {
  const urlData = endPoints.createConversation(content);
  return API.post(urlData.url, urlData.params);
};

/**
 * Envia uma mensagem, com chave de idempotencia (bloco 2.15).
 *
 * `echoId` e opcional e, quando ausente, uma chave nova e gerada aqui. Quem
 * reenvia a MESMA mensagem precisa passar a chave da primeira tentativa — e e
 * por isso que ela e devolvida junto da promessa, em vez de ficar escondida.
 */
const sendMessageAPI = async (
  content,
  replyTo = null,
  { customAttributes, labels, echoId } = {}
) => {
  const chave = echoId || novaChaveDeEnvio();
  const urlData = endPoints.sendMessage(content, replyTo, {
    customAttributes,
    labels,
    echoId: chave,
  });
  const resposta = await API.post(urlData.url, urlData.params);
  resposta.echoId = chave;
  return resposta;
};

const sendAttachmentAPI = async (
  attachment,
  { customAttributes, labels } = {}
) => {
  const urlData = endPoints.sendAttachment(attachment, {
    customAttributes,
    labels,
  });
  return API.post(urlData.url, urlData.params);
};

const getMessagesAPI = async ({ before, after }) => {
  const urlData = endPoints.getConversation({ before, after });
  return API.get(urlData.url, { params: urlData.params });
};

const getConversationAPI = async () => {
  return API.get(`/api/v1/widget/conversations${window.location.search}`);
};

const toggleTyping = async ({ typingStatus }) => {
  return API.post(
    `/api/v1/widget/conversations/toggle_typing${window.location.search}`,
    { typing_status: typingStatus }
  );
};

const setUserLastSeenAt = async ({ lastSeen }) => {
  return API.post(
    `/api/v1/widget/conversations/update_last_seen${window.location.search}`,
    { contact_last_seen_at: lastSeen }
  );
};
const sendEmailTranscript = async () => {
  return API.post(
    `/api/v1/widget/conversations/transcript${window.location.search}`
  );
};
const toggleStatus = async () => {
  return API.get(
    `/api/v1/widget/conversations/toggle_status${window.location.search}`
  );
};

const setCustomAttributes = async customAttributes => {
  return API.post(
    `/api/v1/widget/conversations/set_custom_attributes${window.location.search}`,
    {
      custom_attributes: customAttributes,
    }
  );
};

const deleteCustomAttribute = async customAttribute => {
  return API.post(
    `/api/v1/widget/conversations/destroy_custom_attributes${window.location.search}`,
    {
      custom_attribute: [customAttribute],
    }
  );
};

export {
  createConversationAPI,
  sendMessageAPI,
  getConversationAPI,
  getMessagesAPI,
  sendAttachmentAPI,
  toggleTyping,
  setUserLastSeenAt,
  sendEmailTranscript,
  toggleStatus,
  setCustomAttributes,
  deleteCustomAttribute,
};
