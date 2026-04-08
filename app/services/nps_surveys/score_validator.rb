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
    # 1. Bare number (with optional zero-padding): "8", "10", "09", "08"
    bare_match = @input.match(/\A\s*0?(10|[0-9])\s*[!.]*\s*\z/)
    return bare_match[1].to_i if bare_match

    # 2. "nota/nata X" anywhere — explicit NPS intent regardless of message length
    nota_match = @input.match(/\bn[ao]t[ao]\s*[,:]?\s*(10|[0-9])\b/i)
    return nota_match[1].to_i if nota_match

    # 3. "minha nota é X" — explicit score statement
    minha_match = @input.match(/\bminha\s*nota\s*[ée:\s]\s*(10|[0-9])\b/i)
    return minha_match[1].to_i if minha_match

    # 4. Score at START of message followed by non-digit — customer typed score then comment
    #    "10 com certeza", "10 gostei muito", "0, pois me cobrou...", "10 👍"
    start_match = @input.match(/\A\s*(10|[0-9])\s*[,\s!.]\s*\S/m)
    return start_match[1].to_i if start_match

    # 5. WhatsApp quoted name + score on next line: "**Nome**:\n10"
    quoted_match = @input.match(/:\s*\n\s*(10|[0-9])\s*\z/m)
    return quoted_match[1].to_i if quoted_match

    # 6. Short messages (≤30 chars) with structured patterns
    return nil if @input.length > 30

    short_patterns = [
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
