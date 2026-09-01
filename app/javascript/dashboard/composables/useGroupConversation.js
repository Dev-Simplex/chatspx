import { computed, unref } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import {
  formatPhone,
  participantLabel,
  stripGroupSuffix,
} from 'dashboard/helper/whatsappGroupHelper';

/**
 * Sufixo do JID de grupo do WhatsApp. Espelha `Conversation::WHATSAPP_GROUP_JID_SUFFIX`
 * (app/models/conversation.rb) — a mesma heurística dos dois lados, para o front
 * nunca discordar do backend sobre "isto é um grupo?".
 */
const WHATSAPP_GROUP_JID_SUFFIX = '@g.us';

const isGroupJid = value =>
  String(value || '').endsWith(WHATSAPP_GROUP_JID_SUFFIX);

/**
 * Ordem de exibição dos integrantes (design 3.3):
 *   1. admins A→Z
 *   2. demais A→Z
 *   3. não identificados por último
 * O comparador usa pt-BR para acento não jogar "Ângela" para o fim da lista.
 */
const compareParticipants = (a, b) => {
  if (a.isUnknown !== b.isUnknown) return a.isUnknown ? 1 : -1;
  if (a.admin !== b.admin) return a.admin ? -1 : 1;
  return String(a.label || '').localeCompare(String(b.label || ''), 'pt-BR', {
    sensitivity: 'base',
  });
};

/**
 * Normaliza um participante do snapshot `waha_group` (contrato C3) para o que a UI
 * precisa. O LID entra só como chave de identidade — nunca é renderizado.
 */
const normalizeParticipant = (participant = {}, index = 0) => {
  const { label, isUnknown } = participantLabel(participant);
  return {
    key:
      participant.lid || participant.phone || participant.name || `p-${index}`,
    lid: participant.lid || null,
    phone: participant.phone || null,
    name: participant.name || null,
    admin: Boolean(participant.admin),
    label,
    isUnknown,
    formattedPhone: participant.phone ? formatPhone(participant.phone) : '',
  };
};

/**
 * Estado de grupo de uma conversa de WhatsApp (inbox WAHA).
 *
 * Lê o snapshot de integrantes gravado em
 * `conversation.additional_attributes.waha_group` (contrato C3). Nada aqui faz
 * requisição: é leitura pura do que já está na store.
 *
 * @param {Object|import('vue').Ref} [conversation] Conversa a inspecionar.
 *   Quando omitida, usa a conversa selecionada.
 */
export const useGroupConversation = (conversation = null) => {
  const selectedChat = useMapGetter('getSelectedChat');

  const chat = computed(() => unref(conversation) || selectedChat.value || {});
  const sender = computed(() => chat.value?.meta?.sender || {});
  const additionalAttributes = computed(
    () => chat.value?.additional_attributes || {}
  );

  const isGroup = computed(() => {
    if (additionalAttributes.value.type === 'group') return true;
    if (isGroupJid(sender.value.identifier)) return true;

    const custom = sender.value.custom_attributes || {};
    return (
      isGroupJid(custom.waha_whatsapp_chat_id) ||
      isGroupJid(custom.waha_whatsapp_jid)
    );
  });

  /** Nome do grupo sem o sufixo que a integração gruda — só para exibição. */
  const groupName = computed(() => stripGroupSuffix(sender.value.name || ''));

  const snapshot = computed(
    () => additionalAttributes.value.waha_group || null
  );

  /** `false` enquanto o grupo nunca foi sincronizado — o painel mostra o empty state. */
  const hasSnapshot = computed(() => Boolean(snapshot.value?.synced_at));

  const participants = computed(() => {
    const list = snapshot.value?.participants;
    if (!Array.isArray(list)) return [];
    return list.map(normalizeParticipant).sort(compareParticipants);
  });

  /**
   * Contagem exibida. Vem do snapshot (que sabe o total mesmo quando a lista veio
   * truncada); cai para o tamanho da lista quando o campo não veio.
   */
  const participantCount = computed(() => {
    const count = Number(snapshot.value?.count);
    if (Number.isFinite(count) && count > 0) return count;
    return participants.value.length;
  });

  const unresolvedCount = computed(
    () => participants.value.filter(p => p.isUnknown).length
  );

  const syncedAt = computed(() => {
    const value = snapshot.value?.synced_at;
    if (!value) return null;
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  });

  return {
    isGroup,
    groupName,
    snapshot,
    hasSnapshot,
    participants,
    participantCount,
    unresolvedCount,
    syncedAt,
  };
};

export default useGroupConversation;
