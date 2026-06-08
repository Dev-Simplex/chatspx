class Captain::Conversation::FollowupJob < ApplicationJob
  queue_as :low

  MAX_FOLLOWUPS = 4
  QUIET_START = 21 # 21h
  QUIET_END = 8    # 8h

  # Cutucada decidida pelo agente (via ProgramarFollowupTool). Dispara só se ainda
  # fizer sentido: token atual, sem trava humana, cliente não respondeu, dentro de
  # horário civilizado. A própria cutucada é gerada pelo agente no contexto.
  def perform(conversation, token)
    return unless conversation

    conversation.reload
    attrs = conversation.custom_attributes || {}
    return unless attrs['followup_token'] == token            # substituído por outro follow-up
    return if truthy?(attrs['atendimento_humano'])            # humano travou o bot
    return if conversation.resolved?
    return if lead_replied?(conversation)                     # cliente respondeu -> não cutuca

    return if reschedule_if_quiet_hours(conversation, token)  # madrugada -> remarca pra manhã

    count = attrs['followup_count'].to_i
    if count >= MAX_FOLLOWUPS
      conversation.update!(custom_attributes: attrs.merge(
        'tozi_status_lead' => 'esfriado',
        'followup_status' => 'esfriado (sem resposta após cutucadas)',
        'followup_token' => nil
      ))
      # Bloco 3+4 (funil Tozi): esgotou as cutucadas in-window -> card "Frio" e, em
      # inbox Cloud API, agenda a cadência de reativação por HSM (fora da janela 24h).
      Spx::Tozi::FunnelPlacementService.move(conversation: conversation, to: 'frio')
      Spx::Tozi::ReactivationCadenceService.new(conversation: conversation).perform
      return
    end

    conversation.update!(custom_attributes: attrs.merge('followup_count' => count + 1, 'followup_token' => nil))
    assistant = conversation.inbox.captain_assistant
    return unless assistant

    Captain::Conversation::ResponseBuilderJob.perform_now(conversation, assistant, directive: directive(attrs['followup_motivo']))
  end

  private

  def directive(motivo)
    base = '[NOTA INTERNA — não é mensagem do cliente] O cliente está sem responder há um tempo. ' \
           'Se ainda fizer sentido, mande uma cutucada curta e natural, retomando o assunto de onde parou'
    base += " (#{motivo})" if motivo.present?
    "#{base}. Se já não fizer sentido insistir, responda apenas [IGNORAR]."
  end

  def lead_replied?(conversation)
    last = conversation.messages.where(message_type: %i[incoming outgoing], private: false).order(:created_at).last
    last.nil? || last.message_type == 'incoming'
  end

  def reschedule_if_quiet_hours(conversation, token)
    tz = ActiveSupport::TimeZone['America/Cuiaba'] || ActiveSupport::TimeZone['UTC']
    now = Time.current.in_time_zone(tz)
    return false if now.hour >= QUIET_END && now.hour < QUIET_START

    next_morning = now.hour >= QUIET_START ? now.tomorrow.change(hour: QUIET_END) : now.change(hour: QUIET_END)
    self.class.set(wait: next_morning - now).perform_later(conversation, token)
    true
  end

  def truthy?(value)
    [true, 'true', 1, '1'].include?(value)
  end
end
