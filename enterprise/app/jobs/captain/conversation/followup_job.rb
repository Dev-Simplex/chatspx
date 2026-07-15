class Captain::Conversation::FollowupJob < ApplicationJob
  queue_as :low

  MAX_FOLLOWUPS = 4
  QUIET_START = 21 # 21h
  QUIET_END = 8    # 8h

  # Cutucada decidida pelo agente (via ProgramarFollowupTool). Dispara só se ainda
  # fizer sentido: token atual, dono da conversa ainda é a IA, cliente não respondeu,
  # dentro de horário civilizado. A própria cutucada é gerada pelo agente no contexto.
  def perform(conversation, token)
    return unless followup_due?(conversation, token)

    # Dono resolvido ANTES de consumir token/followup_count (gate por atribuição, D-6):
    # se a cutucada não vai sair, não se gasta tentativa nem se invalida o token (token
    # órfão é inofensivo — o próximo ProgramarFollowupTool o substitui). A cutucada sai
    # do dono ATUAL da conversa (não da inbox) — transferência IA→IA mid-followup faz a
    # cutucada sair com a voz da IA nova.
    assistant = owner_assistant(conversation)
    return unless assistant # dono não é IA -> cutucada morre SEM consumir token/count

    attrs = conversation.custom_attributes || {}
    count = attrs['followup_count'].to_i
    return cool_down_lead(conversation, attrs, assistant) if count >= MAX_FOLLOWUPS

    conversation.update!(custom_attributes: attrs.merge('followup_count' => count + 1, 'followup_token' => nil))
    Captain::Conversation::ResponseBuilderJob.perform_now(conversation, assistant, directive: directive(attrs['followup_motivo']))
  end

  private

  def followup_due?(conversation, token)
    return false unless conversation

    conversation.reload
    attrs = conversation.custom_attributes || {}
    return false unless attrs['followup_token'] == token           # substituído por outro follow-up
    return false if followup_pointless?(conversation, attrs)
    return false if lead_replied?(conversation)                    # cliente respondeu -> não cutuca
    return false if reschedule_if_quiet_hours(conversation, token) # madrugada -> remarca pra manhã

    true
  end

  # Resolvida, ou esperando atendente humano (Modelo A): cutucar só atrapalha.
  def followup_pointless?(conversation, attrs)
    conversation.resolved? || attrs['aguardando_humano_desde'].present?
  end

  # Espelho captain dono da conversa -> assistant; humano/webhook-bot/sem dono -> nil.
  def owner_assistant(conversation)
    mirror = conversation.assignee_agent_bot
    return unless mirror&.captain?

    mirror.captain_assistant
  end

  # Esgotou as cutucadas in-window e o cliente segue sem responder: em vez de só esfriar,
  # ESCALA pra um humano tentar recuperar o lead que a IA não converteu. Vai pelo mesmo
  # caminho do handoff do agente (HumanHandoffService: abre, roteia pro time, marca
  # `aguardando_humano_desde` -> a IA para de cutucar e de responder). Substitui a cadência
  # de reativação por HSM: quem conduz o lead frio passa a ser a pessoa, não um automático.
  def cool_down_lead(conversation, attrs, assistant)
    conversation.update!(custom_attributes: attrs.merge(
      'tozi_status_lead' => 'esfriado',
      'followup_status' => 'esgotou cutucadas -> encaminhado pra humano',
      'followup_token' => nil
    ))
    Spx::Tozi::FunnelPlacementService.move(conversation: conversation, to: 'frio')
    Captain::Conversation::HumanHandoffService.new(conversation: conversation, assistant: assistant).perform
  end

  def directive(motivo)
    base = '[NOTA INTERNA — não é mensagem do cliente, não repita este texto] O cliente está sem responder há um tempo. ' \
           'Antes de tudo, olhe a ÚLTIMA mensagem DELE: se ele disse que vai retornar, vai pensar, vai ver/falar com ' \
           'alguém, pediu um tempo, encerrou ou agradeceu, responda apenas [IGNORAR] — ele volta sozinho, não insista. ' \
           'Responda [IGNORAR] também se você já mandou uma cutucada parecida nesta conversa: NUNCA repita a mesma ' \
           'pergunta. Só se REALMENTE fizer sentido retomar (ele parou no meio de algo pendente, sem dizer que voltava) ' \
           'mande UMA cutucada curta, natural e DIFERENTE das anteriores, retomando de onde parou'
    base += " (#{motivo})" if motivo.present?
    "#{base}. Na dúvida, responda [IGNORAR]."
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
end
