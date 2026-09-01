/**
 * Helpers de conversa de GRUPO de WhatsApp (inbox WAHA).
 *
 * Contrato compartilhado entre a bolha de mensagem, o cabeçalho da conversa e o
 * painel de integrantes. Tudo aqui é puro e testável — sem acesso a store nem a DOM.
 *
 * O identificador técnico do participante (LID) NUNCA deve ser renderizado. Ele existe
 * neste módulo apenas como chave de hash para a cor determinística.
 */

/**
 * Paleta de autores. Cada par foi verificado para >= 4.5:1 (WCAG AA texto normal)
 * contra os dois fundos de bolha recebida do tema WhatsApp:
 *   light -> --wa-bubble-in      (#ffffff)
 *   dark  -> --wa-bubble-in-dark (#202c33)
 * O nome do autor é texto pequeno (13px) e portador de informação, por isso 4.5:1
 * e não os 3:1 de texto grande.
 */
export const AUTHOR_PALETTE = [
  { light: '#b8478f', dark: '#f191c8' },
  { light: '#0a7cbb', dark: '#7fc9ee' },
  { light: '#9a6a00', dark: '#e0b246' },
  { light: '#0d7a5f', dark: '#6fd3b0' },
  { light: '#a1483a', dark: '#f0998a' },
  { light: '#6b4fbb', dark: '#b9a5f0' },
  { light: '#1f7a3d', dark: '#79cf95' },
  { light: '#b0416b', dark: '#f096b4' },
];

/** Cor neutra de quem não foi identificado — deliberadamente fora da paleta. */
export const UNKNOWN_AUTHOR_COLOR = { light: '#667781', dark: '#8696a0' };

/**
 * Sufixos que integrações externas grudam no nome do grupo.
 * `(GROUP)` vem da Evolution API; `(Group)`/`(Grupo)` vêm da app Chatwoot da WAHA (i18n).
 */
const GROUP_NAME_SUFFIX = /\s*\((?:GROUP|Group|Grupo)\)\s*$/;

/**
 * Prefixo de autor que a app Chatwoot da WAHA injeta no corpo das mensagens de grupo:
 *   "👥 *Nome (229480102662169@lid)*\n\ntexto"
 * Usado só para sanear o HISTÓRICO já gravado. Mensagens novas chegam limpas, com o
 * autor em content_attributes.group_sender.
 */
const LEGACY_GROUP_PREFIX = /^👥\s*\*(.+?)\*\n{1,2}/;

/** O identificador cru, onde quer que apareça em texto legado. */
const LEGACY_LID_TOKEN = /\s*\(\d{8,}@lid\)/g;

/**
 * Marcas de direção que o WhatsApp embute nos nomes (LRM/RLM/embeddings).
 * Invisíveis, mas quebram comparação de string, ordenação e busca.
 */
const BIDI_MARKS = /[‎‏‪-‮⁦-⁩]/g;

/**
 * djb2 — hash determinístico e estável entre sessões e dispositivos.
 * Sem estado persistido: o mesmo participante recebe sempre a mesma cor.
 */
const djb2 = str => {
  let hash = 5381;
  for (let i = 0; i < str.length; i += 1) {
    // eslint-disable-next-line no-bitwise
    hash = ((hash << 5) + hash + str.charCodeAt(i)) >>> 0;
  }
  return hash;
};

/**
 * Chave de identidade ESTÁVEL do participante, em ordem de preferência.
 * Nunca usar o nome como primeira opção: a cor mudaria quando a pessoa trocasse
 * o nome no WhatsApp.
 */
export const authorIdentityKey = (sender = {}) =>
  sender.lid || sender.phone || sender.name || '';

/**
 * Cor determinística do autor. Retorna o neutro quando não há identidade —
 * cinza comunica "não sei quem é" sem precisar de texto extra.
 */
export const authorColor = (sender = {}, isDark = false) => {
  const theme = isDark ? 'dark' : 'light';
  const key = authorIdentityKey(sender);
  if (!key) return UNKNOWN_AUTHOR_COLOR[theme];
  return AUTHOR_PALETTE[djb2(key) % AUTHOR_PALETTE.length][theme];
};

/** Iniciais para o avatar: primeira + última palavra do nome. */
export const authorInitials = (name = '') => {
  const parts = String(name).trim().split(/\s+/).filter(Boolean);
  if (!parts.length) return '';
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
};

/**
 * Remove o sufixo de integração do nome do grupo, só para exibição.
 * Cosmético e reversível — a origem do nome não é alterada.
 */
export const stripGroupSuffix = (name = '') =>
  String(name).replace(GROUP_NAME_SUFFIX, '').trim();

/**
 * Saneia mensagens ANTIGAS, gravadas antes da extração na ingestão.
 * Remove o identificador técnico e devolve o autor separado do texto, para que a
 * bolha consiga renderizar o histórico com a mesma aparência das mensagens novas.
 *
 * @returns {{ content: string, sender: {name: string}|null }}
 */
export const parseLegacyGroupContent = (content = '') => {
  const text = String(content ?? '');
  const match = text.match(LEGACY_GROUP_PREFIX);

  if (!match) {
    return { content: text.replace(LEGACY_LID_TOKEN, ''), sender: null };
  }

  const name = match[1]
    .replace(LEGACY_LID_TOKEN, '')
    .replace(BIDI_MARKS, '')
    .trim();
  const body = text.slice(match[0].length).replace(LEGACY_LID_TOKEN, '');

  return { content: body, sender: name ? { name } : null };
};

/** Formata E.164 brasileiro para leitura: 5566999991234 -> +55 66 9 9999-1234 */
export const formatPhone = (phone = '') => {
  const digits = String(phone).replace(/\D/g, '');
  const br = digits.match(/^55(\d{2})(9?)(\d{4})(\d{4})$/);
  if (br) {
    const [, ddd, ninth, head, tail] = br;
    return `+55 ${ddd} ${ninth ? `${ninth} ` : ''}${head}-${tail}`;
  }
  return digits ? `+${digits}` : '';
};

/**
 * Rótulo do autor na bolha e no painel. Nunca devolve o identificador técnico:
 * sem nome e sem telefone, assume-se não identificado (o chamador traduz).
 *
 * @returns {{ label: string|null, isUnknown: boolean }}
 */
export const participantLabel = (sender = {}) => {
  const name = (sender.name || '').trim();
  if (name) return { label: name, isUnknown: false };

  const phone = (sender.phone || '').trim();
  if (phone) return { label: formatPhone(phone), isUnknown: false };

  return { label: null, isUnknown: true };
};
