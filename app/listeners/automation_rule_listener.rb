class AutomationRuleListener < BaseListener
  # Palavras de opt-out (descadastro) do WhatsApp marketing. Casamento por IGUALDADE (não
  # "contains") sobre a mensagem normalizada — acento/caixa/pontuação-insensível, ver
  # #opt_out_message? — pra "PARAR"/"Sair"/"stop."/"CANCELAR" descadastrarem, mas "não vou
  # parar de comprar" (que só CONTÉM "parar") NÃO. Lista central e extensível.
  OPT_OUT_KEYWORDS = %w[parar sair stop cancelar].freeze

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
    # Compliance opt-out ("PARAR"): uma mensagem incoming de descadastro registra a suppression
    # e NÃO dispara flow algum por si — nem por-evento, nem keyword. Só corre em message_created
    # (único evento com a mensagem no payload) e só com o motor Flow ativo (estamos em run_flows).
    return if event_name == 'message_created' && handle_incoming_opt_out(account, conversation, payload)

    current_account_flows(event_name, account).each do |flow|
      gate = ::Flows::RuleAdapter.new(conditions: flow.trigger_config['conditions'], flow: flow)
      conditions_match = ::AutomationRules::ConditionsFilterService.new(gate, conversation, payload).perform
      ::Flows::RunnerService.new(flow: flow, conversation: conversation, trigger_payload: payload).perform if conditions_match.present?
    end

    # Os Flows `trigger_type: keyword` casam contra o CONTEÚDO da mensagem, não contra um
    # event_name — por isso ficam fora do laço por-evento e só rodam em message_created (o
    # único evento que carrega a mensagem no payload). A gate `flows_engine_active?` já foi
    # aplicada por run_engine, então reaproveitamos o cache de flows sem re-checá-la.
    run_keyword_flows(account, conversation, payload) if event_name == 'message_created'
  end

  # Gatilho `keyword`: dispara os Flows keyword-triggered ativos quando o conteúdo de uma
  # mensagem INCOMING de contato casa com as palavras-chave em trigger_config. Anti-loop já
  # garantido por ignore_message_created_event? (mensagens com flow_id nem chegam ao listener)
  # e reforçado aqui pelo filtro incoming (as mensagens que o motor gera são outgoing).
  def run_keyword_flows(account, conversation, payload)
    message = payload[:message]
    return unless message&.incoming? && !message.private?

    content = message.content.to_s
    return if content.blank?

    current_account_keyword_flows(account).each do |flow|
      next unless keyword_trigger_match?(content, flow.trigger_config)

      ::Flows::RunnerService.new(flow: flow, conversation: conversation, trigger_payload: payload).perform
    end
  end

  # Detecta e processa um opt-out numa mensagem INCOMING de contato. Ao casar, registra a
  # suppression de marketing (reason: opt_out) e devolve true — o run_flows aborta TODO disparo
  # por essa mensagem. Reusa os mesmos filtros de elegibilidade do keyword matcher (incoming,
  # não-privada); o anti-loop flow_id já foi aplicado por ignore_message_created_event?.
  def handle_incoming_opt_out(account, conversation, payload)
    message = payload[:message]
    return false unless message&.incoming? && !message.private?
    return false unless opt_out_message?(message.content)

    contact = conversation.contact
    ContactFlowSuppression.record_opt_out!(contact: contact, account: account) if contact.present?
    true
  end

  # É um pedido de descadastro? A mensagem, normalizada (transliterada, minúscula, colapsada) e
  # com a pontuação removida, é EXATAMENTE uma das OPT_OUT_KEYWORDS. Match exato (não substring)
  # evita falso-positivo em frases que só contêm a palavra. Ver #normalize_keyword.
  def opt_out_message?(content)
    normalized = normalize_keyword(content).gsub(/[^a-z0-9 ]/, '').strip
    OPT_OUT_KEYWORDS.include?(normalized)
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

  # Mesmo padrão de cache (2 min) dos flows por-evento — evita a query por mensagem. A lista
  # de keyword flows muda raramente; o matching case/acento-insensitive roda em memória.
  def current_account_keyword_flows(account)
    cache_key = "flows:#{account.id}:keyword"
    flow_ids = Rails.cache.fetch(cache_key, expires_in: 2.minutes) do
      account.flows.active.keyword.pluck(:id)
    end
    Flow.where(id: flow_ids)
  end

  # Casa o conteúdo da mensagem com as keywords do trigger_config, case- e acento-insensitive
  # (I18n.transliterate: "Olá" → "ola", como o normalize do WahaMessageResolvable). Modos:
  #   • 'exact'    → o conteúdo normalizado é IGUAL a alguma keyword
  #   • 'contains' → o conteúdo CONTÉM alguma keyword como substring (default)
  # Keywords em branco são descartadas; sem keyword válida, nunca casa.
  def keyword_trigger_match?(content, trigger_config)
    keywords = Array(trigger_config['keywords']).filter_map { |kw| normalize_keyword(kw).presence }
    return false if keywords.blank?

    haystack = normalize_keyword(content)
    return false if haystack.blank?

    if trigger_config['match'].to_s == 'exact'
      keywords.include?(haystack)
    else
      keywords.any? { |kw| haystack.include?(kw) }
    end
  end

  def normalize_keyword(text)
    I18n.transliterate(text.to_s).downcase.gsub(/\s+/, ' ').strip
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
