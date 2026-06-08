# frozen_string_literal: true

# KANBAN-P3-02: AI Triage com Captain.
# Classifica a intenção de uma conversation e sugere um kanban_stage_id.
# Não bloqueia features se Captain/LLM não estiver configurado — retorna
# fallback `{ stage_id: nil, confidence: 0, rationale: 'captain_unavailable' }`.
#
# Persistência: grava em `kanban_item.metadata.captain_classification`.
#
# A leitura de threshold/opt-in é feita upstream (TriageJob). Aqui só
# classifica e persiste.
class KanbanCaptain::TriageService
  attr_reader :item

  def initialize(item:)
    @item = item
  end

  def perform # rubocop:disable Metrics/AbcSize
    return fallback('no_conversation') if item.conversation.blank?

    stage_options = item.kanban.kanban_stages.ordered.to_a
    return fallback('no_stages') if stage_options.empty?

    last_messages = recent_messages_text
    return fallback('no_messages') if last_messages.blank?

    result = classify(last_messages, stage_options)
    persist(result)
    result
  rescue StandardError => e
    Rails.logger.tagged('kanban-captain').error("triage failed: #{e.class} #{e.message}")
    persist(fallback(e.message))
    fallback(e.message)
  end

  def self.call(item:)
    new(item: item).perform
  end

  private

  def recent_messages_text
    item.conversation.messages
        .where(message_type: %w[incoming outgoing])
        .where(private: false)
        .order(created_at: :desc)
        .limit(8)
        .pluck(:content)
        .compact
        .reverse
        .join("\n")
        .first(2000)
  end

  def classify(text, stage_options)
    enabled = captain_enabled?
    return fallback('captain_disabled') unless enabled

    prompt = build_prompt(text, stage_options)
    response = invoke_llm(prompt)
    return fallback('empty_response') if response.blank?

    parsed = parse_response(response, stage_options)
    parsed.merge(
      generated_at: Time.current.iso8601
    )
  rescue StandardError => e
    Rails.logger.tagged('kanban-captain').warn("classify error: #{e.message}")
    fallback(e.message)
  end

  def build_prompt(text, stages)
    stage_list = stages.each_with_index.map do |s, i|
      "#{i + 1}. id=#{s.id} name=\"#{s.name}\""
    end.join("\n")
    <<~PROMPT
      Classifique a intenção da conversa abaixo escolhendo UMA das etapas listadas.
      Responda APENAS com JSON: {"stage_id": <id>, "confidence": <0..1>, "rationale": "..."}.
      Confiança em decimal. Se nenhuma etapa servir, stage_id=null e confidence=0.

      Etapas:
      #{stage_list}

      Conversa:
      #{text}
    PROMPT
  end

  def invoke_llm(prompt)
    # Tenta usar Captain::BaseTaskService (Enterprise) se disponível
    return invoke_captain(prompt) if defined?(Captain::BaseTaskService) && captain_api_key_present?

    # Fallback direto via Llm::Config (ruby_llm) se houver
    return invoke_ruby_llm(prompt) if defined?(Llm::Config)

    nil
  end

  def invoke_captain(prompt)
    klass = Class.new(Captain::BaseTaskService) do
      def event_name
        'kanban.captain.triage'
      end
    end
    service = klass.new(account: item.kanban.account)
    response = service.send(:make_api_call,
                            model: Captain::BaseTaskService::GPT_MODEL,
                            messages: [
                              { role: 'system', content: 'Você classifica conversas em etapas de funil. Responda sempre JSON estrito.' },
                              { role: 'user', content: prompt }
                            ])
    response[:message].to_s
  end

  def invoke_ruby_llm(prompt)
    api_key = ENV.fetch('OPENAI_API_KEY', nil).presence ||
              InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
    return nil if api_key.blank?

    Llm::Config.with_api_key(api_key) do |context|
      chat = context.chat(model: Llm::Config::DEFAULT_MODEL)
      chat.with_instructions('Você classifica conversas. Responda apenas JSON estrito.')
      response = chat.ask(prompt)
      response.respond_to?(:content) ? response.content : response.to_s
    end
  end

  def captain_enabled? # rubocop:disable Metrics/CyclomaticComplexity
    return false unless item.kanban.account&.feature_enabled?('captain_integration') ||
                        item.kanban.account&.feature_enabled?('chatwoot_v4') ||
                        ENV['ENABLE_KANBAN_AI_TRIAGE'].present? ||
                        captain_api_key_present?

    true
  rescue StandardError
    captain_api_key_present?
  end

  def captain_api_key_present?
    ENV['OPENAI_API_KEY'].present? || InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value.present?
  rescue StandardError
    false
  end

  def parse_response(text, stage_options) # rubocop:disable Metrics/CyclomaticComplexity
    json_str = extract_json(text)
    data = JSON.parse(json_str)
    stage_id = data['stage_id'].present? ? Integer(data['stage_id']) : nil
    stage_id = nil unless stage_options.any? { |s| s.id == stage_id }
    confidence = Float(data['confidence'] || 0)
    confidence = (confidence * 100).round if confidence > 1 # normalize back if % wrong
    confidence = (confidence / 100.0).round(2) if confidence > 1
    {
      'stage_id' => stage_id,
      'confidence' => confidence.clamp(0.0, 1.0),
      'rationale' => data['rationale'].to_s.first(280)
    }
  rescue StandardError
    fallback('parse_error')
  end

  def extract_json(text)
    return '{}' if text.blank?

    match = text.match(/\{.*\}/m)
    match ? match[0] : '{}'
  end

  def persist(classification)
    meta = item.metadata || {}
    # rubocop:disable Rails/SkipsModelValidations
    item.update_columns(
      metadata: meta.merge('captain_classification' => classification),
      updated_at: Time.current
    )
    # rubocop:enable Rails/SkipsModelValidations
    persist_feedback_row(classification)
  rescue StandardError => e
    Rails.logger.tagged('kanban-captain').warn("persist error: #{e.message}")
  end

  def persist_feedback_row(classification)
    stage_id    = classification['stage_id'] || classification[:stage_id]
    confidence  = classification['confidence'] || classification[:confidence]
    rationale   = classification['rationale'] || classification[:rationale]
    KanbanCaptainFeedback.create!(
      kanban_item: item,
      suggested_stage_id: stage_id,
      confidence: confidence,
      rationale: rationale.to_s.first(2000),
      ai_feedback: 'pending'
    )
  rescue StandardError => e
    Rails.logger.tagged('kanban-captain').warn("persist_feedback_row error: #{e.message}")
  end

  def fallback(reason)
    {
      'stage_id' => nil,
      'confidence' => 0.0,
      'rationale' => reason.to_s.first(280),
      'generated_at' => Time.current.iso8601
    }
  end
end
