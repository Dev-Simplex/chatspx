# Handles Brazil phone number normalization
# ref: https://github.com/chatwoot/chatwoot/issues/5840
#
# Brazil changed its mobile number system by adding a "9" prefix to existing numbers.
# This normalizer adds the "9" digit if the number is 12 digits (making it 13 digits total)
# to match the new format: 55 + DDD + 9 + number
class Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer < Whatsapp::PhoneNormalizers::BasePhoneNormalizer
  COUNTRY_CODE_LENGTH = 2
  DDD_LENGTH = 2

  def normalize(waid)
    return waid unless handles_country?(waid)

    ddd = waid[COUNTRY_CODE_LENGTH, DDD_LENGTH]
    number = waid[COUNTRY_CODE_LENGTH + DDD_LENGTH, waid.length - (COUNTRY_CODE_LENGTH + DDD_LENGTH)]
    normalized_number = "55#{ddd}#{number}"
    normalized_number = "55#{ddd}9#{number}" if normalized_number.length != 13
    normalized_number
  end

  # Brazilian mobile numbers exist in two forms after the 2012 ninth-digit reform:
  # 12 digits (55 + DDD + 8) for legacy records and 13 digits (55 + DDD + 9 + 8) for current ones.
  # Meta's Cloud API delivers 13-digit wa_ids, so we need to match contacts stored in either form.
  def variants(waid)
    return [waid].compact.uniq unless handles_country?(waid)

    with_nine = normalize(waid)
    without_nine = strip_ninth_digit(with_nine)
    [waid, with_nine, without_nine].compact.uniq
  end

  private

  def country_code_pattern
    /^55/
  end

  def strip_ninth_digit(waid_13)
    return unless waid_13&.length == 13

    ddd = waid_13[COUNTRY_CODE_LENGTH, DDD_LENGTH]
    rest = waid_13[(COUNTRY_CODE_LENGTH + DDD_LENGTH)..]
    return unless rest&.start_with?('9')

    "55#{ddd}#{rest[1..]}"
  end
end
