require 'bigdecimal'

# Explicit normalization cases correspond to the persisted type enum.
# rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
module Captain::Evidence::Normalizer
  module_function

  def call(value, type)
    raise ArgumentError, 'missing value' if value.nil?

    case type.to_s
    when 'money' then decimal(value).to_s('F')
    when 'decimal'
      number = BigDecimal(value.to_s.tr(',', '.'))
      raise ArgumentError, 'non-finite decimal' unless number.finite?

      number.to_s('F')
    when 'id', 'text', 'time' then value.to_s.strip
    when 'phone'
      digits = value.to_s.gsub(/\D/, '')
      raise ArgumentError, 'invalid phone' unless digits.length.between?(8, 15)

      digits
    when 'boolean'
      return value if [true, false].include?(value)
      return true if %w[sim true].include?(value.to_s.downcase.strip)
      return false if %w[nao não false].include?(value.to_s.downcase.strip)

      raise ArgumentError, 'unknown boolean'
    when 'integer'
      Integer(value.to_s, 10).to_s
    else raise ArgumentError, "unsupported type: #{type}"
    end
  end

  # API decimals and PT-BR presentation. No float arithmetic, no percent tolerance.
  def decimal(value)
    currency = value.to_s.match?(/\AR\$/i)
    text = value.to_s.strip.sub(/\AR\$\s*/i, '').delete(' ')
    multiplier = if text.sub!(/\s*(?:milh(?:ão|ões|oes))\z/i, '')
                   1_000_000
                 elsif text.sub!(/\s*mil\z/i, '')
                   1000
                 else
                   1
                 end
    text = text.delete('.').tr(',', '.') if text.include?(',')
    text = text.delete('.') if currency && text.match?(/\A[+-]?\d{1,3}(?:\.\d{3})+\z/)
    raise ArgumentError, 'invalid decimal' unless text.match?(/\A[+-]?\d+(?:\.\d+)?\z/)

    BigDecimal(text) * multiplier
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
