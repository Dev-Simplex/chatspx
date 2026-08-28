# frozen_string_literal: true

# Centraliza a regra de SUPERVISÃO DE TIME. Um supervisor enxerga as conversas dos
# times que supervisiona mesmo sem ser membro do time nem da caixa de entrada (D2),
# e mesmo com as flags de isolamento por agente ligadas. Espelha o padrão de
# AgentMessageIsolation: viewer-dependent (depende de QUEM olha), então precisa ser
# consultado em cada ponto de leitura em vez de viver numa association.
#
# Todo caminho aqui é no-op quando ninguém é supervisor: sem linha em
# team_supervisors, `team_ids` devolve [] e o caller faz short-circuit (D5, sem flag).
#
# ASSIMETRIA INTENCIONAL (D4): supervisão NÃO alcança o sino/notificações. O sino foi
# deliberadamente estreitado para "só o assignee" — supervisor de um time grande
# viraria spam. Não use este módulo dentro do NotificationBuilder.
module TeamSupervision
  module_function

  # Ids dos times que o usuário supervisiona NESTA conta. [] para AgentBot, contexto
  # sem User (jobs/widget/API pública) ou conta ausente.
  def team_ids(user, account)
    return [] unless user.is_a?(User)

    account_id = account.is_a?(Account) ? account.id : account
    return [] if account_id.blank?

    user.supervised_team_ids_for(account_id)
  end

  def supervises?(user, team_id, account)
    return false if team_id.blank?

    team_ids(user, account).include?(team_id.to_i)
  end

  # O CARGO responde true mesmo numa conta sem time nenhum: ele não depende de linha
  # em team_supervisors. As linhas continuam valendo para o agente que supervisiona
  # times específicos.
  def supervisor?(user, account)
    return false unless user.is_a?(User)

    account_id = account.is_a?(Account) ? account.id : account
    return false if account_id.blank?
    return true if user.supervisor_of_account?(account_id)

    team_ids(user, account).any?
  end

  # Agentes que o supervisor pode GERENCIAR: a união dos membros de todos os times que
  # ele supervisiona. É o mesmo conjunto usado em dois papéis:
  #   * quem ele pode renomear (AgentsController#authorize_supervisor_update);
  #   * o POOL de quem ele pode ADICIONAR num time supervisionado — ele nunca traz
  #     alguém de fora desse conjunto.
  # NÃO use isto para recortar GET /agents: aquela resposta alimenta a store `agents`
  # do dashboard inteiro (menções, participantes, Kanban), e estreitá-la some com
  # gente em telas que nada têm a ver com supervisão (T4).
  # [] para quem não supervisiona nada, então o caller faz short-circuit sem consultar
  # team_members.
  def manageable_agent_ids(user, account)
    supervised_ids = team_ids(user, account)
    return [] if supervised_ids.empty?

    TeamMember.where(team_id: supervised_ids).distinct.pluck(:user_id)
  end

  # Times que o usuário alcança: membro ∪ supervisionado. É o conjunto usado pelos
  # filtros de conversa — NÃO troque por ele a visibilidade de etiquetas/respostas
  # "de-time", que continua sendo só de membro.
  def accessible_team_ids(user, account)
    return [] unless user.is_a?(User)

    account_id = account.is_a?(Account) ? account.id : account
    return [] if account_id.blank?

    member_ids = user.teams.where(account_id: account_id).pluck(:id)
    member_ids | team_ids(user, account)
  end
end
