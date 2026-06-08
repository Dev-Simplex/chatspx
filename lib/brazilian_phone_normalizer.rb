# frozen_string_literal: true

# Normaliza números de telefone BR para formato E.164 com '9' adicionado em celulares.
# Casos cobertos:
#   "5511999999999" → "5511999999999" (já normalizado, 13 dígitos)
#   "551199999999"  → "5511999999999" (12 dígitos, insere '9' como 5º dígito após DDI)
#   "11999999999"   → "5511999999999" (sem DDI, adiciona '55')
#   "1199999999"    → "5511999999999" (sem DDI e sem '9')
class BrazilianPhoneNormalizer
  def self.call(phone) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return nil if phone.nil? || phone.to_s.strip.empty?

    digits = phone.to_s.gsub(/\D/, '')
    return nil if digits.empty?
    return digits if digits.length == 13 && digits.start_with?('55')

    digits = "55#{digits}" unless digits.start_with?('55')
    digits.insert(4, '9') if digits.length == 12 && digits[4] != '9'

    digits
  end
end
