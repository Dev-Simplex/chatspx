// Helper para gerar preview legível da última mensagem em cards Kanban (P1-02).
// Mensagens não-texto retornam placeholder humanizado ("📎 Imagem", etc).
// Mensagens enviadas pelo agente recebem prefixo "Você: ".

const MESSAGE_TYPE_OUTGOING = 1;

const isOutgoing = msg =>
  Number(msg?.message_type ?? msg?.messageType ?? 0) === MESSAGE_TYPE_OUTGOING;

const firstAttachmentKind = msg => {
  const attachments = msg?.attachments || [];
  if (!Array.isArray(attachments) || attachments.length === 0) return null;
  const file_type = attachments[0]?.file_type || attachments[0]?.fileType;
  return file_type;
};

export function getMessagePreview(msg, t) {
  if (!msg)
    return {
      text: t('KANBAN.CARD.PREVIEW_EMPTY'),
      isPlaceholder: true,
      outgoing: false,
    };

  const outgoing = isOutgoing(msg);
  const attKind = firstAttachmentKind(msg);
  if (attKind) {
    const map = {
      image: 'KANBAN.CARD.PREVIEW_IMAGE',
      file: 'KANBAN.CARD.PREVIEW_FILE',
      audio: 'KANBAN.CARD.PREVIEW_AUDIO',
      video: 'KANBAN.CARD.PREVIEW_VIDEO',
      location: 'KANBAN.CARD.PREVIEW_LOCATION',
      contact: 'KANBAN.CARD.PREVIEW_CONTACT',
      sticker: 'KANBAN.CARD.PREVIEW_STICKER',
    };
    const key = map[attKind] || 'KANBAN.CARD.PREVIEW_FILE';
    return {
      text: t(key),
      isPlaceholder: true,
      outgoing,
    };
  }

  const raw =
    msg?.content ||
    msg?.processed_message_content ||
    msg?.processedMessageContent ||
    '';
  const truncated = raw.length > 60 ? `${raw.slice(0, 57)}…` : raw;
  return {
    text: truncated || t('KANBAN.CARD.PREVIEW_EMPTY'),
    isPlaceholder: !truncated,
    outgoing,
  };
}

export function useKanbanMessagePreview() {
  return { getMessagePreview };
}
