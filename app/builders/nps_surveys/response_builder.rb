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
      handle_without_score(nps_response)
      return
    end

    process_nps_response(nps_response, score)
  end

  private

  def agent_responded_after_nps?(conversation, nps_response)
    nps_message_id = nps_response.metadata&.dig('message_id')
    return false unless nps_message_id

    # Usa all_messages — deteccao de resposta agente apos NPS deve ver historico global.
    # content_attributes e JSON serializado como STRING: ver Message::CONTENT_ATTRIBUTES_JSON.
    conversation.all_messages
                .where(message_type: :outgoing)
                .where('id > ?', nps_message_id)
                .where("COALESCE(#{Message::CONTENT_ATTRIBUTES_JSON} ->> 'nps_survey', '') <> 'true'")
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

  # Toggle + candidatura vivem no NpsSurveys::LlmGate — fonte unica compartilhada com o
  # ReopenGuard, que segura o reopen exatamente quando este caminho vai rodar.
  def extract_score_via_llm
    return nil unless NpsSurveys::LlmGate.gpt_parse_candidate?(inbox: message.inbox, text: message.content)

    NpsSurveys::ScoreLlmParser.extract(text: message.content, account: message.account)
  end

  # Notas atribuidas quando o sentimento e detectado (sem numero na mensagem).
  # Ficam nas faixas de detrator/promotor; entram no calculo do NPS (decisao do produto).
  SENTIMENT_DETRACTOR_SCORE = 3
  SENTIMENT_PROMOTER_SCORE = 9

  # Resposta sem nota explicita. Ordem (barato -> caro):
  # 1. Tentativa invalida obvia (heuristica) -> aviso; finaliza apos 3 (nao sabe avaliar).
  # 2. Classificacao por IA (atras de toggle): elogio -> promotor, insatisfacao -> detrator,
  #    outro assunto -> atendimento humano. Neutro/duvida/falha -> libera para humano.
  #
  # Invariante: o ReopenGuard segura o reopen sempre que o LlmGate diz que o LLM sera
  # consultado. Entao TODO caminho que nao trata a mensagem tem que liberar a conversa
  # aqui — senao o cliente fica preso numa conversa resolved e ninguem atende. A garantia
  # e centralizada neste `unless handled` (nao depende de lembrar em cada branch).
  def handle_without_score(nps_response)
    if looks_like_nps_attempt?
      handle_invalid_response(nps_response)
      return
    end

    release_conversation_for_human(nps_response) unless handle_ai_classification(nps_response)
  end

  # Retorna true quando a mensagem foi TRATADA como resposta de NPS (nota por sentimento
  # ou handoff). Neutro, categoria desconhecida, toggle off e falha do LLM -> false.
  def handle_ai_classification(nps_response)
    return false unless NpsSurveys::LlmGate.sentiment_candidate?(inbox: message.inbox, text: message.content)

    case classify_via_llm
    when 'negative' then process_nps_response(nps_response, SENTIMENT_DETRACTOR_SCORE, sentiment_inferred: true)
    when 'positive' then process_nps_response(nps_response, SENTIMENT_PROMOTER_SCORE, sentiment_inferred: true)
    when 'other_topic' then handoff_to_human_new_topic(nps_response)
    else return false
    end

    true
  end

  # Fail-open: erro/timeout do LLM nao pode prender o cliente numa conversa resolved
  # (o guard ja segurou o reopen contando com esta decisao) -> sem categoria, libera.
  def classify_via_llm
    NpsSurveys::ScoreLlmParser.classify(text: message.content, account: message.account)
  rescue StandardError => e
    Rails.logger.warn("[NPS] classificacao por IA falhou conv=#{message.conversation_id}: #{e.message}")
    nil
  end

  # Cliente quer tratar de outro assunto: encerra a pesquisa (nao e resposta de NPS)
  # e mantem a conversa aberta para atendimento humano.
  def handoff_to_human_new_topic(nps_response)
    nps_response.update!(status: :dismissed, dismiss_reason: 'other_topic')
    release_conversation_for_human(nps_response)
  rescue StandardError => e
    Rails.logger.warn("[NPS] handoff outro assunto conv=#{nps_response.conversation_id}: #{e.message}")
  end

  # Nao era resposta de NPS: devolve a conversa para atendimento humano. No-op quando o
  # guard nao segurou (a conversa ja reabriu sozinha via Message#reopen_conversation).
  def release_conversation_for_human(nps_response)
    conversation = nps_response.conversation
    conversation.reload
    conversation.open! if conversation.resolved?
  rescue StandardError => e
    Rails.logger.warn("[NPS] nao consegui liberar conv=#{nps_response.conversation_id} para atendimento: #{e.message}")
  end

  def valid_score?(score)
    score.is_a?(Integer) && score >= 0 && score <= 10
  end

  def process_nps_response(nps_response, score, sentiment_inferred: false)
    comment = extract_comment

    # Update NPS response first to mark it as answered
    # This prevents conversation from reopening when response_to_active_survey? is checked
    attrs = { score: score, comment: comment, status: :responded, answered_at: Time.current }
    # Marca respostas cuja nota veio de sentimento (sem numero), para auditoria/relatorio.
    attrs[:metadata] = (nps_response.metadata || {}).merge('sentiment_inferred' => true) if sentiment_inferred
    nps_response.update!(attrs)

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
    return false if band_thank_you_message(nps_response).blank?

    # Idempotencia: nao reenviar o mesmo agradecimento se ja foi enviado ha pouco
    # (evita duplicidade quando a resposta e processada 2x por corrida de eventos).
    !thank_you_already_sent?(nps_response)
  end

  def thank_you_already_sent?(nps_response)
    content = thank_you_content(nps_response)
    nps_response.conversation.messages
                .where(message_type: :outgoing, content: content)
                .exists?(['created_at >= ?', 5.minutes.ago])
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

  # Conteudo final do agradecimento (por faixa, com fallback e sem assinatura).
  def thank_you_content(nps_response)
    msg = band_thank_you_message(nps_response) ||
          I18n.t('conversations.templates.nps_thank_you', default: 'Thank you for your feedback!')
    msg.gsub(/\*\*:\s*/, '').gsub(/\n\n--\s*\n\n\*\*:.*$/m, '').strip
  end

  def send_thank_you_message(nps_response)
    thank_you_message = thank_you_content(nps_response)

    conversation = nps_response.conversation
    # skip_signature: sem assinatura; nps_survey_system: nao dismissar a pesquisa (ver NpsSurveyListener)
    conversation.messages.create!(
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :outgoing,
      content_type: :text,
      content: thank_you_message,
      content_attributes: { skip_signature: true, nps_survey_system: true }
    )
  end

  # Numero de respostas invalidas toleradas antes de encerrar a conversa.
  # Ate MAX-1 -> envia o aviso; na MAX-esima -> finaliza (nao repete a pergunta).
  MAX_INVALID_ATTEMPTS = 3

  # Roteia a resposta invalida: avisa nas primeiras tentativas e, ao atingir
  # MAX_INVALID_ATTEMPTS respostas invalidas, encerra a pesquisa e resolve a conversa.
  def handle_invalid_response(nps_response)
    attempts = invalid_attempts_count(nps_response)

    if attempts >= MAX_INVALID_ATTEMPTS
      finalize_after_invalid_attempts(nps_response)
    else
      send_invalid_response_message(nps_response)
    end
  end

  # Conta apenas as respostas RECONHECIDAS como tentativa invalida de NPS
  # (abc, "?", "nao sei", numero fora de 0-10...) pos-survey, ate a atual (inclusive).
  # Mensagem normal de conversa nao conta (ela reabre a conversa via ReopenGuard).
  def invalid_attempts_count(nps_response)
    nps_message_id = nps_response.metadata&.dig('message_id')
    scope = message.conversation.messages.where(message_type: :incoming).where('id <= ?', message.id)
    scope = scope.where('id > ?', nps_message_id) if nps_message_id

    scope.count { |m| NpsSurveys::ScoreValidator.looks_like_failed_attempt?(m.content) }
  end

  # Encerra a pesquisa apos respostas invalidas em excesso: envia a mensagem de
  # encerramento ao cliente, marca a NpsResponse como dismissed e garante a conversa
  # resolvida (nao reabre, nao reenvia pergunta).
  def finalize_after_invalid_attempts(nps_response)
    send_invalid_finalize_message(nps_response)
    nps_response.update!(status: :dismissed, dismiss_reason: 'invalid_responses')

    create_invalid_finalized_activity_message(nps_response)

    conversation = nps_response.conversation
    conversation.reload
    return unless conversation.open?

    conversation.skip_team_required_for_resolution_validation = true
    conversation.update!(status: :resolved)
  rescue StandardError => e
    Rails.logger.warn("[NPS] falha ao finalizar apos respostas invalidas conv=#{nps_response.conversation_id}: #{e.message}")
  end

  DEFAULT_INVALID_FINALIZE_MESSAGE = 'Ops, parece que não conseguimos entender a sua resposta. 😕 ' \
                                     'Para não tomarmos mais o seu tempo, estamos encerrando este atendimento por agora. Obrigado!'.freeze

  def send_invalid_finalize_message(nps_response)
    config = nps_response.inbox.nps_config || {}
    content = config['invalid_finalize_message'].presence ||
              I18n.t('conversations.templates.nps_invalid_finalize', default: DEFAULT_INVALID_FINALIZE_MESSAGE)
    return if content.blank?

    conversation = nps_response.conversation
    # nps_survey_system: nao dismissar/reprocessar a pesquisa (ver NpsSurveyListener).
    conversation.messages.create!(
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :outgoing,
      content_type: :text,
      content: content,
      content_attributes: { nps_survey_system: true }
    )
  end

  def create_invalid_finalized_activity_message(nps_response)
    content = I18n.t('conversations.activity.nps.finalized_invalid',
                     count: MAX_INVALID_ATTEMPTS,
                     default: "Pesquisa NPS encerrada apos #{MAX_INVALID_ATTEMPTS} respostas invalidas.")
    ::Conversations::ActivityMessageJob.perform_later(
      nps_response.conversation_id,
      { account_id: nps_response.account_id, inbox_id: nps_response.inbox_id, message_type: :activity, content: content }
    )
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
    # nps_survey_system: impede o NpsSurveyListener de dismissar a pesquisa (nao e agente assumindo).
    conversation.messages.create!(
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :outgoing,
      content_type: :text,
      content: invalid_message,
      content_attributes: { nps_survey_system: true }
    )
  end
end
