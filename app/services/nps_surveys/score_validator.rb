# Validates and extracts NPS score (0-10) from text. Used by ResponseBuilder and ReopenGuard.
# Normalizes content (strip + invisible characters) to recognize "10" even with encoding/extra characters.
class NpsSurveys::ScoreValidator
  def self.validate_and_extract(input)
    new(input).validate_and_extract
  end

  def initialize(input)
    @input = normalize(input)
  end

  def self.normalize(text)
    return '' if text.blank?

    text.to_s
        .encode('UTF-8', invalid: :replace, undef: :replace)
        .strip
        .gsub(/[\u200B-\u200D\uFEFF]/, '')
  end

  def validate_and_extract
    return extract_from_text if @input.present?

    nil
  end

  # Fonte unica para "isto parece uma tentativa (falha) de responder o NPS":
  # numero fora de 0-10, ou mensagem curta de confusao/pulo ("abc", "?", "nao sei").
  # Usada por ResponseBuilder (para enviar o aviso de resposta invalida) e por
  # ReopenGuard (para nao reabrir a conversa). Manter os dois em sincronia.
  SHORT_SKIP_PATTERNS = [
    /\A(n[ãa]o\s*)?sei\z/i,
    %r{\An/a\z}i,
    /\A\?+\z/,
    /\A\.+\z/,
    /\A(nao|não)\z/i,
    /\Aabc\z/i,
    /\A[a-z]\z/i,
    /\A[\s\?\.,!\-]+\z/
  ].freeze

  def self.looks_like_failed_attempt?(text)
    normalized = normalize(text)
    return false if normalized.blank?

    # Numero puro fora de 0-10 (ex.: "11", "100", "-1")
    return !(0..10).cover?(normalized.to_i) if normalized.match?(/\A\s*-?\d+\s*\z/)
    return false if normalized.length > 25

    SHORT_SKIP_PATTERNS.any? { |pattern| normalized.match?(pattern) }
  end

  private

  def normalize(text)
    self.class.normalize(text)
  end

  def extract_from_text
    extract_bare_number || extract_nota_pattern || extract_minha_nota ||
      extract_score_at_start || extract_quoted_score || extract_short_pattern
  end

  def extract_bare_number
    bare_match = @input.match(/\A\s*0?(10|[0-9])\s*[!.]*\s*\z/)
    bare_match&.captures&.first&.to_i
  end

  def extract_nota_pattern
    nota_match = @input.match(/\bn[ao]t[ao]\s*[,:]?\s*(10|[0-9])\b/i)
    nota_match&.captures&.first&.to_i
  end

  def extract_minha_nota
    minha_match = @input.match(/\bminha\s*nota\s*[ée:\s]\s*(10|[0-9])\b/i)
    minha_match&.captures&.first&.to_i
  end

  # Score at START of message followed by non-digit — customer typed score then comment
  def extract_score_at_start
    start_match = @input.match(/\A\s*(10|[0-9])\s*[,\s!.]\s*\S/m)
    start_match&.captures&.first&.to_i
  end

  # WhatsApp quoted name + score on next line: "**Nome**:\n10"
  def extract_quoted_score
    quoted_match = @input.match(/:\s*\n\s*(10|[0-9])\s*\z/m)
    quoted_match&.captures&.first&.to_i
  end

  SHORT_PATTERNS = [
    %r{\A\s*(10|[0-9])\s*/\s*10\s*\z}i,   # "8/10"
    /\A\s*(10|[0-9])\s*de\s*10\s*\z/i,    # "8 de 10"
    /\Ascore[:\s]+(10|[0-9])\s*\z/i,      # "score: 7"
    /\Arating[:\s]+(10|[0-9])\s*\z/i,     # "rating: 6"
    /\A\s*(10|[0-9])\s*estrelas?\s*\z/i,  # "9 estrelas"
    /\A\s*(10|[0-9])\s*stars?\s*\z/i      # "9 stars"
  ].freeze

  def extract_short_pattern
    return nil if @input.length > 30

    SHORT_PATTERNS.each do |pattern|
      match = @input.match(pattern)
      return match[1].to_i if match
    end
    nil
  end

  def valid_score?(score)
    score.between?(0, 10)
  end
end
