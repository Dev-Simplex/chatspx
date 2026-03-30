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

  private

  def normalize(text)
    self.class.normalize(text)
  end

  def extract_from_text # rubocop:disable Metrics/MethodLength
    # Try direct integer match first
    integer_match = @input.match(/^\s*(\d+)\s*$/)
    return integer_match[1].to_i if integer_match && valid_score?(integer_match[1].to_i)

    # Try patterns like "10!!!", "nota 9", "8/10", "score: 7"
    patterns = [
      /(\d+)\s*!+/,                    # "10!!!"
      /nota\s*(\d+)/i,                 # "nota 9"
      %r{(\d+)\s*/\s*10}i,              # "8/10"
      /score[:\s]+(\d+)/i,             # "score: 7"
      /(\d+)\s*de\s*10/i,              # "8 de 10"
      /rating[:\s]+(\d+)/i,             # "rating: 6"
      /(\d+)\s*estrelas?/i,            # "9 estrelas"
      /(\d+)\s*stars?/i,               # "9 stars"
      %r{(\d+)\s*/\s*(\d+)},            # "8/10" (capture first number)
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
    score.between?(0, 10)
  end
end
