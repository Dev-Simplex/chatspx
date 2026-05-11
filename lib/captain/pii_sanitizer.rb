module Captain::PiiSanitizer
  # Order matters: more specific (CNPJ, phone) before broader (CPF/card)
  # so that broader matches don't "steal" the digits. Phone has no \b on
  # the left because `+` isn't a word char.
  PATTERNS = {
    cnpj: [%r{\b\d{2}\.?\d{3}\.?\d{3}/?\d{4}-?\d{2}\b}, '[CNPJ]'],
    phone_br: [/(?:\+?55\s?)?\(?\b\d{2}\)?\s?9?\d{4}-?\d{4}\b/, '[TELEFONE]'],
    cpf: [/\b\d{3}\.?\d{3}\.?\d{3}-?\d{2}\b/, '[CPF]'],
    card: [/\b(?:\d[ -]*?){13,19}\b/, '[CARTAO]'],
    email: [/\b[\w._%+-]+@[\w.-]+\.[A-Za-z]{2,}\b/, '[EMAIL]'],
    cep: [/\b\d{5}-?\d{3}\b/, '[CEP]']
  }.freeze

  DEFAULT_TYPES = %i[cnpj phone_br cpf card].freeze

  module_function

  # Returns a copy of `text` with PII patterns redacted by their masks.
  # Defense-in-depth pair with the frontend `sanitizePII.js` — the backend
  # masks again before injecting messages into LLM prompts so PII never
  # reaches the upstream provider even if the frontend is bypassed.
  def sanitize(text, enabled_types: DEFAULT_TYPES)
    return text if text.blank?

    result = text.dup
    enabled_types.each do |type|
      regex, mask = PATTERNS[type]
      next unless regex

      result = result.gsub(regex) do |match|
        next match unless should_mask?(type, match)

        mask
      end
    end
    result
  end

  def valid_luhn?(num)
    return false unless num.match?(/\A\d{13,19}\z/)

    sum = 0
    alt = false
    num.reverse.each_char do |c|
      n = c.to_i
      if alt
        n *= 2
        n -= 9 if n > 9
      end
      sum += n
      alt = !alt
    end
    (sum % 10).zero?
  end

  def should_mask?(type, match)
    case type
    when :card
      digits = match.gsub(/[ -]/, '')
      valid_luhn?(digits)
    when :cpf
      digits = match.gsub(/\D/, '')
      # Reject all-same-digit fake CPFs (00000000000, 11111111111, ...)
      !/^(\d)\1+$/.match?(digits)
    else
      true
    end
  end
end
