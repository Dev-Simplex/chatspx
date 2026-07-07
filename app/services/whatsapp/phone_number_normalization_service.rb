# Service to handle phone number normalization for WhatsApp messages
# Currently supports Brazil and Argentina phone number format variations
# Supports both WhatsApp Cloud API and Twilio WhatsApp providers
class Whatsapp::PhoneNumberNormalizationService
  def initialize(inbox)
    @inbox = inbox
  end

  # @param raw_number [String] The phone number in provider-specific format
  #   - Cloud: "5541988887777" (clean number)
  #   - Twilio: "whatsapp:+5541988887777" (prefixed format)
  # @param provider [Symbol] :cloud or :twilio
  # @return [String] Normalized source_id in provider format or original if not found
  def normalize_and_find_contact_by_provider(raw_number, provider)
    # Extract clean number based on provider format
    clean_number = extract_clean_number(raw_number, provider)

    # Find appropriate normalizer for the country
    normalizer = find_normalizer_for_country(clean_number)
    return raw_number unless normalizer

    # Try every known variant of the number (e.g., Brazil 12d/13d) so we
    # reuse an existing ContactInbox regardless of how it was originally stored.
    matches = normalizer.variants(clean_number).filter_map do |variant|
      find_existing_contact_inbox(format_for_provider(variant, provider))
    end.uniq

    return raw_number if matches.empty?
    # Common case (single ContactInbox): identical to the historical behaviour,
    # keeping the hot path (every inbound WhatsApp message hits this) untouched.
    return matches.first.source_id if matches.one?

    # Duplicate fichas (e.g. ninth-digit legacy + current forms of the same
    # number): route to the ContactInbox whose conversation is most recent —
    # the "live thread" — instead of whichever variant happened to match first.
    best = matches.max_by do |contact_inbox|
      contact_inbox.conversations.maximum(:created_at) || contact_inbox.created_at
    end
    best.source_id
  end

  private

  attr_reader :inbox

  def find_normalizer_for_country(waid)
    NORMALIZERS.map(&:new)
               .find { |normalizer| normalizer.handles_country?(waid) }
  end

  def find_existing_contact_inbox(normalized_waid)
    inbox.contact_inboxes.find_by(source_id: normalized_waid)
  end

  # Extract clean number from provider-specific format
  def extract_clean_number(raw_number, provider)
    case provider
    when :twilio
      raw_number.gsub(/^whatsapp:\+/, '') # Remove prefix: "whatsapp:+5541988887777" → "5541988887777"
    else
      raw_number # Default fallback for unknown providers
    end
  end

  # Format normalized number for provider-specific storage
  def format_for_provider(clean_number, provider)
    case provider
    when :twilio
      "whatsapp:+#{clean_number}" # Add prefix: "5541988887777" → "whatsapp:+5541988887777"
    else
      clean_number # Default for :cloud and unknown providers: "5541988887777"
    end
  end

  NORMALIZERS = [
    Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer,
    Whatsapp::PhoneNormalizers::ArgentinaPhoneNormalizer
  ].freeze
end
