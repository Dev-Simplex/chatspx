/* global axios */
import ApiClient from './ApiClient';

// Os endpoints de agendamento já existiam, mas só eram chamados de dentro do
// Kanban (KanbanAPI). A conversa não deveria depender do módulo de Kanban para
// agendar, então o acesso vive aqui.
class ScheduledMessagesAPI extends ApiClient {
  constructor() {
    super('scheduled_messages', { accountScoped: true });
  }

  // Agendamentos de UMA conversa. `status` aceita pending/sent/failed/cancelled/all.
  // Recebe o display_id (o `id` da conversa no front); conversation_id na API é o id
  // interno, e mandar um no lugar do outro listava agendamentos de outra conversa.
  getByConversation(conversationDisplayId, { status = 'pending' } = {}) {
    return axios.get(this.url, {
      params: { conversation_display_id: conversationDisplayId, status },
    });
  }

  // A caixa de entrada pode ser outra que não a da conversa, então o endpoint
  // devolve todas as caixas da conta.
  getInboxes() {
    return axios.get(`${this.url}/inboxes`);
  }

  create(scheduledMessage) {
    return axios.post(this.url, { scheduled_message: scheduledMessage });
  }

  cancel(id) {
    return axios.delete(`${this.url}/${id}`);
  }
}

export default new ScheduledMessagesAPI();
