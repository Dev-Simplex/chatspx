class Captain::InboxPendingConversationsResolutionJob < ApplicationJob
  CAPTAIN_INFERENCE_RESOLVE_ACTIVITY_REASON = 'no outstanding questions'.freeze
  CAPTAIN_INFERENCE_HANDOFF_ACTIVITY_REASON = 'pending clarification from customer'.freeze

  queue_as :low

  def perform(inbox)
    return if inbox.account.captain_auto_resolve_disabled?

    if evaluate_conversation_completion?(inbox.account)
      perform_with_evaluation(inbox)
    else
      perform_time_based(inbox)
    end
  ensure
    Current.reset
  end

  private

  def evaluate_conversation_completion?(account)
    account.feature_enabled?('captain_tasks') && account.captain_auto_resolve_evaluated?
  end

  def perform_time_based(inbox)
    resolvable_pending_conversations(inbox).each do |conversation|
      assistant = assistant_for(conversation)
      next if assistant.blank?

      Current.executed_by = assistant
      create_resolution_message(conversation, assistant)
      conversation.resolved!
    end
  end

  def perform_with_evaluation(inbox)
    closure_on = auto_closure_enabled?(inbox.account)
    resolvable_pending_conversations(inbox, closure_on).each do |conversation|
      assistant = assistant_for(conversation)
      next if assistant.blank?

      Current.executed_by = assistant

      if closure_on
        route_with_closure_policy(conversation, assistant, inbox)
      else
        route_legacy(conversation, assistant, inbox)
      end
    end
  end

  # Comportamento legado (sem política de encerramento): completa -> resolve, incompleta -> handoff.
  def route_legacy(conversation, assistant, inbox)
    evaluation = evaluate_conversation(conversation, inbox)
    return unless still_resolvable_after_evaluation?(conversation, false)

    if evaluation[:complete]
      resolve_conversation(conversation, assistant, evaluation[:reason])
    else
      handoff_conversation(conversation, assistant, evaluation[:reason])
    end
  end

  # Política de encerramento (opt-in por conta): triagem janela-aware com cadência STATEFUL
  # (marcadores em custom_attributes; o cron reavalia a cada ciclo, sem job novo).
  def route_with_closure_policy(conversation, assistant, inbox)
    attrs = conversation.custom_attributes || {}

    # 1) Já na fila de encerramento: fecha pela válvula (N dias ocioso) ou espera o humano —
    #    sem re-rodar o LLM.
    if attrs['aguardando_encerramento_desde'].present?
      finalize_queue_expiry(conversation, assistant) if closure_queue_expired?(conversation)
      return
    end

    # 2) Trivial já avisado ("vou encerrar" enviado): fecha SÓ quando a janela expira (o
    #    cliente ainda pode voltar dentro dela). Sem re-LLM — usa a classe salva no aviso.
    if attrs['encerramento_avisado_em'].present?
      return if conversation.can_reply?

      finalize_close(conversation, assistant, attrs['encerramento_classe'] || 'trivial', 'janela expirou após o aviso')
      return
    end

    # 3) Primeira passagem: C (campanha sem resposta) nunca fecha por tempo (janela nunca
    #    abriu — espera o próximo template); senão classifica e despacha.
    return if campaign_without_reply?(conversation)

    evaluation = evaluate_conversation(conversation, inbox)
    return unless still_resolvable_after_evaluation?(conversation, true)

    dispatch_closure_action(conversation, assistant, evaluation)
  end

  def dispatch_closure_action(conversation, assistant, evaluation)
    classe = evaluation[:classe]
    case closure_action_for(conversation.account, classe)
    when 'queue'
      # Substantiva: manda o "vou encerrar" (lever, se a janela deixar) e joga pra fila do
      # humano JÁ — ele vê e resolve/resgata; a válvula fecha se ninguém agir em N dias.
      send_closing_notice(conversation, assistant, classe) if conversation.can_reply?
      Captain::Conversation::PendingClosureService.new(
        conversation: conversation, assistant: assistant,
        reason: "Aguardando encerramento (#{classe || 'substantive'}): #{evaluation[:reason]}"
      ).perform
    when 'close'
      # Trivial: nota gentil enquanto a janela abre, e fecha só quando ela expira. Sem nota
      # configurada (ou janela já fechada) -> fecha calado agora.
      return if conversation.can_reply? && send_closing_notice(conversation, assistant, classe)

      finalize_close(conversation, assistant, classe || 'trivial', evaluation[:reason])
    end
    # 'off' -> não age
  end

  # Resolve o assistant pela CONVERSA (dono atual -> participante -> elegível da inbox como
  # rede de segurança do legado, A9.4 — desvio CONSCIENTE de D-6 documentado no design).
  def assistant_for(conversation)
    conversation.assignee_agent_bot&.captain_assistant ||
      conversation.messages.where(sender_type: 'Captain::Assistant').order(:created_at).last&.sender ||
      conversation.inbox.captain_assistants.first
  end

  def evaluate_conversation(conversation, inbox)
    Captain::ConversationCompletionService.new(
      account: inbox.account,
      conversation_display_id: conversation.display_id
    ).perform
  end

  def resolvable_pending_conversations(inbox, closure_on = false)
    cutoff = auto_resolve_cutoff_time
    limit = Limits::BULK_ACTIONS_LIMIT
    pending = inbox.conversations.pending.where('last_activity_at < ?', cutoff)
    return pending.limit(limit) unless closure_on

    # Política ligada: também alcança as conversas OPEN da IA que ficaram paradas — a aba
    # "IA" acumula ABERTAS, que o scan pending-only não tocaria.
    open_ai = inbox.conversations.open.assigned_to_captain.where('last_activity_at < ?', cutoff)
    ids = (pending.limit(limit).ids + open_ai.limit(limit).ids).uniq.first(limit)
    inbox.conversations.where(id: ids)
  end

  def still_resolvable_after_evaluation?(conversation, closure_on = false)
    conversation.reload
    return false unless conversation.last_activity_at && conversation.last_activity_at < auto_resolve_cutoff_time
    return true if conversation.pending?

    # Com a política ligada, conversa OPEN ainda da IA segue elegível (a aba IA acumula abertas).
    closure_on && conversation.open? && conversation.assignee_agent_bot&.captain?
  rescue ActiveRecord::RecordNotFound
    false
  end

  def auto_resolve_cutoff_time
    Time.now.utc - 1.hour
  end

  def auto_closure_config(account)
    account.settings&.dig('auto_closure') || {}
  end

  def auto_closure_enabled?(account)
    auto_closure_config(account)['enabled'] == true
  end

  # Ação por classe (config da conta). Default conservador: TUDO pra fila (queue) até medir;
  # a conta liga 'close' por classe quando quiser auto-fechar (ex.: trivial).
  def closure_action_for(account, classe)
    (auto_closure_config(account)['actions'] || {})[classe.to_s].presence || 'queue'
  end

  # C — campanha (empresa iniciou) e o lead NUNCA respondeu: a janela nunca abriu.
  def campaign_without_reply?(conversation)
    conversation.campaign.present? && !conversation.messages.incoming.exists?
  end

  # Fecho SILENCIOSO: a despedida foi a nota de encerramento, enviada com a janela ABERTA
  # (pós-expiração nada free-form entrega). Grava motivo_encerramento (mesma chave do modal humano).
  def finalize_close(conversation, assistant, classe, reason)
    conversation.custom_attributes = (conversation.custom_attributes || {}).merge('motivo_encerramento' => "IA/#{classe}: #{reason}")
    create_private_note(conversation, assistant, "Auto-encerrado (#{classe}): #{reason}")
    conversation.with_captain_activity_context(
      reason: CAPTAIN_INFERENCE_RESOLVE_ACTIVITY_REASON,
      reason_type: :inference
    ) { conversation.resolved! }
    conversation.dispatch_captain_inference_resolved_event
  end

  # Válvula: conversa na fila de encerramento parada há mais de max_dias sem ação humana.
  def finalize_queue_expiry(conversation, assistant)
    finalize_close(conversation, assistant, 'valvula', "#{closure_max_days(conversation.account)}d na fila sem ação humana")
  end

  # Nota "vou encerrar" (config da conta, por classe). Retorna true se enviou. Sem texto
  # configurado -> não manda (fail-safe; o fluxo cai pro fecho direto). Marca o aviso + a classe.
  def send_closing_notice(conversation, assistant, classe)
    text = closing_notice_text(conversation, classe)
    return false if text.blank?

    I18n.with_locale(conversation.account.locale) do
      conversation.messages.create!(
        message_type: :outgoing,
        account_id: conversation.account_id,
        inbox_id: conversation.inbox_id,
        content: text,
        sender: assistant
      )
    end
    conversation.update!(custom_attributes: (conversation.custom_attributes || {}).merge(
      'encerramento_avisado_em' => Time.current.iso8601, 'encerramento_classe' => classe.to_s
    ))
    true
  end

  def closing_notice_text(conversation, classe)
    notices = auto_closure_config(conversation.account)['closing_notice'] || {}
    notices[classe.to_s].presence || notices['default'].presence
  end

  def closure_max_days(account)
    cfg = auto_closure_config(account)
    cfg.key?('max_dias') ? cfg['max_dias'].to_i : 3
  end

  def closure_queue_expired?(conversation)
    desde = conversation.custom_attributes&.dig('aguardando_encerramento_desde')
    return false if desde.blank?

    max_days = closure_max_days(conversation.account)
    return false if max_days <= 0 # 0 = mantém na fila indefinidamente (hold)

    Time.zone.parse(desde) < max_days.days.ago
  rescue StandardError
    false
  end

  def resolve_conversation(conversation, assistant, reason)
    create_private_note(conversation, assistant, "Auto-resolved: #{reason}")
    create_resolution_message(conversation, assistant)
    conversation.with_captain_activity_context(
      reason: CAPTAIN_INFERENCE_RESOLVE_ACTIVITY_REASON,
      reason_type: :inference
    ) { conversation.resolved! }
    conversation.dispatch_captain_inference_resolved_event
  end

  def handoff_conversation(conversation, assistant, reason)
    create_private_note(conversation, assistant, "Auto-handoff: #{reason}")
    create_handoff_message(conversation, assistant)
    conversation.with_captain_activity_context(
      reason: CAPTAIN_INFERENCE_HANDOFF_ACTIVITY_REASON,
      reason_type: :inference
    ) { conversation.bot_handoff! }
    conversation.dispatch_captain_inference_handoff_event
    send_out_of_office_message_if_applicable(conversation.reload)
  end

  def send_out_of_office_message_if_applicable(conversation)
    # Campaign conversations should never receive OOO templates — the campaign itself
    # serves as the initial outreach, and OOO would be confusing in that context.
    return if conversation.campaign.present?

    ::MessageTemplates::Template::OutOfOffice.perform_if_applicable(conversation)
  end

  def create_private_note(conversation, assistant, content)
    conversation.messages.create!(
      message_type: :outgoing,
      private: true,
      sender: assistant,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      content: content
    )
  end

  def create_resolution_message(conversation, assistant)
    I18n.with_locale(conversation.account.locale) do
      resolution_message = assistant.config['resolution_message']
      conversation.messages.create!(
        message_type: :outgoing,
        account_id: conversation.account_id,
        inbox_id: conversation.inbox_id,
        content: resolution_message.presence || I18n.t('conversations.activity.auto_resolution_message'),
        sender: assistant
      )
    end
  end

  def create_handoff_message(conversation, assistant)
    handoff_message = assistant.config['handoff_message']
    return if handoff_message.blank?

    conversation.messages.create!(
      message_type: :outgoing,
      sender: assistant,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      content: handoff_message,
      preserve_waiting_since: true
    )
  end
end
