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

  def supervisor?(user, account)
    team_ids(user, account).any?
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
