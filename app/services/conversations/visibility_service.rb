# Espelho INVERSO de Conversations::PermissionFilterService#accessible_conversations
# (app/services/conversations/permission_filter_service.rb:18-25) + a cláusula de assignee do guard
# authorize_team_access (app/controllers/api/v1/accounts/conversations_controller.rb:246-260).
#
#   LÁ:   dado 1 usuário  -> quais conversas (relation, read-side da LISTA).
#   AQUI: dada 1 conversa -> quais usuários (audiência de notificação do sino).
#
# SE VOCÊ MUDAR UM, MUDE O OUTRO. As duas superfícies precisam concordar: notificar sobre uma
# conversa que o usuário não acha na lista (e que retorna 403 se ele abrir) é o bug que este
# service existe para fechar.
#
# ÚNICA EXCEÇÃO, DELIBERADA: a SUPERVISÃO DE TIME (TeamSupervision / team_supervisors) entra no
# PermissionFilterService mas NÃO entra aqui — o sino foi estreitado de propósito para "só o
# assignee" (D4 de task/supervisor-de-time.md) e supervisor de time grande viraria spam.
# NÃO "conserte" esta assimetria: ela é a decisão, não um esquecimento.
#
# NÃO aplicar esta regra dentro do NotificationBuilder: ele é o choke point dos 9 call sites e
# mataria a menção cross-team, que é deliberada (Messages::MentionService monta a audiência sem
# filtro de time de propósito — menção é consentimento explícito). Escopar na SELEÇÃO DE AUDIÊNCIA.
#
# Roda em job async (EventDispatcherJob): não depende de Current.user.
class Conversations::VisibilityService
  pattr_initialize [:conversation!]

  def visible_to?(user)
    return false if user.blank?
    return true if administrator_ids.include?(user.id)
    # Atribuição implica acesso (espelha authorize_team_access). Defensiva quanto ao time: o
    # AssignmentHandler já zera o assignee que não é do time (assignment_handler.rb:48-50), então
    # "time X + assignee do time Y" não persiste. Ainda vale para o assignee que saiu do inbox.
    return true if conversation.assignee_id == user.id
    return false unless inbox_member_ids.include?(user.id)
    # Conversa sem time notifica todo o inbox — senão conversa nova entra e passa batido.
    return true if conversation.team_id.nil?
    # Agente sem time nenhum vê tudo dos inboxes dele (a LISTA não filtra time para ele).
    return true unless users_with_teams_ids.include?(user.id)

    team_member_ids.include?(user.id)
  end

  private

  def account_id
    conversation.account_id
  end

  def administrator_ids
    @administrator_ids ||= AccountUser.where(account_id: account_id, role: :administrator).pluck(:user_id).to_set
  end

  def inbox_member_ids
    # Recheca o inbox: ConversationParticipant#ensure_inbox_access só valida na criação, então
    # participante que saiu do inbox continua na tabela.
    @inbox_member_ids ||= conversation.inbox.member_ids.to_set
  end

  def team_member_ids
    @team_member_ids ||= (conversation.team&.team_members&.pluck(:user_id) || []).to_set
  end

  # Resolve "quem tem time" para o loop inteiro em 1 query.
  def users_with_teams_ids
    @users_with_teams_ids ||= TeamMember.joins(:team)
                                        .where(teams: { account_id: account_id })
                                        .where(user_id: inbox_member_ids.to_a)
                                        .distinct
                                        .pluck(:user_id)
                                        .to_set
  end
end

Conversations::VisibilityService.prepend_mod_with('Conversations::VisibilityService')
