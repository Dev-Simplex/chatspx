import { reactive } from 'vue';
import GroupParticipantsAPI from 'dashboard/api/groupParticipants';

/**
 * Contato SALVO de cada integrante de um grupo de WhatsApp, por conversa:
 * { [conversationId]: { telefone: { id, name } } }.
 *
 * O WhatsApp quase nunca manda o nome do integrante; o nome que o agente salvou
 * no ChatSPX vem do GET /waha_group (ligado pelo telefone, com e sem o nono
 * dígito). Uma requisição por conversa: o painel de integrantes e todas as
 * bolhas do grupo leem daqui.
 */
const cache = reactive({});
const pending = {};

export const loadGroupSavedContacts = (
  conversationId,
  { force = false } = {}
) => {
  if (!conversationId) return Promise.resolve();
  if (pending[conversationId]) return pending[conversationId];
  if (cache[conversationId] && !force) return Promise.resolve();

  pending[conversationId] = GroupParticipantsAPI.show(conversationId)
    .then(({ data }) => {
      cache[conversationId] = data?.contacts || {};
    })
    .catch(() => {
      // Sem a lista, a tela segue mostrando o número: nada quebra.
    })
    .finally(() => {
      delete pending[conversationId];
    });
  return pending[conversationId];
};

/** null enquanto não carregou (ninguém é marcado como "não salvo" antes da hora). */
export const groupSavedContacts = conversationId =>
  cache[conversationId] || null;
