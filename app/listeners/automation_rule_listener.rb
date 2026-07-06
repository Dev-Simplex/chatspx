class AutomationRuleListener < BaseListener
  def conversation_updated(event)
    process_conversation_event(event, 'conversation_updated')
  end

  def conversation_created(event)
    process_conversation_event(event, 'conversation_created')
  end

  def conversation_opened(event)
    process_conversation_event(event, 'conversation_opened')
  end

  def conversation_resolved(event)
    process_conversation_event(event, 'conversation_resolved')
  end

  def message_created(event)
    message = event.data[:message]

    return if ignore_message_created_event?(event)

    account = message.try(:account)
    payload = { message: message, changed_attributes: event.data[:changed_attributes] }

    run_engine('message_created', account, message.conversation, payload)
  end

  private

  def process_conversation_event(event, event_name)
    return if performed_by_automation?(event)

    auto_reply_skip_events = %w[conversation_created conversation_opened]
    return if auto_reply_skip_events.include?(event_name) && ignore_auto_reply_event?(event)

    conversation = event.data[:conversation]
    account = conversation.account
    payload = { changed_attributes: event.data[:changed_attributes] }

    run_engine(event_name, account, conversation, payload)
  end

  # Motor unificado, gated por conta: com a flag `flows` ligada, a conta roda os Flows (que
  # o backfill criou espelhando as regras antigas); sem ela, roda as AutomationRules como
  # sempre. Mutuamente exclusivo por conta — é a mitigação de R-1 (dupla-execução) durante a
  # coexistência, sem tocar dados e reversível (desligar a flag volta ao motor antigo).
  def run_engine(event_name, account, conversation, payload)
    return if account.blank?

    if flows_engine_active?(account)
      run_flows(event_name, account, conversation, payload)
    else
      run_rules(event_name, account, conversation, payload)
    end
  end

  # O motor Flow só assume quando a flag está ligada E a conta já tem flows (o backfill
  # rodou). Sem o segundo gate, ligar a flag antes do backfill silenciaria TODAS as
  # automations da conta (run_flows iteraria vazio e as AutomationRules nunca rodariam).
  def flows_engine_active?(account)
    return false unless account.flows_engine_enabled?

    Rails.cache.fetch("flows_present:#{account.id}", expires_in: 2.minutes) do
      account.flows.active.exists?
    end
  end

  def run_rules(event_name, account, conversation, payload)
    current_account_rules(event_name, account).each do |rule|
      conditions_match = ::AutomationRules::ConditionsFilterService.new(rule, conversation, payload).perform
      ::AutomationRules::ActionService.new(rule, account, conversation).perform if conditions_match.present?
    end
  end

  def run_flows(event_name, account, conversation, payload)
    current_account_flows(event_name, account).each do |flow|
      gate = ::Flows::RuleAdapter.new(conditions: flow.trigger_config['conditions'], flow: flow)
      conditions_match = ::AutomationRules::ConditionsFilterService.new(gate, conversation, payload).perform
      ::Flows::RunnerService.new(flow: flow, conversation: conversation, trigger_payload: payload).perform if conditions_match.present?
    end
  end

  def current_account_rules(event_name, account)
    cache_key = "automation_rules:#{account.id}:#{event_name}"
    rule_ids = Rails.cache.fetch(cache_key, expires_in: 2.minutes) do
      AutomationRule.where(event_name: event_name, account_id: account.id, active: true).pluck(:id)
    end
    AutomationRule.where(id: rule_ids)
  end

  def current_account_flows(event_name, account)
    cache_key = "flows:#{account.id}:#{event_name}"
    flow_ids = Rails.cache.fetch(cache_key, expires_in: 2.minutes) do
      account.flows.active.conversation_event.where("trigger_config->>'event_name' = ?", event_name).pluck(:id)
    end
    Flow.where(id: flow_ids)
  end

  # Reconhece tanto AutomationRule (motor antigo) quanto Flow (motor novo) como "sistema",
  # para não re-disparar sobre eventos que o próprio motor gerou.
  def performed_by_automation?(event)
    performer = event.data[:performed_by]
    performer.present? && (performer.instance_of?(AutomationRule) || performer.instance_of?(Flow))
  end

  def ignore_auto_reply_event?(event)
    conversation = event.data[:conversation]
    conversation.additional_attributes['auto_reply'].present?
  end

  # Anti-loop de mensagem: ignora mensagens que o próprio motor criou. Checa a chave legada
  # `automation_rule_id` E a nova `flow_id` (generalização — Flows::ActionService marca as
  # mensagens com flow_id, action_service.rb).
  def ignore_message_created_event?(event)
    message = event.data[:message]
    performed_by_automation?(event) || message.activity? || message.auto_reply_email? ||
      message.content_attributes&.dig('automation_rule_id').present? ||
      message.content_attributes&.dig('flow_id').present?
  end
end
