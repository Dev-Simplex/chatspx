module Enterprise::ActivityMessageHandler
  def automation_status_change_activity_content
    return super unless Current.executed_by.instance_of?(Captain::Assistant)

    locale = Current.executed_by.account.locale
    key = captain_activity_key
    return unless key

    I18n.t(key, user_name: Current.executed_by.name, reason: captain_status_reason, locale: locale)
  end

  # Quando a IA (Captain::Assistant) atribui agente/time — ex.: handoff que roteia
  # pro time "locação" —, a atividade deve sair com o NOME da IA ("por Júlia"), não
  # com o genérico "por Sistema de Automação". Cobre create_team_change_activity e
  # create_assignee_change_activity, que resolvem o ator por aqui quando não há
  # Current.user (caso dos jobs do Captain, onde Current.executed_by = o assistant).
  def activity_message_owner(user_name)
    return Current.executed_by.name if !user_name && Current.executed_by.instance_of?(Captain::Assistant)

    super
  end

  # F3: marca a atividade como feita por uma IA (content_attributes.ai_actor),
  # capturado no contexto sync — o front estiliza essas atividades em roxo + ícone.
  def activity_message_params(content, content_attributes: nil)
    params = super
    return params unless Current.executed_by.instance_of?(Captain::Assistant)

    params.merge(
      content_attributes: (content_attributes || {}).merge(
        ai_actor: { id: Current.executed_by.id, name: Current.executed_by.name }
      )
    )
  end

  private

  def captain_status_reason
    captain_activity_reason.presence
  end

  def captain_activity_key
    return captain_resolved_activity_key if resolved?
    return captain_open_activity_key if open?
  end

  def captain_resolved_activity_key
    return 'conversations.activity.captain.resolved_by_tool' if captain_activity_reason_type == :tool && captain_status_reason.present?
    return 'conversations.activity.captain.resolved_with_reason' if captain_status_reason.present?

    'conversations.activity.captain.resolved'
  end

  def captain_open_activity_key
    return 'conversations.activity.captain.open_with_reason' if captain_status_reason.present?

    'conversations.activity.captain.open'
  end
end
