# Valida e extrai nota NPS (0-10) de texto. Usado pelo ResponseBuilder e pelo ReopenGuard.
# Normaliza conteúdo (strip + caracteres invisíveis) para reconhecer "10" mesmo com encoding/caracteres extras.
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

  private

  def normalize(text)
    self.class.normalize(text)
  end

  def extract_from_text
    # Try direct integer match first
    integer_match = @input.match(/^\s*(\d+)\s*$/)
    return integer_match[1].to_i if integer_match && valid_score?(integer_match[1].to_i)

    # Try patterns like "10!!!", "nota 9", "8/10", "score: 7"
    patterns = [
      /(\d+)\s*!+/,                    # "10!!!"
      /nota\s*(\d+)/i,                 # "nota 9"
      /(\d+)\s*\/\s*10/i,              # "8/10"
      /score[:\s]+(\d+)/i,             # "score: 7"
      /(\d+)\s*de\s*10/i,              # "8 de 10"
      /rating[:\s]+(\d+)/i,             # "rating: 6"
      /(\d+)\s*estrelas?/i,            # "9 estrelas"
      /(\d+)\s*stars?/i,               # "9 stars"
      /(\d+)\s*\/\s*(\d+)/,            # "8/10" (capture first number)
      /(\d+)/                           # Any number
    ]

    patterns.each do |pattern|
      match = @input.match(pattern)
      next unless match

      score = match[1].to_i
      return score if valid_score?(score)
    end

    nil
  end

  def valid_score?(score)
    score >= 0 && score <= 10
  end
end
