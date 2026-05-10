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

  shareLocation(conversationId, { latitude, longitude, address }) {
    return axios.post(`${this.url}/${conversationId}/messages/share_location`, {
      latitude,
      longitude,
      address,
    });
  }

  shareContact(
    conversationId,
    { source, name, phone, contact_id: contactId, agent_id: agentId }
  ) {
    return axios.post(`${this.url}/${conversationId}/messages/share_contact`, {
      source,
      name,
      phone,
      contact_id: contactId,
      agent_id: agentId,
    });
  }

  updateContent(conversationId, messageId, content) {
    return axios.patch(`${this.url}/${conversationId}/messages/${messageId}`, {
      content,
    });
  }

  retry(conversationID, messageId) {
    return axios.post(
      `${this.url}/${conversationID}/messages/${messageId}/retry`
    );
  }

  toggleReaction(conversationId, messageId, emoji) {
    return axios.post(
      `${this.url}/${conversationId}/messages/${messageId}/reactions`,
      { emoji }
    );
  }

  toggleStar(conversationId, messageId) {
    return axios.post(
      `${this.url}/${conversationId}/messages/${messageId}/star`
    );
  }

  getPreviousMessages({
    conversationId,
    after,
    before,
    limit,
    includeMeta,
    include_meta: includeMetaLegacy,
  }) {
    const params = {};

    if (before) {
      params.before = before;
    }
    if (after && Number(after) !== Number(before)) {
      params.after = after;
    }

    if (limit) {
      params.limit = limit;
    }

    const shouldIncludeMeta = includeMeta ?? includeMetaLegacy;
    if (typeof shouldIncludeMeta === 'boolean') {
      params.include_meta = shouldIncludeMeta;
    }

    return axios.get(`${this.url}/${conversationId}/messages`, { params });
  }

  // eslint-disable-next-line class-methods-use-this
  async getAllMessages(conversationId, options = {}) {
    /* eslint-disable no-await-in-loop, no-plusplus, no-promise-executor-return */
    const {
      onProgress,
      maxMessages = 500,
      maxIterations = 50,
      requestTimeout = 30000,
      totalTimeout = 120000,
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
            const newMessages = messages.filter(
              msg => !existingIds.has(msg.id)
            );

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
            const backoffDelay = 2 ** retries * 1000;
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
    /* eslint-enable no-await-in-loop, no-plusplus, no-promise-executor-return */
  }

  translateMessage(conversationId, messageId, targetLanguage) {
    return axios.post(
      `${this.url}/${conversationId}/messages/${messageId}/translate`,
      {
        target_language: targetLanguage,
      }
    );
  }
}

/**
 * Busca todas as mensagens de uma conversa usando paginação
 * @param {number} conversationId - ID da conversa
 * @param {Object} options - Opções de controle
 * @param {AbortSignal} options.signal - AbortController signal para cancelamento
 * @param {number} options.maxIterations - Limite de iterações (padrão: 100)
 * @param {number} options.requestTimeout - Timeout por request em ms (padrão: 30000)
 * @param {number} options.totalTimeout - Timeout total em ms (padrão: 120000)
 * @returns {Promise<Array>} Array de todas as mensagens
 */
/* eslint-disable no-await-in-loop */
export const getAllMessages = async (conversationId, options = {}) => {
  const {
    signal,
    maxIterations = 100,
    requestTimeout = 30000,
    totalTimeout = 120000,
  } = options;

  let allMessages = [];
  let before = null;
  let hasMore = true;
  let iterations = 0;
  const startTime = Date.now();

  while (hasMore && iterations < maxIterations) {
    // Verificar cancelamento externo
    if (signal?.aborted) {
      break;
    }

    // Verificar timeout total
    if (Date.now() - startTime > totalTimeout) {
      // eslint-disable-next-line no-console
      console.warn(
        `Timeout total ao buscar mensagens da conversa ${conversationId}`
      );
      break;
    }

    try {
      const params = before ? { before } : {};
      const response = await axios.get(
        `${MessageApi.url}/${conversationId}/messages`,
        { params, signal, timeout: requestTimeout }
      );

      const messages = response.data?.payload || [];

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

        // Verificar se não há mais mensagens (se o before não mudou)
        if (previousBefore === before) {
          hasMore = false;
        }
      }
      iterations += 1;
    } catch (error) {
      // Propagate abort errors so callers can distinguish cancellation
      if (axios.isCancel(error) || error.name === 'AbortError') {
        throw error;
      }
      // eslint-disable-next-line no-console
      console.error(
        `Erro ao buscar mensagens da conversa ${conversationId}:`,
        error
      );
      hasMore = false;
    }
  }

  return allMessages;
};
/* eslint-enable no-await-in-loop */

export default new MessageApi();
