/* eslint-disable no-plusplus, no-await-in-loop, no-shadow */
import html2pdf from 'html2pdf.js';
import MessageAPI from '../api/inbox/message';
import { format, fromUnixTime } from 'date-fns';
import { MESSAGE_TYPE } from 'shared/constants/messages';

// Limites para geração de PDF
const MAX_CONVERSATIONS = 5; // Limite de conversas simultâneas
const MAX_MESSAGES_PER_CONVERSATION = 500; // Limite de mensagens por conversa
const MAX_TOTAL_MESSAGES = 2000; // Limite total de mensagens

/**
 * Ordena conversas por data (mais antiga primeiro)
 */
export const sortConversationsChronologically = conversations => {
  return [...conversations].sort((a, b) => {
    const dateA = a.createdAt || a.timestamp || 0;
    const dateB = b.createdAt || b.timestamp || 0;
    return dateA - dateB;
  });
};

/**
 * Ordena mensagens por data (mais antiga primeiro)
 */
export const sortMessagesChronologically = messages => {
  return [...messages].sort((a, b) => {
    const dateA = a.createdAt || a.created_at || 0;
    const dateB = b.createdAt || b.created_at || 0;
    return dateA - dateB;
  });
};

/**
 * Formata timestamp Unix para data/hora legível
 */
const formatDateTime = timestamp => {
  if (!timestamp) return '';
  try {
    const date = fromUnixTime(timestamp);
    return format(date, "dd/MM/yyyy 'às' HH:mm");
  } catch {
    return '';
  }
};

/**
 * Formata apenas a data
 */
const formatDate = timestamp => {
  if (!timestamp) return '';
  try {
    const date = fromUnixTime(timestamp);
    return format(date, 'dd/MM/yyyy');
  } catch {
    return '';
  }
};

/**
 * Remove tags HTML e limpa o conteúdo
 */
const stripHtml = html => {
  if (!html) return '';
  const tmp = document.createElement('DIV');
  tmp.innerHTML = html;
  return tmp.textContent || tmp.innerText || '';
};

/**
 * Escapa HTML para prevenir XSS
 */
const escapeHtml = text => {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
};

/**
 * Converte imagem para base64 usando fetch (evita CORS)
 */
const imageToBase64 = async url => {
  try {
    // Tentar usar fetch primeiro (funciona melhor com CORS)
    const response = await fetch(url, { mode: 'cors', credentials: 'omit' });
    if (response.ok) {
      const blob = await response.blob();
      return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onloadend = () => resolve(reader.result);
        reader.onerror = reject;
        reader.readAsDataURL(blob);
      });
    }
    throw new Error('Failed to fetch image');
  } catch (error) {
    // Se fetch falhar, tentar com Image (pode falhar com CORS, mas vamos tentar)
    return new Promise((resolve, reject) => {
      const img = new Image();
      img.crossOrigin = 'anonymous';
      const timeout = setTimeout(() => {
        reject(new Error('Image load timeout'));
      }, 5000);
      img.onload = () => {
        clearTimeout(timeout);
        const canvas = document.createElement('canvas');
        canvas.width = img.width;
        canvas.height = img.height;
        const ctx = canvas.getContext('2d');
        ctx.drawImage(img, 0, 0);
        try {
          const dataURL = canvas.toDataURL('image/png');
          resolve(dataURL);
        } catch (err) {
          reject(err);
        }
      };
      img.onerror = () => {
        clearTimeout(timeout);
        reject(error);
      };
      img.src = url;
    });
  }
};

/**
 * Carrega logo e converte para base64
 */
const loadLogoBase64 = async () => {
  try {
    // Usar o domínio atual da aplicação para evitar CORS
    const currentOrigin = window.location.origin;
    const logoPath = `${currentOrigin}/brand-assets/logo.svg`;
    return await imageToBase64(logoPath);
  } catch (error) {
    // eslint-disable-next-line no-console
    console.warn('Não foi possível carregar logo:', error);
    return null;
  }
};

/**
 * Carrega background image e converte para base64
 */
const loadBackgroundBase64 = async () => {
  try {
    // Usar o domínio atual da aplicação para evitar CORS
    const currentOrigin = window.location.origin;
    const bgPath = `${currentOrigin}/assets/images/chat-spx-background-light.png`;
    return await imageToBase64(bgPath);
  } catch (error) {
    // eslint-disable-next-line no-console
    console.warn('Não foi possível carregar background:', error);
    return null;
  }
};

/**
 * Busca todas as mensagens de uma conversa
 */
const fetchAllMessages = async (conversationId, onProgress) => {
  try {
    const response = await MessageAPI.getAllMessages(conversationId, {
      onProgress,
      maxMessages: 10000,
      maxIterations: 500,
      requestTimeout: 30000,
      totalTimeout: 300000,
    });
    return response.data.payload || [];
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error(
      `Erro ao buscar mensagens da conversa ${conversationId}:`,
      error
    );
    return [];
  }
};

/**
 * Gera HTML de uma mensagem
 */
const generateMessageHTML = message => {
  const messageType = message.message_type ?? message.messageType ?? 0;
  const isPrivate = message.private === true;
  const isIncoming = messageType === MESSAGE_TYPE.INCOMING;
  const isOutgoing = messageType === MESSAGE_TYPE.OUTGOING;
  const isActivity = messageType === MESSAGE_TYPE.ACTIVITY;

  const senderName = message.sender?.name || message.sender?.email || 'Sistema';
  const messageDate = formatDateTime(message.createdAt || message.created_at);
  const messageContent = stripHtml(message.content || '');

  // Determinar classe CSS baseado no tipo
  let messageClass = 'message';
  if (isOutgoing) {
    messageClass += ' message--outgoing';
  } else if (isIncoming) {
    messageClass += ' message--incoming';
  } else if (isActivity) {
    messageClass += ' message--activity';
  }
  if (isPrivate) {
    messageClass += ' message--private';
  }

  // Anexos
  let attachmentsHTML = '';
  if (message.attachments && message.attachments.length > 0) {
    attachmentsHTML = `
      <div class="message__attachments">
        ${message.attachments
          .map(
            att =>
              `<div class="message__attachment">📎 ${escapeHtml(
                att.name || att.file_name || 'Anexo'
              )}</div>`
          )
          .join('')}
      </div>
    `;
  }

  return `
    <div class="${messageClass}">
      <div class="message__header">
        <span class="message__sender">${escapeHtml(senderName)}</span>
        <span class="message__date">${escapeHtml(messageDate)}</span>
      </div>
      ${messageContent ? `<div class="message__content">${escapeHtml(messageContent)}</div>` : ''}
      ${attachmentsHTML}
    </div>
  `;
};

/**
 * Gera HTML de uma conversa
 */
const generateConversationHTML = (conversation, messages, inbox, labels) => {
  const conversationInfo = [];
  if (conversation.createdAt || conversation.timestamp) {
    conversationInfo.push(
      `<div class="conversation__info-item"><strong>Data de criação:</strong> ${formatDate(conversation.createdAt || conversation.timestamp)}</div>`
    );
  }
  if (inbox?.name) {
    conversationInfo.push(
      `<div class="conversation__info-item"><strong>Inbox:</strong> ${escapeHtml(inbox.name)}</div>`
    );
  }
  if (conversation.status) {
    conversationInfo.push(
      `<div class="conversation__info-item"><strong>Status:</strong> ${escapeHtml(conversation.status)}</div>`
    );
  }
  if (labels && labels.length > 0) {
    const labelNames = labels.map(l => l.title || l.name).join(', ');
    conversationInfo.push(
      `<div class="conversation__info-item"><strong>Labels:</strong> ${escapeHtml(labelNames)}</div>`
    );
  }

  // Remover mensagens duplicadas baseado no ID antes de ordenar
  const uniqueMessages = messages.filter(
    (msg, index, self) => index === self.findIndex(m => m.id === msg.id)
  );

  const sortedMessages = sortMessagesChronologically(uniqueMessages);

  // Limitar número de mensagens exibidas se exceder o limite
  const maxMessagesToDisplay = MAX_MESSAGES_PER_CONVERSATION;
  const messagesToDisplay = sortedMessages.slice(0, maxMessagesToDisplay);
  const hasMoreMessages = sortedMessages.length > maxMessagesToDisplay;
  const hiddenMessagesCount = sortedMessages.length - maxMessagesToDisplay;

  const messagesHTML = messagesToDisplay
    .map(msg => generateMessageHTML(msg))
    .join('');

  // Adicionar mensagem indicando se há mais mensagens não exibidas
  let moreMessagesNotice = '';
  if (hasMoreMessages) {
    moreMessagesNotice = `
      <div class="conversation__limit-notice">
        <strong>Nota:</strong> Esta conversa possui ${sortedMessages.length} mensagens no total. 
        Por limitações técnicas, apenas as primeiras ${maxMessagesToDisplay} mensagens estão sendo exibidas neste PDF. 
        (${hiddenMessagesCount} mensagens não exibidas)
      </div>
    `;
  }

  return `
    <div class="conversation">
      <h2 class="conversation__title">Conversa #${conversation.id}</h2>
      ${conversationInfo.length > 0 ? `<div class="conversation__info">${conversationInfo.join('')}</div>` : ''}
      ${messages.length > 0 ? `<div class="conversation__messages">${messagesHTML}</div>${moreMessagesNotice}` : '<p class="conversation__empty">Nenhuma mensagem encontrada.</p>'}
    </div>
  `;
};

/**
 * Gera o template HTML completo
 */
const generateHTMLTemplate = ({
  contact,
  conversations,
  conversationsWithMessages,
  logoBase64,
  backgroundBase64,
  user,
  account,
}) => {
  // Validar que há conversas com mensagens
  if (!conversationsWithMessages || conversationsWithMessages.length === 0) {
    throw new Error('Nenhuma conversa com mensagens para gerar PDF.');
  }

  const conversationsHTML = conversationsWithMessages
    .map(({ conversation, messages, inbox, labels }) =>
      generateConversationHTML(conversation, messages, inbox, labels)
    )
    .join('');

  // Validar que o HTML foi gerado
  if (!conversationsHTML || conversationsHTML.trim().length === 0) {
    throw new Error(
      'Erro ao gerar HTML das conversas. Nenhum conteúdo foi gerado.'
    );
  }

  const logoImg = logoBase64
    ? `<img src="${logoBase64}" alt="Chatwoot" class="header__logo" />`
    : '';

  const backgroundStyle = backgroundBase64
    ? `background-image: url('${backgroundBase64}');`
    : '';

  return `
<div class="pdf-wrapper">
  <style>
    .pdf-wrapper {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
      font-size: 14px;
      line-height: 1.6;
      color: #373435;
      background-color: #ffffff;
      ${backgroundStyle ? `${backgroundStyle} background-repeat: repeat; background-size: 400px; background-position: 0 0;` : ''}
      margin: 0;
      padding: 0;
      width: 100%;
      max-width: 100%;
      position: relative;
      min-height: 100vh;
      display: flex;
      justify-content: center;
    }

    .pdf-wrapper::before {
      content: '';
      position: absolute;
      top: 0;
      left: 0;
      right: 0;
      bottom: 0;
      ${backgroundStyle}
      background-repeat: repeat;
      background-size: 400px;
      background-position: 0 0;
      opacity: 0.05;
      z-index: 0;
      pointer-events: none;
    }

    .pdf-wrapper * {
      box-sizing: border-box;
    }

    main {
      width: 100%;
    }

    .pdf-container {
      position: relative;
      width: 210mm;
      max-width: 100%;
      margin: 0 auto;
      padding: 20mm;
      background-color: #ffffff;
      box-sizing: border-box;
      min-height: 100%;
    }

    .pdf-container::before {
      content: '';
      position: absolute;
      top: 0;
      left: 0;
      right: 0;
      bottom: 0;
      min-height: 100%;
      ${backgroundStyle}
      background-repeat: repeat;
      background-size: 400px;
      background-position: 0 0;
      opacity: 0.05;
      z-index: 0;
      pointer-events: none;
    }

    .pdf-container > * {
      position: relative;
      z-index: 1;
    }

    .header {
      margin-bottom: 30px;
      padding-bottom: 20px;
      border-bottom: 2px solid #e0e0e0;
      text-align: center;
    }

    .header__logo {
      height: 50px;
      margin-bottom: 20px;
      display: block;
      margin-left: auto;
      margin-right: auto;
    }

    .header__title {
      font-size: 26px;
      font-weight: 700;
      color: #373435;
      margin-bottom: 12px;
      line-height: 1.2;
    }

    .header__subtitle {
      font-size: 18px;
      color: #666;
      margin-bottom: 8px;
      font-weight: 500;
    }

    .header__company {
      font-size: 14px;
      color: #2dc46f;
      margin-bottom: 6px;
      font-weight: 600;
    }

    .header__user {
      font-size: 13px;
      color: #666;
      margin-bottom: 10px;
    }

    .header__meta {
      font-size: 12px;
      color: #999;
      display: flex;
      justify-content: space-between;
      margin-top: 15px;
      flex-wrap: wrap;
      gap: 10px;
    }

    .conversation {
      margin-bottom: 50px;
      page-break-inside: avoid;
      break-inside: avoid-page;
      orphans: 3;
      widows: 3;
    }

    .conversation__title {
      font-size: 20px;
      font-weight: 700;
      color: #2dc46f;
      margin-bottom: 18px;
      padding-bottom: 8px;
      border-bottom: 1px solid #e0e0e0;
    }

    .conversation__info {
      background: #f8f9fa;
      padding: 14px 16px;
      border-radius: 8px;
      margin-bottom: 24px;
      font-size: 13px;
      border-left: 4px solid #2dc46f;
    }

    .conversation__info-item {
      margin-bottom: 6px;
    }

    .conversation__info-item:last-child {
      margin-bottom: 0;
    }

    .conversation__info-item strong {
      color: #666;
      margin-right: 8px;
    }

    .conversation__messages {
      display: flex;
      flex-direction: column;
      gap: 12px;
      width: 100%;
      max-width: 100%;
      align-items: flex-start;
    }

    .conversation__empty {
      text-align: center;
      color: #999;
      font-style: italic;
      padding: 30px 20px;
      background: #f8f9fa;
      border-radius: 8px;
      border: 1px dashed #ddd;
    }

    .conversation__limit-notice {
      background: #fff3cd;
      border: 1px solid #ffc107;
      border-radius: 8px;
      padding: 12px 16px;
      margin-top: 16px;
      margin-bottom: 16px;
      font-size: 12px;
      color: #856404;
      text-align: center;
    }

    .message {
      max-width: 85%;
      padding: 14px 18px;
      padding-bottom: 16px;
      border-radius: 12px;
      margin-bottom: 8px;
      word-wrap: break-word;
      word-break: break-word;
      overflow-wrap: break-word;
      box-shadow: 0 1px 2px rgba(0, 0, 0, 0.1);
      box-sizing: border-box;
      overflow: visible;
      min-width: 150px;
      min-height: auto;
      page-break-inside: auto;
      break-inside: auto;
      orphans: 2;
      widows: 2;
    }

    .message--incoming {
      align-self: flex-start;
      background: #e8f4f8;
      border: 1px solid #2dc46f;
      color: #000;
      margin-right: auto;
      margin-left: 0;
    }

    .message--outgoing {
      align-self: flex-end;
      background: #2dc46f;
      border: 1px solid #2dc46f;
      color: #fff;
      margin-left: auto;
      margin-right: 0;
    }

    .message--activity {
      align-self: center;
      max-width: 90%;
      background: #fff9e6;
      border: 1px solid #ffd700;
      color: #666;
      margin-left: auto;
      margin-right: auto;
      text-align: center;
    }

    .message--private {
      background: #f5f5f5;
      border-color: #ccc;
      color: #333;
    }

    .message--private .message__content {
      color: #333;
    }

    .message__header {
      display: flex;
      justify-content: space-between;
      align-items: flex-start;
      margin-bottom: 8px;
      font-size: 12px;
      gap: 12px;
      flex-wrap: wrap;
    }

    .message__sender {
      font-weight: 600;
      flex: 1 1 auto;
      min-width: 0;
      overflow: visible;
      word-wrap: break-word;
      word-break: break-word;
      overflow-wrap: break-word;
      white-space: normal;
    }

    .message__date {
      opacity: 0.7;
      font-size: 11px;
      flex: 0 0 auto;
      white-space: nowrap;
      align-self: flex-start;
    }

    .message__content {
      line-height: 1.7;
      white-space: pre-wrap;
      word-wrap: break-word;
      word-break: break-word;
      overflow-wrap: break-word;
      max-width: 100%;
      overflow: visible;
      padding-bottom: 2px;
      page-break-inside: auto;
      break-inside: auto;
      orphans: 2;
      widows: 2;
    }

    .message--outgoing .message__content {
      color: #ffffff;
    }

    .message--incoming .message__content {
      color: #000000;
    }

    .message--activity .message__content {
      color: #666666;
    }

    .message__attachments {
      margin-top: 10px;
      padding-top: 10px;
      border-top: 1px solid rgba(0, 0, 0, 0.1);
    }

    .message--outgoing .message__attachments {
      border-top-color: rgba(255, 255, 255, 0.3);
    }

    .message__attachment {
      font-size: 12px;
      margin-top: 6px;
      opacity: 0.85;
      padding: 4px 0;
    }

    /* Melhorias de quebra de página */
    .conversation__title {
      page-break-after: avoid;
      break-after: avoid;
    }

    .conversation__info {
      page-break-inside: avoid;
      break-inside: avoid-page;
    }

    .message__header {
      page-break-after: avoid;
      break-after: avoid;
    }

    .pdf-footer {
      position: fixed;
      bottom: 0;
      left: 0;
      right: 0;
      background: #f8f9fa;
      border-top: 2px solid #2dc46f;
      padding: 8px 20px;
      font-size: 10px;
      color: #666;
      display: flex;
      justify-content: space-between;
      align-items: center;
      z-index: 1000;
    }

    .pdf-footer__left {
      display: flex;
      flex-direction: column;
      gap: 2px;
    }

    .pdf-footer__right {
      text-align: right;
      font-size: 9px;
      opacity: 0.8;
    }

    @media print {
      .pdf-container::before {
        opacity: 0.03;
      }
    }

    @page {
      margin-bottom: 20mm;
    }
  </style>
  <div class="pdf-container">
    <header class="header">
      ${logoImg}
      <h1 class="header__title">Histórico de Conversas</h1>
      <div class="header__subtitle">${escapeHtml(contact?.name || 'Contato')}</div>
      ${account?.name ? `<div class="header__company">Empresa: ${escapeHtml(account.name)}</div>` : ''}
      ${user?.name ? `<div class="header__user">Gerado por: ${escapeHtml(user.name)}</div>` : ''}
      <div class="header__meta">
        <span>Data de geração: ${formatDate(Math.floor(Date.now() / 1000))}</span>
        <span>Total de conversas: ${conversations.length}</span>
      </div>
    </header>
    <main style="position: relative; z-index: 1;">
      ${conversationsHTML}
    </main>
    <footer class="pdf-footer">
      <div class="pdf-footer__left">
        ${account?.name ? `<div><strong>Empresa:</strong> ${escapeHtml(account.name)}</div>` : ''}
        ${user?.name ? `<div><strong>Gerado por:</strong> ${escapeHtml(user.name)}</div>` : ''}
      </div>
      <div class="pdf-footer__right">
        <div>Histórico de Conversas - CHAT - SPX</div>
        <div>${formatDate(Math.floor(Date.now() / 1000))}</div>
      </div>
    </footer>
  </div>
</div>
  `;
};

/**
 * Gera o PDF com as conversas selecionadas
 */
/**
 * Filtra mensagens por período e notas privadas
 */
export const filterMessages = (
  messages,
  { dateFrom, dateTo, includePrivateNotes = true } = {}
) => {
  return messages.filter(msg => {
    const timestamp = msg.createdAt || msg.created_at || 0;
    if (dateFrom && timestamp < dateFrom) return false;
    if (dateTo && timestamp > dateTo) return false;
    if (!includePrivateNotes && msg.private === true) return false;
    return true;
  });
};

export const generateConversationsPDF = async ({
  conversations,
  contact,
  inboxesById,
  labelsById,
  accountLabels,
  user,
  account,
  onProgress,
  dateFrom,
  dateTo,
  includePrivateNotes = true,
}) => {
  let offscreenContainer;
  let hiddenNinjaKeys = [];
  try {
    // Ordenar conversas cronologicamente (mais antiga primeiro)
    const sortedConversations = sortConversationsChronologically(conversations);

    // Validar limites antes de iniciar a geração
    if (sortedConversations.length > MAX_CONVERSATIONS) {
      const errorMessage = `Limite de conversas excedido. Máximo permitido: ${MAX_CONVERSATIONS}. Você selecionou: ${sortedConversations.length}. Por favor, selecione menos conversas ou divida a exportação em múltiplos PDFs.`;
      // eslint-disable-next-line no-console
      console.error(errorMessage);
      throw new Error(errorMessage);
    }

    // Buscar mensagens de todas as conversas (sequencialmente para melhor controle de erros)
    const conversationsWithMessages = [];
    const errors = [];
    let totalMessagesCount = 0;

    for (let i = 0; i < sortedConversations.length; i++) {
      const conversation = sortedConversations[i];

      if (onProgress) {
        onProgress({
          current: i + 1,
          total: sortedConversations.length,
          conversationId: conversation.id,
          status: 'fetching',
        });
      }

      try {
        let messages = await fetchAllMessages(conversation.id, total => {
          if (onProgress) {
            onProgress({
              current: i + 1,
              total: sortedConversations.length,
              conversationId: conversation.id,
              messagesLoaded: total,
              status: 'fetching',
            });
          }
        });

        // Aplicar filtros de período e notas privadas
        messages = filterMessages(messages, {
          dateFrom,
          dateTo,
          includePrivateNotes,
        });

        // Validar limite de mensagens por conversa
        if (messages.length > MAX_MESSAGES_PER_CONVERSATION) {
          const errorMessage = `Conversa #${conversation.id} excede o limite de mensagens. Máximo permitido: ${MAX_MESSAGES_PER_CONVERSATION}. Encontradas: ${messages.length}. Por favor, selecione conversas menores ou divida a exportação.`;
          // eslint-disable-next-line no-console
          console.warn(errorMessage);
          errors.push({
            conversationId: conversation.id,
            error: new Error(errorMessage),
          });
          // Limitar mensagens para esta conversa
          messages.splice(MAX_MESSAGES_PER_CONVERSATION);
        }

        // Validar limite total de mensagens
        totalMessagesCount += messages.length;
        if (totalMessagesCount > MAX_TOTAL_MESSAGES) {
          const errorMessage = `Limite total de mensagens excedido. Máximo permitido: ${MAX_TOTAL_MESSAGES}. Total encontrado: ${totalMessagesCount}. Por favor, selecione menos conversas ou divida a exportação.`;
          // eslint-disable-next-line no-console
          console.warn(errorMessage);
          // Parar de processar mais conversas
          if (onProgress) {
            onProgress({
              current: i + 1,
              total: sortedConversations.length,
              conversationId: conversation.id,
              status: 'error',
              error: errorMessage,
            });
          }
          break;
        }

        const inbox = inboxesById?.[conversation.inboxId] || {};
        const conversationLabels =
          conversation.labels?.map(labelId => {
            const label =
              accountLabels?.find(l => l.id === labelId) ||
              labelsById?.[labelId];
            return label;
          }) || [];

        conversationsWithMessages.push({
          conversation,
          messages,
          inbox,
          labels: conversationLabels.filter(Boolean),
        });

        if (onProgress) {
          onProgress({
            current: i + 1,
            total: sortedConversations.length,
            conversationId: conversation.id,
            status: 'fetched',
          });
        }
      } catch (error) {
        // eslint-disable-next-line no-console
        console.error(`Erro ao processar conversa ${conversation.id}:`, error);
        errors.push({ conversationId: conversation.id, error });
        // Continuar com outras conversas mesmo se uma falhar
        if (onProgress) {
          onProgress({
            current: i + 1,
            total: sortedConversations.length,
            conversationId: conversation.id,
            status: 'error',
            error: error.message,
          });
        }
      }
    }

    // Validar se há conversas com mensagens para exportar
    if (conversationsWithMessages.length === 0) {
      const errorMessage =
        'Nenhuma conversa com mensagens encontrada para exportar.';
      // eslint-disable-next-line no-console
      console.error(errorMessage);
      throw new Error(errorMessage);
    }

    // Logar informações de debug
    const totalMessages = conversationsWithMessages.reduce(
      (sum, conv) => sum + (conv.messages?.length || 0),
      0
    );
    // eslint-disable-next-line no-console
    console.log('Iniciando geração de PDF:', {
      conversas: conversationsWithMessages.length,
      totalMensagens: totalMessages,
      contato: contact?.name || 'N/A',
    });

    // Carregar imagens em base64 para evitar problemas de CORS
    // Usar Promise.allSettled para continuar mesmo se algumas falharem
    const [logoResult, backgroundResult] = await Promise.allSettled([
      loadLogoBase64(),
      loadBackgroundBase64(),
    ]);
    const logoBase64 =
      logoResult.status === 'fulfilled' ? logoResult.value : null;
    const backgroundBase64 =
      backgroundResult.status === 'fulfilled' ? backgroundResult.value : null;

    // Gerar HTML
    const htmlContent = generateHTMLTemplate({
      contact,
      conversations: sortedConversations,
      conversationsWithMessages,
      logoBase64,
      backgroundBase64,
      user,
      account,
    });

    // Remover elementos ninja-keys do DOM antes de gerar PDF (evita erro de ShadowRoot)
    const ninjaKeysElements = document.querySelectorAll('ninja-keys');
    hiddenNinjaKeys = [];
    ninjaKeysElements.forEach(el => {
      if (el.style.display !== 'none') {
        hiddenNinjaKeys.push(el);
        el.style.display = 'none';
      }
    });

    // Criar elemento temporário e renderizar HTML
    const tempDiv = document.createElement('div');
    tempDiv.innerHTML = htmlContent;

    // Estilos para renderização correta - elemento renderizado mas fora da viewport
    // Usar position absolute com coordenadas negativas para não aparecer na tela
    tempDiv.style.position = 'absolute';
    tempDiv.style.left = '0';
    tempDiv.style.top = '0';
    tempDiv.style.width = '794px'; // 210mm em pixels (A4)
    tempDiv.style.backgroundColor = '#ffffff';
    tempDiv.style.visibility = 'visible';
    tempDiv.style.opacity = '1';
    tempDiv.style.zIndex = '-1';
    tempDiv.style.overflow = 'visible';
    tempDiv.style.display = 'block';
    tempDiv.style.pointerEvents = 'none';
    tempDiv.style.height = 'auto';
    tempDiv.style.maxHeight = 'none';

    // Criar um container offscreen para não aparecer na tela
    const offscreenContainer = document.createElement('div');
    offscreenContainer.style.position = 'absolute';
    offscreenContainer.style.left = '-9999px';
    offscreenContainer.style.top = '0';
    offscreenContainer.style.width = '794px';
    offscreenContainer.style.height = 'auto';
    offscreenContainer.style.overflow = 'visible';
    offscreenContainer.appendChild(tempDiv);

    // Adicionar container offscreen ao body
    document.body.appendChild(offscreenContainer);

    // Forçar layout recalculation
    // eslint-disable-next-line no-unused-expressions
    tempDiv.offsetHeight;

    // Aguardar um frame para garantir renderização
    await new Promise(resolve => {
      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          resolve();
        });
      });
    });

    // Aguardar imagens carregarem
    const images = tempDiv.querySelectorAll('img');
    if (images.length > 0) {
      await Promise.race([
        Promise.all(
          Array.from(images).map(
            img =>
              new Promise(resolve => {
                if (img.complete && img.naturalHeight !== 0) {
                  resolve();
                  return;
                }
                img.onload = () => resolve();
                img.onerror = () => resolve();
              })
          )
        ),
        new Promise(resolve => {
          setTimeout(() => resolve(), 2000);
        }),
      ]);
    }

    // Verificar se há conteúdo e altura
    const textContent = tempDiv.textContent || tempDiv.innerText || '';
    const elementHeight = tempDiv.offsetHeight || tempDiv.scrollHeight;

    if (textContent.trim().length === 0 || elementHeight === 0) {
      // eslint-disable-next-line no-console
      console.error('PDF vazio - sem conteúdo detectado ou altura zero', {
        textLength: textContent.trim().length,
        height: elementHeight,
        scrollHeight: tempDiv.scrollHeight,
        offsetHeight: tempDiv.offsetHeight,
      });
      if (offscreenContainer.parentNode) {
        document.body.removeChild(offscreenContainer);
      }
      throw new Error(
        'Nenhum conteúdo encontrado para gerar PDF ou elemento com altura zero'
      );
    }

    // Determinar scale baseado no tamanho do conteúdo (reduzir para conteúdo grande)
    const messagesCount = tempDiv.querySelectorAll('.message').length;
    const dynamicScale = messagesCount > 1000 ? 1 : 2; // Reduzir scale para conteúdo muito grande

    // Configurações otimizadas do PDF
    const opt = {
      margin: [10, 10, 20, 10],
      filename: `historico_conversas_${(contact?.name || 'contato').replace(/[^a-z0-9]/gi, '_')}_${formatDate(Math.floor(Date.now() / 1000)).replace(/\//g, '_')}.pdf`,
      image: { type: 'jpeg', quality: 0.95 },
      html2canvas: {
        scale: dynamicScale,
        useCORS: true,
        allowTaint: true,
        logging: false,
        backgroundColor: '#ffffff',
        removeContainer: false,
        width: tempDiv.scrollWidth || 794,
        height: tempDiv.scrollHeight || 1123,
        windowWidth: tempDiv.scrollWidth || 794,
        windowHeight: tempDiv.scrollHeight || 1123,
        x: 0,
        y: 0,
        scrollX: 0,
        scrollY: 0,
        ignoreElements: element => {
          // Ignorar elementos ninja-keys e outros elementos problemáticos
          return (
            element.tagName === 'NINJA-KEYS' ||
            element.classList?.contains('ninja-keys') ||
            element.closest('ninja-keys') !== null
          );
        },
      },
      jsPDF: {
        unit: 'mm',
        format: 'a4',
        orientation: 'portrait',
      },
      pagebreak: { mode: ['avoid-all', 'css', 'legacy'] },
    };

    // Gerar PDF
    await html2pdf().set(opt).from(tempDiv).save();

    // Remover container offscreen
    if (offscreenContainer.parentNode) {
      document.body.removeChild(offscreenContainer);
    }

    // Restaurar elementos ninja-keys
    hiddenNinjaKeys.forEach(el => {
      el.style.display = '';
    });
    // Retornar relatório de erros se houver
    if (errors.length > 0 && onProgress) {
      onProgress({ errors });
    }
  } catch (error) {
    // Remover container offscreen em caso de erro
    if (
      typeof offscreenContainer !== 'undefined' &&
      offscreenContainer.parentNode
    ) {
      document.body.removeChild(offscreenContainer);
    }
    // Restaurar elementos ninja-keys em caso de erro
    if (typeof hiddenNinjaKeys !== 'undefined') {
      hiddenNinjaKeys.forEach(el => {
        el.style.display = '';
      });
    }
    // eslint-disable-next-line no-console
    console.error('Erro ao gerar PDF:', error);
    throw error;
  }
};
