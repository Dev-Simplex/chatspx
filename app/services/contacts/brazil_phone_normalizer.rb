# Handles Brazil phone number normalization for contacts
# ref: https://github.com/chatwoot/chatwoot/issues/5840
#
# Brazil changed its mobile number system by adding a "9" prefix to existing numbers.
# This normalizer adds the "9" digit if the number is 12 digits (making it 13 digits total)
# to match the new format: +55 + DDD + 9 + number
class Contacts::BrazilPhoneNormalizer
  DDD_LENGTH = 2
  # Expected length after +55 when normalized: DDD (2) + 9 (1) + number (8) = 11 digits
  # Length without 9: DDD (2) + number (8) = 10 digits
  EXPECTED_LENGTH_WITHOUT_9 = 10
  EXPECTED_LENGTH_WITH_9 = 11

  def self.normalize(phone_number)
    new(phone_number).normalize
  end

  def initialize(phone_number)
    @phone_number = phone_number
  end

  def normalize
    return @phone_number unless brazilian_number?
    return @phone_number if already_normalized?

    add_ninth_digit
  end

  private

  attr_reader :phone_number

  def brazilian_number?
    return false if phone_number.blank?
    return false unless phone_number.start_with?('+55')
    return false unless valid_e164_format?

    true
  end

  def valid_e164_format?
    phone_number.match?(/\+[1-9]\d{1,14}\z/)
  end

  def already_normalized?
    # Remove +55 to check the length of DDD + number
    # If it has 11+ digits, it's already normalized (has the 9)
    # If it has exactly 10 digits, it needs the 9 added
    number_after_country_code = phone_number[3..]
    number_after_country_code.length >= EXPECTED_LENGTH_WITH_9
  end

  def add_ninth_digit
    # Format: +55DDDXXXXXXXX (10 digits after +55) -> +55DDD9XXXXXXXX (11 digits after +55)
    # Extract: +55 (3 chars), DDD (2 chars), rest (8 digits without 9)
    country_code_part = phone_number[0, 3] # +55
    ddd = phone_number[3, DDD_LENGTH] # DDD
    number_part = phone_number[5..] # Rest of the number (should be 8 digits)

    "#{country_code_part}#{ddd}9#{number_part}"
  end
end

