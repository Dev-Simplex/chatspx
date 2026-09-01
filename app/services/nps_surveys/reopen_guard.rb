# frozen_string_literal: true

# Service responsible for deciding if a message is a response to an active NPS survey.
# When it returns true, the conversation should NOT be reopened (prevents reopening for valid/invalid NPS responses).
#
# Rules aligned with inbox configuration (nps_config):
# - Only considers it an "NPS response" if there is an active survey: status :sent, answered_at nil.
# - Survey expiration uses nps_config['expiration_hours'] (via NpsResponse#expired?).
# - Message must be after the survey was sent (created_at >= sent_at).
# - Content looks like a response attempt (score 0-10, or "skip" patterns), OR the
#   ResponseBuilder is going to ask the LLM about it (NpsSurveys::LlmGate).
# - When in doubt AND nobody else will decide (no LLM), does NOT block reopening.
#
# Este guard so enxerga regex; o ResponseBuilder (assincrono) enxerga regex + LLM.
# Quando o builder vai consultar o LLM, o guard segura o reopen e DEFERE a decisao a ele
# — senao a conversa reabre e dispara automacoes/flows antes do NPS reconhecer a resposta
# (ex.: "excelente" nao tem digito). Contrapartida obrigatoria: todo caminho do builder que
# conclui "nao era resposta de NPS" precisa abrir a conversa (release_conversation_for_human).
#
# Flow: Message created -> reopen_conversation -> calls prevent_reopen?(message) ->
#   if true: conversation stays resolved; NpsSurveyListener then processes and marks NPS as answered.
#
class NpsSurveys::ReopenGuard
  pattr_initialize [:message!]

  # Returns true if the message is a response to an active NPS survey and the conversation should NOT reopen.
  def prevent_reopen?
    return false unless message.incoming?
    return false unless message.conversation.resolved?

    active_nps = find_active_nps_response
    return false unless active_nps

    return false if nps_expired_or_message_before_survey?(active_nps)
    return false if agent_responded_after_nps?(active_nps)

    response_to_survey?
  end

  private

  # Reconhece a mensagem como resposta a pesquisa por regex (nota valida ou tentativa invalida
  # obvia) ou, quando o regex nao ve nada, porque o ResponseBuilder VAI consultar o LLM sobre
  # ela (LlmGate) — ai o guard segura o reopen e defere a decisao a ele.
  def response_to_survey?
    content_looks_like_nps_response? ||
      content_looks_like_wrong_or_skip_nps_attempt? ||
      NpsSurveys::LlmGate.will_attempt?(inbox: message.inbox, text: content)
  end

  delegate :conversation, :content, :content_attributes, :created_at, to: :message

  def find_active_nps_response
    conversation.nps_responses
                .where(status: :sent, answered_at: nil)
                .order(created_at: :desc)
                .first
  end

  def agent_responded_after_nps?(active_nps)
    nps_message_id = active_nps.metadata&.dig('message_id')
    return false unless nps_message_id

    # Mesma query do ResponseBuilder — os dois lados TEM que concordar (ver cabecalho).
    # content_attributes e JSON serializado como STRING: ver Message::CONTENT_ATTRIBUTES_JSON.
    conversation.messages
                .where(message_type: :outgoing)
                .where('id > ?', nps_message_id)
                .where("COALESCE(#{Message::CONTENT_ATTRIBUTES_JSON} ->> 'nps_survey', '') <> 'true'")
                .exists?
  end

  def nps_expired_or_message_before_survey?(active_nps)
    return true if active_nps.expired?
    return true if active_nps.sent_at.present? && created_at.present? && created_at < active_nps.sent_at

    false
  end

  # Widget sends score via content_attributes; channels (WhatsApp etc.) send text in content.
  def content_looks_like_nps_response?
    return true if content_attributes.dig('submitted_values', 'nps_response', 'score').present?

    normalized = normalize_content(content)
    return true if NpsSurveys::ScoreValidator.validate_and_extract(normalized).present?
    return true if nps_score_like_content?(normalized)

    false
  end

  # Invalid or "skip" responses should also not reopen (e.g., "11", "don't know", "?", "abc").
  # Fonte unica compartilhada com o ResponseBuilder (NpsSurveys::ScoreValidator).
  def content_looks_like_wrong_or_skip_nps_attempt?(text = content)
    NpsSurveys::ScoreValidator.looks_like_failed_attempt?(text)
  end

  def nps_score_like_content?(normalized)
    return false if normalized.blank?

    # Delegate to ScoreValidator — single source of truth for score extraction
    NpsSurveys::ScoreValidator.validate_and_extract(normalized).present?
  end

  # Remove invisible characters and normalize encoding for reliable detection (e.g., "10" with zero-width chars).
  def normalize_content(text)
    return '' if text.blank?

    text.to_s
        .encode('UTF-8', invalid: :replace, undef: :replace)
        .strip
        .gsub(/[\u200B-\u200D\uFEFF]/, '')
  end
end
