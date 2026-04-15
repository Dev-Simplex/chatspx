# Base class for country-specific phone number normalizers
# Each country normalizer should inherit from this class and implement:
# - country_code_pattern: regex to identify the country code
# - normalize: logic to convert phone number to normalized format for contact lookup
class Whatsapp::PhoneNormalizers::BasePhoneNormalizer
  def handles_country?(waid)
    waid.match(country_code_pattern)
  end

  def normalize(waid)
    raise NotImplementedError, 'Subclasses must implement #normalize'
  end

  # Returns every equivalent waid representation this normalizer knows about
  # (e.g., Brazilian numbers with and without the ninth digit).
  # Subclasses can override to expose more than one variant.
  def variants(waid)
    [waid, normalize(waid)].compact.uniq
  end

  private

  def country_code_pattern
    raise NotImplementedError, 'Subclasses must implement #country_code_pattern'
  end
end
