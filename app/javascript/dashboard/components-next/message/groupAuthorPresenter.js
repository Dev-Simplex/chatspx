/**
 * Monta o que a bolha precisa para mostrar QUEM falou num grupo de WhatsApp.
 *
 * Função pura: recebe o `group_sender` gravado na ingestão e os rótulos já traduzidos,
 * devolve rótulo, iniciais, cores (light/dark) e tooltip. Fica fora do componente para
 * a bolha e o preview de resposta usarem exatamente a mesma identidade visual.
 *
 * O identificador técnico (LID) nunca é devolvido para exibição: ele só alimenta a cor
 * determinística, dentro de `whatsappGroupHelper`.
 */
import {
  authorColor,
  authorInitials,
  participantLabel,
  formatPhone,
  UNKNOWN_AUTHOR_COLOR,
} from 'dashboard/helper/whatsappGroupHelper';

/**
 * Sem nome, o avatar mostra o DDD — é o que identifica a pessoa de relance numa lista
 * de números. Jamais o identificador técnico.
 * @param {String} phone - Telefone em E.164 sem "+"
 * @returns {String}
 */
export const phoneInitials = phone => {
  const digits = String(phone ?? '').replace(/\D/g, '');
  if (!digits) return '#';
  if (digits.startsWith('55') && digits.length >= 12) return digits.slice(2, 4);
  return digits.slice(-2);
};

/**
 * @typedef {Object} GroupAuthor
 * @property {String} label - Nome, telefone formatado ou "não identificado"
 * @property {Boolean} isUnknown - Quando não há nome nem telefone
 * @property {String} initials - Iniciais do avatar ("RS", "66" ou "?")
 * @property {String} color - Cor determinística no tema claro
 * @property {String} colorDark - Cor determinística no tema escuro
 * @property {String} tooltip - Nome · telefone (ou a dica de não identificado)
 * @property {String} ariaLabel - Rótulo acessível do avatar
 */

/**
 * Rótulos do autor, resolvidos num lugar só para a bolha e o preview de resposta
 * falarem igual.
 *
 * As chaves de grupo são criadas junto com o painel de integrantes; enquanto não
 * existirem, `t()` devolve a própria chave — o fallback em pt-BR evita que ela apareça
 * na tela.
 *
 * @param {Function} t - `t` do vue-i18n
 * @returns {{unknownLabel: String, unknownHint: String, sentBy: String}}
 */
export const groupAuthorLabels = t => {
  const unknownLabel = t('GROUP_INFO.UNKNOWN_PARTICIPANT');
  const unknownHint = t('GROUP_INFO.UNKNOWN_PARTICIPANT_HINT');

  return {
    unknownLabel:
      unknownLabel === 'GROUP_INFO.UNKNOWN_PARTICIPANT'
        ? 'Participante não identificado'
        : unknownLabel,
    unknownHint:
      unknownHint === 'GROUP_INFO.UNKNOWN_PARTICIPANT_HINT'
        ? 'O WhatsApp não informou quem enviou esta mensagem. Sincronize os integrantes do grupo para tentar identificar.'
        : unknownHint,
    sentBy: t('CONVERSATION.SENT_BY'),
  };
};

/**
 * @param {Object|null} sender - `content_attributes.group_sender` ({ name, lid, phone })
 * @param {Object} labels - Rótulos já traduzidos pelo chamador
 * @param {String} labels.unknownLabel - "Participante não identificado"
 * @param {String} labels.unknownHint - Dica exibida no tooltip de não identificado
 * @param {String} labels.sentBy - Prefixo do rótulo acessível ("Enviado por")
 * @returns {GroupAuthor|null} `null` quando não há autor estruturado (mensagem legada)
 */
export const buildGroupAuthor = (sender, labels = {}) => {
  if (!sender) return null;

  const { unknownLabel = '', unknownHint = '', sentBy = '' } = labels;

  const { label, isUnknown } = participantLabel(sender);
  const name = (sender.name || '').trim();
  const phone = formatPhone(sender.phone || '');

  const displayLabel = isUnknown ? unknownLabel : label;

  return {
    label: displayLabel,
    isUnknown,
    initials: isUnknown
      ? '?'
      : authorInitials(name) || phoneInitials(sender.phone),
    // Não identificado nunca recebe cor da paleta: cinza comunica "não sei quem é"
    // sem precisar de texto extra.
    color: isUnknown ? UNKNOWN_AUTHOR_COLOR.light : authorColor(sender, false),
    colorDark: isUnknown
      ? UNKNOWN_AUTHOR_COLOR.dark
      : authorColor(sender, true),
    // O telefone aparece SÓ aqui; quando ele já é o rótulo, não se repete.
    tooltip: isUnknown
      ? unknownHint
      : [label, name && phone ? phone : ''].filter(Boolean).join(' · '),
    ariaLabel: `${sentBy} ${displayLabel}`.trim(),
  };
};

/**
 * Estilo com as duas cores do autor. As classes `dark:` do Tailwind trocam de variável
 * sozinhas — o componente não precisa saber qual tema está ativo, e a cor acompanha a
 * troca de tema sem re-render.
 * @param {GroupAuthor} author
 * @returns {Object}
 */
export const groupAuthorStyle = author => ({
  '--group-author-color': author.color,
  '--group-author-color-dark': author.colorDark,
});
