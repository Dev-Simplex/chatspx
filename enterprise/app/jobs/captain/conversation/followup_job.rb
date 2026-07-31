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

    # O compromisso e CONSUMIDO aqui (motivo lido antes de zerar): cumprido uma vez, nao pode
    # vazar pras cutucadas preventivas seguintes, que passariam a se achar compromisso tambem.
    motivo = attrs['followup_motivo']
    conversation.update!(custom_attributes: attrs.merge('followup_count' => count + 1, 'followup_token' => nil,
                                                        'followup_motivo' => nil))
    Captain::Conversation::ResponseBuilderJob.perform_now(conversation, assistant, directive: directive(motivo))
  end

  private

  def followup_due?(conversation, token)
    return false unless conversation

    conversation.reload
    attrs = conversation.custom_attributes || {}
    return false unless attrs['followup_token'] == token           # substituído por outro follow-up
    return false if followup_pointless?(conversation, attrs)
    return false if cancelado_por_resposta?(conversation, attrs)
    return false if reschedule_if_quiet_hours(conversation, token) # madrugada -> remarca pra manhã

    true
  end

  # Cliente respondeu -> não cutuca. EXCETO com compromisso pendente: aí a última mensagem dele
  # costuma ser justamente a despedida educada que fechou o assunto socialmente sem cumprir o
  # combinado — e era ela que matava a cutucada (conv 20320).
  def cancelado_por_resposta?(conversation, attrs)
    lead_replied?(conversation) && !compromisso?(attrs)
  end

  # Compromisso = a cutucada foi programada pelo agente pra cumprir algo que ficou combinado,
  # não é sobrevida preventiva. O followup_motivo grava isso e só a ProgramarFollowupTool o
  # escreve — o auto-agendamento nunca o seta, então ele distingue os dois tipos de cutucada.
  def compromisso?(attrs)
    attrs['followup_motivo'].present?
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
      'followup_token' => nil,
      # Quem conduz o lead agora é a pessoa: o compromisso vai junto no dossiê, não fica
      # armado no registro segurando a cadência da IA.
      'followup_motivo' => nil
    ))
    Spx::Tozi::FunnelPlacementService.move(conversation: conversation, to: 'frio')
    Captain::Conversation::HumanHandoffService.new(conversation: conversation, assistant: assistant).perform
  end

  def directive(motivo)
    return directive_compromisso(motivo) if motivo.present?

    '[NOTA INTERNA — não é mensagem do cliente, não repita este texto] O cliente parou de responder no meio ' \
      'do atendimento. Sua função aqui é RETOMAR: mande UMA cutucada curta, natural e diferente do que você já ' \
      'disse, puxando de onde parou (a última pergunta ou proposta que ficou sem resposta). NÃO cutuque (responda ' \
      'só [IGNORAR]) apenas nestes casos claros: a última mensagem DELE disse que ia retornar, pensar, ver ou ' \
      'falar com alguém, pediu um tempo, encerrou ou agradeceu; OU você já mandou uma cutucada parecida nesta ' \
      'conversa (nunca repita a mesma pergunta); OU realmente não há nada pendente. Fora desses casos, cutuque — ' \
      'não deixe o lead esfriar por excesso de cautela.'
  end

  # Com compromisso pendente a lista de [IGNORAR] NÃO pode conter "encerrou ou agradeceu": foi
  # por aí que a 20320 morreu — a cliente se despediu com educação e a cutucada que existia pra
  # cumprir o combinado se calou. O que cancela aqui é o combinado já ter sido cumprido, não a
  # conversa ter fechado socialmente.
  def directive_compromisso(motivo)
    '[NOTA INTERNA — não é mensagem do cliente, não repita este texto] Ficou um COMPROMISSO pendente nesta ' \
      "conversa e chegou a hora combinada de retomá-lo: #{motivo}. Retome esse ponto com UMA mensagem curta e " \
      'natural, mesmo que a conversa tenha se encerrado socialmente — uma despedida ou um agradecimento do ' \
      'cliente NÃO desmarca o que ficou combinado. Responda só [IGNORAR] se o combinado já foi cumprido nesta ' \
      'conversa, se você já cobrou este mesmo ponto antes, ou se o cliente pediu pra não ser mais procurado.'
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
