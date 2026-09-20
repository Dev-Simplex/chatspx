# Observation and its failure containment are one boundary; callers never enforce its verdict.
# rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
class Captain::Evidence::Shadow
  def self.enabled?(assistant)
    assistant&.account&.custom_attributes&.[]('captain_fact_guard_shadow') == true
  end

  def self.with_run(conversation, assistant)
    scope = prepare_scope(conversation, assistant)
    return yield unless scope

    Captain::Evidence::Context.set(scope: scope, publication_path: 'response') do
      capture_quotes(scope)
      yield
    end
  end

  def self.capture_quotes(scope)
    Captain::Evidence::Sources.quotes(scope.conversation.messages.find_by(id: scope.turn_id))
  rescue StandardError => e
    scope.unavailable = true
    Captain::Evidence::Telemetry.emit(**scope.metadata, publication_path: 'response', decision: 'would_block',
                                                        reason: 'ledger_unavailable', error_class: e.class.name)
  end

  def self.prepare_scope(conversation, assistant)
    build_scope(conversation, assistant) if enabled?(assistant)
  rescue StandardError => e
    Captain::Evidence::Telemetry.emit(account_id: conversation.account_id, captain_assistant_id: assistant.id,
                                      decision: 'would_block', reason: 'scope_unavailable', error_class: e.class.name)
    nil
  end

  def self.build_scope(conversation, assistant)
    Captain::Evidence::Scope.new(conversation: conversation, assistant: assistant)
  end

  def self.observe(text:, stage:, message: nil, unsupported: false)
    scope = Captain::Evidence::Context.scope
    return unless scope

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    claims = Captain::Evidence::ClaimExtractor.new(scope).extract(text)
    verdicts = Captain::Evidence::FactGuard.new(Captain::Evidence::Ledger.new(scope)).evaluate(claims)
    # Free prose cannot be certified by a finite grammar. Coverage remains visible even with all matched claims.
    verdicts << { fact_type: 'coverage', decision: 'unassessed', reason: unsupported ? 'binary_or_external_payload' : 'free_text_remainder',
                  evidence_ids: [] }
    attrs = scope.metadata.merge(message_id: message&.id, publication_id: scope.publication_id || SecureRandom.uuid,
                                 publication_path: Captain::Evidence::Context.publication_path || 'response', stage: stage,
                                 extractor_version: Captain::Evidence::ClaimExtractor::VERSION,
                                 payload_digest: Digest::SHA256.hexdigest(text.to_s), created_at: Time.current,
                                 duration_ms: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000)
    Captain::FactGuardEvent.transaction(requires_new: true) do
      # Append-only telemetry, built by the guard; batch avoids a round trip per claim.
      Captain::FactGuardEvent.insert_all!(verdicts.map { |verdict| attrs.merge(claim: {}, **verdict) }) # rubocop:disable Rails/SkipsModelValidations
    end
    metrics = attrs.except(:payload_digest, :message_id).merge(decisions: verdicts.map { |v| v.except(:claim) })
    metrics[:duration_ms] = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
    Captain::Evidence::Telemetry.emit(**metrics)
    verdicts
  rescue StandardError => e
    scope.unavailable = true if scope
    Captain::Evidence::Telemetry.emit(**(scope&.metadata || {}), publication_path: Captain::Evidence::Context.publication_path,
                                                                 stage: stage, decision: 'would_block', reason: 'ledger_unavailable',
                                                                 error_class: e.class.name)
    Rails.logger.warn("[fact_guard] event_unavailable account=#{scope&.account_id} assistant=#{scope&.assistant_id} " \
                      "path=#{Captain::Evidence::Context.publication_path} stage=#{stage} error=#{e.class.name}")
    [{ fact_type: 'coverage', decision: 'would_block', reason: 'ledger_unavailable', evidence_ids: [] }]
  end

  def self.message(message)
    return unless message.outgoing? && !message.private?

    scope = Captain::Evidence::Context.scope
    return unless scope

    unless scope.account_id == message.account_id && scope.conversation_id == message.conversation_id
      Captain::Evidence::Telemetry.emit(**scope.metadata, publication_path: Captain::Evidence::Context.publication_path,
                                                          decision: 'unassessed', reason: 'destination_context_mismatch')
      return
    end

    payload = [message.content, *visible_text(message.content_attributes.slice('cards', 'interactive_payload'))].join("\n")
    observe(text: payload, stage: 'publication', message: message,
            unsupported: message.attachments.any? || message.additional_attributes['template_params'].present?)
  rescue StandardError => e
    Captain::Evidence::Telemetry.emit(account_id: message.account_id, conversation_id: message.conversation_id,
                                      decision: 'would_block', reason: 'publication_observer_unavailable', error_class: e.class.name)
    nil
  end

  # Ignore renderer indices; inspect user-visible card text rather than the JSON syntax.
  def self.visible_text(node)
    case node
    when Hash
      node.flat_map { |key, value| %w[text title subtitle description].include?(key) && value.is_a?(String) ? [value] : visible_text(value) }
    when Array then node.flat_map { |value| visible_text(value) }
    else []
    end
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
