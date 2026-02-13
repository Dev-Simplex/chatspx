# frozen_string_literal: true

# Serviço responsável por decidir se uma mensagem é resposta a uma pesquisa NPS ativa.
# Quando retorna true, a conversa NÃO deve ser reaberta (evita reabertura por resposta válida/inválida ao NPS).
#
# Regras alinhadas à configuração da caixa de entrada (nps_config):
# - Só considera "resposta NPS" se existir pesquisa ativa: status :sent, answered_at nil.
# - Expiração da pesquisa usa nps_config['expiration_hours'] (via NpsResponse#expired?).
# - Mensagem deve ser posterior ao envio da pesquisa (created_at >= sent_at).
# - Conteúdo deve parecer claramente uma tentativa de resposta (nota 0-10, ou padrões de "pular").
# - Na dúvida, NÃO bloqueia reabertura (reabre para o cliente poder ser atendido).
#
# Fluxo: Mensagem criada → reopen_conversation → chama prevent_reopen?(message) →
#   se true: conversa permanece resolvida; NpsSurveyListener depois processa e marca NPS como respondido.
#
class NpsSurveys::ReopenGuard
  pattr_initialize [:message!]

  # Retorna true se a mensagem for resposta a uma pesquisa NPS ativa e a conversa NÃO deve reabrir.
  def prevent_reopen?
    return false unless message.incoming?
    return false unless message.conversation.resolved?

    active_nps = find_active_nps_response
    return false unless active_nps

    return false if nps_expired_or_message_before_survey?(active_nps)
    return true if content_looks_like_nps_response?
    return true if content_looks_like_wrong_or_skip_nps_attempt?

    false
  end

  private

  delegate :conversation, :content, :content_attributes, :created_at, to: :message

  def find_active_nps_response
    conversation.nps_responses
                .where(status: :sent, answered_at: nil)
                .order(created_at: :desc)
                .first
  end

  def nps_expired_or_message_before_survey?(active_nps)
    return true if active_nps.expired?
    return true if active_nps.sent_at.present? && created_at.present? && created_at < active_nps.sent_at

    false
  end

  # Widget envia score em content_attributes; canais (WhatsApp etc.) enviam texto no content.
  def content_looks_like_nps_response?
    return true if content_attributes.dig('submitted_values', 'nps_response', 'score').present?

    normalized = normalize_content(content)
    return true if NpsSurveys::ScoreValidator.validate_and_extract(normalized).present?
    return true if nps_score_like_content?(normalized)

    false
  end

  # Respostas inválidas ou de "pular" também não devem reabrir (ex.: "11", "não sei", "?").
  def content_looks_like_wrong_or_skip_nps_attempt?(text = content)
    looks_like_wrong_nps_attempt_only?(normalize_content(text))
  end

  def nps_score_like_content?(normalized)
    return false if normalized.blank?

    return true if normalized.match?(/^\s*(10|[0-9])\s*!*\s*$/)
    return true if normalized.match?(/\b(10|[0-9])\s*\/\s*10\b/)
    return true if normalized.match?(/\b(10|[0-9])\s*de\s*10\b/i)

    keyword_present = normalized.match?(/\b(nota|score|rating|estrelas?|stars?)\b/i)
    keyword_present && normalized.match?(/\b(10|[0-9])\b/)
  end

  def looks_like_wrong_nps_attempt_only?(normalized)
    return false if normalized.blank?

    # Número fora de 0-10 (ex.: "100", "11", "-1")
    if normalized.match?(/^\s*-?\d+\s*$/)
      num = normalized.to_i
      return true unless (0..10).cover?(num)
    end

    return false if normalized.length > 25

    short_skip_patterns = [
      /\A(n[ãa]o\s*)?sei\z/i,
      /\An\/a\z/i,
      /\A\?+\z/,
      /\A\.+\z/,
      /\A(nao|não)\z/i,
      /\Aabc\z/i,
      /\A[a-z]\z/i,
      /\A[\s\?\.,!\-]+\z/
    ]
    short_skip_patterns.any? { |pattern| normalized.match?(pattern) }
  end

  # Remove caracteres invisíveis e normaliza encoding para detecção confiável (ex.: "10" com zero-width).
  def normalize_content(text)
    return '' if text.blank?

    text.to_s
        .encode('UTF-8', invalid: :replace, undef: :replace)
        .strip
        .gsub(/[\u200B-\u200D\uFEFF]/, '')
  end
end
