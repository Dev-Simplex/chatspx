class NpsSurveys::ResponseBuilder # rubocop:disable Metrics/ClassLength
  pattr_initialize [:message]

  def perform
    return unless message.incoming?

    conversation = message.conversation
    nps_response = find_active_nps_response(conversation)
    return unless nps_response
    return if agent_responded_after_nps?(conversation, nps_response)

    score = extract_score_from_message

    if score.nil?
      # Only send "invalid response" for short messages that look like NPS attempts
      # (e.g. "onze", "abc", "?"), and cap at 2 retries to avoid annoying loops.
      send_invalid_response_message(nps_response) if looks_like_nps_attempt? && retry_count_within_limit?(nps_response)
      return
    end

    process_nps_response(nps_response, score)
  end

  private

  def agent_responded_after_nps?(conversation, nps_response)
    nps_message_id = nps_response.metadata&.dig('message_id')
    return false unless nps_message_id

    # Usa all_messages — deteccao de resposta agente apos NPS deve ver historico global.
    conversation.all_messages
                .where(message_type: :outgoing)
                .where('id > ?', nps_message_id)
                .where.not("content_attributes ->> 'nps_survey' = 'true'")
                .exists?
  end

  def find_active_nps_response(conversation)
    # Find the most recent NPS response with status "sent" that has not yet been answered
    nps_response = conversation.nps_responses
                               .where(status: :sent)
                               .where(answered_at: nil)
                               .order(created_at: :desc)
                               .first

    return nil if nps_response.blank?
    return nil if nps_response.expired?

    nps_response
  end

  def extract_score_from_message
    # Try to get score from content_attributes first (widget submission)
    score = message.content_attributes.dig('submitted_values', 'nps_response', 'score')
    return score.to_i if score.present? && valid_score?(score.to_i)

    # Try to extract from message content (text response)
    score = NpsSurveys::ScoreValidator.validate_and_extract(message.content)
    return score if score.present? && valid_score?(score)

    # [NOVO] Fallback de PARSING via LLM (so quando o regex falha e a mensagem
    # parece uma nota escrita por extenso, ex.: "dez", "nota nove"). Atras de
    # toggle por inbox; nunca infere nota a partir de sentimento.
    llm_score = extract_score_via_llm
    return llm_score if llm_score.present? && valid_score?(llm_score)

    nil
  end

  def extract_score_via_llm
    return nil unless gpt_parse_enabled?
    return nil unless gpt_parse_candidate?(message.content)

    NpsSurveys::ScoreLlmParser.extract(text: message.content, account: message.account)
  end

  def gpt_parse_enabled?
    config = message.inbox&.nps_config || {}
    ActiveModel::Type::Boolean.new.cast(config['gpt_parse_enabled'])
  end

  # Limita as chamadas ao LLM: mensagem curta que contenha um digito ou um
  # numeral por extenso (0-10). Evita gastar chamada em conversa normal.
  NUMBER_WORDS = /\b(zero|um|uma|dois|duas|tr[êe]s|quatro|cinco|seis|sete|oito|nove|dez)\b/i

  def gpt_parse_candidate?(text)
    normalized = NpsSurveys::ScoreValidator.normalize(text)
    return false if normalized.blank?
    return false if normalized.length > 40

    normalized.match?(/\d/) || normalized.match?(NUMBER_WORDS)
  end

  def valid_score?(score)
    score.is_a?(Integer) && score >= 0 && score <= 10
  end

  def process_nps_response(nps_response, score)
    comment = extract_comment

    # Update NPS response first to mark it as answered
    # This prevents conversation from reopening when response_to_active_survey? is checked
    nps_response.update!(
      score: score,
      comment: comment,
      status: :responded,
      answered_at: Time.current
    )

    # Create activity message (only if one doesn't already exist for this NPS response)
    create_responded_activity_message(nps_response, score) unless activity_message_exists?(nps_response, score)

    # Optionally send thank you message (per-band se configurado)
    send_thank_you_message(nps_response) if should_send_thank_you?(nps_response)

    # [NOVO] Detrator (0-6) -> reabrir + atribuir a humano + label, para
    # follow-up (o unico caso em que reabrir e desejado). Config-driven, idempotente.
    route_detractor(nps_response, score)

    # Respostas por extenso ("nota nove") sao extraidas pelo LLM DEPOIS do
    # ReopenGuard (que so ve regex) ja ter reaberto a conversa. Como uma resposta
    # de NPS valida nao deve reabrir (igual ao caminho de digito), re-resolvemos —
    # exceto quando e um detrator com reopen configurado (unico reabrir desejado).
    ensure_conversation_not_reopened_by_response(nps_response, score)

    nps_response
  end

  # Se a conversa reabriu por causa da mensagem-resposta do NPS, devolve para
  # resolved. So age quando de fato esta aberta e nao e detrator-com-reopen.
  def ensure_conversation_not_reopened_by_response(nps_response, score)
    return if detractor_reopen_requested?(nps_response, score)

    conversation = nps_response.conversation
    conversation.reload
    return unless conversation.open?

    conversation.skip_team_required_for_resolution_validation = true
    conversation.update!(status: :resolved)
  rescue StandardError => e
    Rails.logger.warn("[NPS] nao consegui re-resolver conv=#{nps_response.conversation_id} apos resposta: #{e.message}")
  end

  def detractor_reopen_requested?(nps_response, score)
    return false unless score.between?(0, 6)

    config = nps_response.inbox.nps_config || {}
    truthy_config?(config['detractor_reopen'])
  end

  # Ramifica o pos-resposta pela faixa. So o detrator dispara acao (reabrir/atribuir/label);
  # promotor e neutro apenas recebem o agradecimento (send_thank_you_message).
  def route_detractor(nps_response, score)
    return unless score.between?(0, 6)

    config = nps_response.inbox.nps_config || {}
    return unless detractor_routing_configured?(config)

    conversation = nps_response.conversation
    apply_detractor_label(conversation, config['detractor_label'])
    apply_detractor_assignment(conversation, config)
    reopen_for_detractor(conversation) if truthy_config?(config['detractor_reopen'])
    stamp_detractor_routed(nps_response)
  rescue StandardError => e
    Rails.logger.warn("[NPS detractor] routing failed conv=#{nps_response.conversation_id}: #{e.message}")
  end

  def detractor_routing_configured?(config)
    truthy_config?(config['detractor_reopen']) ||
      config['detractor_assignee_id'].present? ||
      config['detractor_team_id'].present? ||
      config['detractor_label'].present?
  end

  def apply_detractor_label(conversation, label)
    return if label.blank?
    return if conversation.label_list.include?(label)

    conversation.add_labels(label)
  end

  def apply_detractor_assignment(conversation, config)
    attrs = {
      assignee_id: resolved_detractor_id(conversation, config, :assignee_id, 'detractor_assignee_id', :users),
      team_id: resolved_detractor_id(conversation, config, :team_id, 'detractor_team_id', :teams)
    }.compact

    conversation.update!(attrs) if attrs.present?
  end

  # Resolve o id de destino (agente/time) so quando muda de fato e pertence a conta.
  def resolved_detractor_id(conversation, config, current_attr, config_key, association)
    id = config[config_key].presence&.to_i
    return nil if id.nil?
    return nil if conversation.public_send(current_attr) == id
    return nil unless conversation.account.public_send(association).exists?(id: id)

    id
  end

  def reopen_for_detractor(conversation)
    return unless conversation.resolved?

    conversation.open!
  end

  def stamp_detractor_routed(nps_response)
    meta = nps_response.metadata || {}
    return if meta['detractor_routed_at'].present?

    nps_response.update!(metadata: meta.merge('detractor_routed_at' => Time.current.iso8601))
  end

  def truthy_config?(value)
    ActiveModel::Type::Boolean.new.cast(value)
  end

  def create_responded_activity_message(nps_response, score)
    content = I18n.t('conversations.activity.nps.responded',
                     score: score,
                     default: "NPS survey responded with score #{score}")
    activity_message_params = {
      account_id: nps_response.account_id,
      inbox_id: nps_response.inbox_id,
      message_type: :activity,
      content: content
    }
    conversation = nps_response.conversation
    ::Conversations::ActivityMessageJob.perform_later(conversation.id, activity_message_params) if content
  end

  def activity_message_exists?(nps_response, score)
    # Check if an activity message with the same content was created recently (within last 5 minutes)
    # This prevents duplicate activity messages when the job is retried
    expected_content = I18n.t('conversations.activity.nps.responded',
                              score: score,
                              default: "NPS survey responded with score #{score}")
    conversation = nps_response.conversation
    conversation.messages
                .where(message_type: :activity)
                .where(content: expected_content)
                .exists?(['created_at >= ?', 5.minutes.ago])
  end

  def extract_comment
    # Try to get comment from content_attributes first
    comment = message.content_attributes.dig('submitted_values', 'nps_response', 'comment')
    return comment if comment.present?

    # If no score was found in content, the entire message might be a comment
    # But we should only treat it as comment if it's not a score
    score_in_content = NpsSurveys::ScoreValidator.validate_and_extract(message.content)
    return nil if score_in_content.present?

    # If message doesn't contain a score, it might be a comment
    (message.content.presence)
  end

  def should_send_thank_you?(nps_response)
    band_thank_you_message(nps_response).present?
  end

  # Mensagem por faixa (promotor/neutro/detrator) com fallback para a mensagem
  # generica thank_you_message — mantem compat com a config antiga.
  def band_thank_you_message(nps_response)
    config = nps_response.inbox.nps_config || {}
    key = case nps_response.score
          when 9..10 then 'thank_you_promoter'
          when 7..8 then 'thank_you_passive'
          when 0..6 then 'thank_you_detractor'
          end
    band = key ? config[key] : nil
    band.presence || config['thank_you_message'].presence
  end

  def send_thank_you_message(nps_response)
    thank_you_message = band_thank_you_message(nps_response) ||
                        I18n.t('conversations.templates.nps_thank_you', default: 'Thank you for your feedback!')

    # Remove any signature patterns that might have been added
    thank_you_message = thank_you_message.gsub(/\*\*:\s*/, '').gsub(/\n\n--\s*\n\n\*\*:.*$/m, '').strip

    conversation = nps_response.conversation
    # Create message without signature by setting content_attributes to skip signature
    conversation.messages.create!(
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :outgoing,
      content_type: :text,
      content: thank_you_message,
      content_attributes: { skip_signature: true }
    )
  end

  MAX_INVALID_RETRIES = 2

  # Cap retries: count incoming messages after the NPS survey that didn't produce a valid score.
  # After 2 failed attempts, stop sending "invalid response" to avoid annoying the customer.
  def retry_count_within_limit?(nps_response)
    nps_message_id = nps_response.metadata&.dig('message_id')
    return true unless nps_message_id

    failed_attempts = message.conversation.messages
                             .where(message_type: :incoming)
                             .where('id > ?', nps_message_id)
                             .where('id < ?', message.id)
                             .count
    failed_attempts < MAX_INVALID_RETRIES
  end

  # Short messages that look like failed NPS attempts (number out of range, single char, "?", "abc", etc.)
  # We send "invalid response" only for these — not for normal conversation messages.
  # Fonte unica compartilhada com o ReopenGuard (NpsSurveys::ScoreValidator).
  def looks_like_nps_attempt?
    NpsSurveys::ScoreValidator.looks_like_failed_attempt?(message.content)
  end

  def send_invalid_response_message(nps_response)
    inbox = nps_response.inbox
    nps_config = inbox.nps_config || {}
    invalid_message = nps_config['invalid_response_message'] ||
                      I18n.t('conversations.templates.nps_invalid_response',
                             default: 'Please respond with a number from 0 to 10.')

    conversation = nps_response.conversation
    conversation.messages.create!(
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :outgoing,
      content_type: :text,
      content: invalid_message
    )
  end
end
