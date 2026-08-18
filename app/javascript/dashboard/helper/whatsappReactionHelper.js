/**
 * Reações de WhatsApp que chegam como MENSAGEM de texto no fio.
 *
 * A app `chatwoot` que roda dentro da WAHA não tem para onde mandar uma reação: o
 * webhook dela só sabe criar mensagem. Então ela transforma a reação em texto e a
 * empurra para a conversa:
 *
 *   grupo (legado): "👥 *Rogerio José Da Silva (229480102662169@lid)*\n\n*Reagiu com* 👍"
 *   grupo (novo):   "*Reagiu com* 👍"  + content_attributes.group_sender
 *   1:1:            "*Reagiu com* 🚀"
 *
 * Em todos os casos ela preenche `content_attributes.in_reply_to` com o id da mensagem
 * reagida — é esse campo que permite ancorar o chip na bolha certa, sem adivinhação.
 *
 * O resultado no fio hoje é uma bolha de texto por reação. Em grupo, uma por
 * participante: dez pessoas reagindo a um aviso viram dez bolhas.
 *
 * Este módulo é PURO (sem store, sem DOM, sem i18n) e faz duas coisas:
 *   1. reconhecer que uma mensagem é, na verdade, uma reação;
 *   2. agregá-las por mensagem-alvo, no formato de chip que o WhatsApp usa.
 *
 * DÉBITO CONHECIDO: a correção de verdade é na ingestão — gravar a reação em
 * `message_reactions` (a tabela já existe, ver `app/models/message_reaction.rb`) em vez
 * de criar uma mensagem. Enquanto isso não vier, este saneamento é o que impede o fio de
 * ser tomado por reações. Quando vier, este módulo sai inteiro.
 */
import {
  parseLegacyGroupContent,
  participantLabel,
  authorIdentityKey,
} from 'dashboard/helper/whatsappGroupHelper';

/**
 * O corpo INTEIRO precisa ser o marcador seguido do emoji — âncoras `^`/`$` não são
 * cosméticas aqui: existem mensagens de notificação que CITAM uma reação no meio do
 * texto ("💬 **Mensagem:** \"**Reagiu com** 👍\"") e essas continuam sendo mensagens
 * de verdade. O marcador vem traduzido pela app da WAHA — daí as duas variantes.
 */
const REACTION_BODY = /^\*(?:Reagiu com|Reacted with)\*\s+(\S{1,24})$/u;

const EMPTY_INDEX = Object.freeze({
  reactionsByMessageId: new Map(),
  standaloneReactions: new Map(),
  hiddenMessageIds: new Set(),
});

/**
 * Reconhece uma mensagem-reação e devolve o que ela carrega de útil.
 *
 * @param {Object} message - Mensagem JÁ camelizada (contrato do MessageList)
 * @returns {{emoji: String, targetId: Number|null, authorLabel: String|null,
 *            authorKey: String}|null} `null` quando não é reação
 */
export const parseWhatsAppReaction = (message = {}) => {
  const content = message?.content;
  if (!content || typeof content !== 'string') return null;
  // Guard barato: sem o asterisco do marcador não há o que testar.
  if (!content.includes('*')) return null;
  // Reação não tem anexo; se tem, é mensagem de verdade que por acaso casa o texto.
  if (Array.isArray(message.attachments) && message.attachments.length) {
    return null;
  }

  const { content: body, sender: legacySender } =
    parseLegacyGroupContent(content);
  const match = body.trim().match(REACTION_BODY);
  if (!match) return null;

  const attrs = message.contentAttributes || {};
  const groupSender = attrs.groupSender ?? attrs.group_sender ?? null;
  const targetId = attrs.inReplyTo ?? attrs.in_reply_to ?? null;

  // Autor estruturado (mensagem nova) tem precedência sobre o nome extraído do texto.
  const author = groupSender || legacySender;
  const { label } = author ? participantLabel(author) : { label: null };

  return {
    emoji: match[1],
    targetId: targetId ?? null,
    authorLabel: label,
    // Identidade para deduplicar: no WhatsApp cada pessoa tem UMA reação por mensagem;
    // trocar de emoji gera uma segunda mensagem, e sem chave a contagem inflaria.
    // Sem autor conhecido cai no id da mensagem — único, ou seja, nunca deduplica.
    authorKey:
      (author && authorIdentityKey(author)) || label || `message-${message.id}`,
  };
};

/**
 * Agrega as reações de um autor por emoji, preservando a ordem de chegada.
 * @param {Map<String, {emoji: String, authorLabel: String|null}>} byAuthor
 * @returns {Array<{emoji: String, count: Number, authors: String[]}>}
 */
const toChips = byAuthor => {
  const chips = new Map();

  byAuthor.forEach(({ emoji, authorLabel }) => {
    if (!chips.has(emoji)) chips.set(emoji, { emoji, count: 0, authors: [] });
    const chip = chips.get(emoji);
    chip.count += 1;
    if (authorLabel) chip.authors.push(authorLabel);
  });

  return [...chips.values()];
};

/**
 * Varre a lista carregada e devolve o índice de reações do fio.
 *
 * A reação só sai do fio quando há onde colocá-la: alvo conhecido E presente na lista
 * carregada. Se o alvo ficou numa página anterior (ou a WAHA não mandou `in_reply_to`),
 * a reação continua visível — como chip solto, não como bolha de texto. Sumir com ela
 * seria perder informação que o agente tem hoje.
 *
 * @param {Array<Object>} messages - Mensagens camelizadas, em ordem cronológica
 * @returns {{reactionsByMessageId: Map<Number, Array>, standaloneReactions: Map<Number, Array>,
 *            hiddenMessageIds: Set<Number>}}
 */
export const collectWhatsAppReactions = (messages = []) => {
  const parsed = [];

  messages.forEach(message => {
    const reaction = parseWhatsAppReaction(message);
    if (reaction) parsed.push({ message, reaction });
  });

  if (!parsed.length) return EMPTY_INDEX;

  const reactionIds = new Set(parsed.map(({ message }) => message.id));
  const knownIds = new Set(messages.map(message => message?.id));

  const byTarget = new Map();
  const standaloneReactions = new Map();
  const hiddenMessageIds = new Set();

  parsed.forEach(({ message, reaction }) => {
    const { targetId, emoji, authorLabel, authorKey } = reaction;
    // Reação ancorada em outra reação seria um chip pendurado em nada: trata como solta.
    const canAnchor =
      targetId && knownIds.has(targetId) && !reactionIds.has(targetId);

    if (!canAnchor) {
      standaloneReactions.set(message.id, [
        { emoji, count: 1, authors: authorLabel ? [authorLabel] : [] },
      ]);
      return;
    }

    if (!byTarget.has(targetId)) byTarget.set(targetId, new Map());
    // `set` sobrescreve: a última reação da pessoa é a que vale.
    byTarget.get(targetId).set(authorKey, { emoji, authorLabel });
    hiddenMessageIds.add(message.id);
  });

  const reactionsByMessageId = new Map();
  byTarget.forEach((byAuthor, targetId) => {
    reactionsByMessageId.set(targetId, toChips(byAuthor));
  });

  return { reactionsByMessageId, standaloneReactions, hiddenMessageIds };
};
