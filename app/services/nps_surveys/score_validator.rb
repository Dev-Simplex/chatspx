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

  def extract_from_text
    # 1. Bare number only (entire message is just "8", "10", "0", etc.)
    bare_match = @input.match(/\A\s*(10|[0-9])\s*[!.]*\s*\z/)
    return bare_match[1].to_i if bare_match

    # 2. Short messages (≤30 chars) with explicit NPS patterns
    #    Longer messages likely contain incidental numbers, not NPS scores
    return nil if @input.length > 30

    short_patterns = [
      /\Anota\s*(10|[0-9])\s*\z/i,          # "nota 9"
      %r{\A\s*(10|[0-9])\s*/\s*10\s*\z}i,   # "8/10"
      /\A\s*(10|[0-9])\s*de\s*10\s*\z/i,    # "8 de 10"
      /\Ascore[:\s]+(10|[0-9])\s*\z/i,      # "score: 7"
      /\Arating[:\s]+(10|[0-9])\s*\z/i,     # "rating: 6"
      /\A\s*(10|[0-9])\s*estrelas?\s*\z/i,  # "9 estrelas"
      /\A\s*(10|[0-9])\s*stars?\s*\z/i      # "9 stars"
    ]

    short_patterns.each do |pattern|
      match = @input.match(pattern)
      return match[1].to_i if match
    end

    nil
  end

  def valid_score?(score)
    score.between?(0, 10)
  end
end
