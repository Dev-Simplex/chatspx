/* eslint no-console: 0 */
/* global axios */
import ApiClient from '../ApiClient';

export const buildCreatePayload = ({
  message,
  isPrivate,
  contentAttributes,
  echoId,
  files,
  ccEmails = '',
  bccEmails = '',
  toEmails = '',
  templateParams,
}) => {
  let payload;
  if (files && files.length !== 0) {
    payload = new FormData();
    if (message) {
      payload.append('content', message);
    }
    files.forEach(file => {
      payload.append('attachments[]', file);
    });
    payload.append('private', isPrivate);
    payload.append('echo_id', echoId);
    payload.append('cc_emails', ccEmails);
    payload.append('bcc_emails', bccEmails);

    if (toEmails) {
      payload.append('to_emails', toEmails);
    }
    if (contentAttributes) {
      payload.append('content_attributes', JSON.stringify(contentAttributes));
    }
  } else {
    payload = {
      content: message,
      private: isPrivate,
      echo_id: echoId,
      content_attributes: contentAttributes,
      cc_emails: ccEmails,
      bcc_emails: bccEmails,
      to_emails: toEmails,
      template_params: templateParams,
    };
  }
  return payload;
};

class MessageApi extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  create({
    conversationId,
    message,
    private: isPrivate,
    contentAttributes,
    echo_id: echoId,
    files,
    ccEmails = '',
    bccEmails = '',
    toEmails = '',
    templateParams,
  }) {
    return axios({
      method: 'post',
      url: `${this.url}/${conversationId}/messages`,
      data: buildCreatePayload({
        message,
        isPrivate,
        contentAttributes,
        echoId,
        files,
        ccEmails,
        bccEmails,
        toEmails,
        templateParams,
      }),
    });
  }

  delete(conversationID, messageId) {
    return axios.delete(`${this.url}/${conversationID}/messages/${messageId}`);
  }

  retry(conversationID, messageId) {
    return axios.post(
      `${this.url}/${conversationID}/messages/${messageId}/retry`
    );
  }

  getPreviousMessages({ conversationId, after, before, starred }) {
    const params = { before };
    if (after && Number(after) !== Number(before)) {
      params.after = after;
    }
    if (starred) {
      params.starred = 'true';
    }
    return axios.get(`${this.url}/${conversationId}/messages`, { params });
  }

  getStarredMessages({ conversationId }) {
    return axios.get(`${this.url}/${conversationId}/messages`, {
      params: {
        starred: 'true',
      },
    });
  }

  async getAllMessages(conversationId, options = {}) {
    const {
      onProgress,
      maxMessages = 10000,
      maxIterations = 500,
      requestTimeout = 30000,
      totalTimeout = 300000,
    } = options;

    let allMessages = [];
    let before = null;
    let hasMore = true;
    let iterations = 0;
    const startTime = Date.now();

    while (hasMore && iterations < maxIterations) {
      // Verificar timeout total
      if (Date.now() - startTime > totalTimeout) {
        // eslint-disable-next-line no-console
        console.warn(
          `Timeout ao buscar mensagens da conversa ${conversationId}`
        );
        break;
      }

      // Verificar limite de mensagens
      if (allMessages.length >= maxMessages) {
        // eslint-disable-next-line no-console
        console.warn(
          `Limite de ${maxMessages} mensagens atingido para conversa ${conversationId}`
        );
        break;
      }

      let retries = 0;
      const maxRetries = 3;
      let success = false;

      while (retries < maxRetries && !success) {
        try {
          const params = before ? { before } : {};
          const response = await Promise.race([
            axios.get(`${this.url}/${conversationId}/messages`, { params }),
            new Promise((_, reject) =>
              setTimeout(
                () => reject(new Error('Request timeout')),
                requestTimeout
              )
            ),
          ]);

          const messages = response.data.payload || [];
          const meta = response.data.meta || {};

          // Verificar metadados de paginação se disponíveis
          if (meta.has_more === false || meta.next_page === null) {
            hasMore = false;
          }

          if (messages.length === 0) {
            hasMore = false;
          } else {
            const previousBefore = before;
            
            // Remover mensagens duplicadas baseado no ID antes de adicionar
            const existingIds = new Set(allMessages.map(msg => msg.id));
            const newMessages = messages.filter(msg => !existingIds.has(msg.id));
            
            // Adicionar apenas mensagens novas (sem duplicatas)
            allMessages = [...newMessages, ...allMessages];
            before = messages[messages.length - 1].id;

            // Se before não mudou, provavelmente não há mais mensagens
            if (previousBefore === before) {
              hasMore = false;
            }

            // Callback de progresso
            if (onProgress) {
              onProgress(allMessages.length, messages.length);
            }
          }

          success = true;
          iterations++;
        } catch (error) {
          // Retry logic com backoff exponencial
          const isRetryable =
            error.code === 'ECONNABORTED' ||
            error.message.includes('timeout') ||
            error.message.includes('Network Error');

          if (isRetryable && retries < maxRetries - 1) {
            const backoffDelay = Math.pow(2, retries) * 1000;
            // eslint-disable-next-line no-console
            console.warn(
              `Tentativa ${retries + 1} falhou para conversa ${conversationId}, tentando novamente em ${backoffDelay}ms`
            );
            await new Promise(resolve => setTimeout(resolve, backoffDelay));
            retries++;
          } else {
            // eslint-disable-next-line no-console
            console.error(
              `Erro ao buscar mensagens da conversa ${conversationId}:`,
              error
            );
            throw error;
          }
        }
      }
    }

    return { data: { payload: allMessages } };
  }

  translateMessage(conversationId, messageId, targetLanguage) {
    return axios.post(
      `${this.url}/${conversationId}/messages/${messageId}/translate`,
      {
        target_language: targetLanguage,
      }
    );
  }

  starMessage({ accountId, conversationId, messageId }) {
    return axios.post(
      `/api/v1/accounts/${accountId}/conversations/${conversationId}/messages/${messageId}/star`
    );
  }

  unstarMessage({ accountId, conversationId, messageId }) {
    return axios.delete(
      `/api/v1/accounts/${accountId}/conversations/${conversationId}/messages/${messageId}/star`
    );
  }
}

export default new MessageApi();
