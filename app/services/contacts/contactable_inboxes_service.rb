class Contacts::ContactableInboxesService
  pattr_initialize [:contact!]

  def get
    account = contact.account
    account.inboxes.filter_map { |inbox| get_contactable_inbox(inbox) }
  end

  private

  def get_contactable_inbox(inbox)
    case inbox.channel_type
    when 'Channel::TwilioSms'
      twilio_contactable_inbox(inbox)
    when 'Channel::Whatsapp'
      whatsapp_contactable_inbox(inbox)
    when 'Channel::Sms'
      sms_contactable_inbox(inbox)
    when 'Channel::Email'
      email_contactable_inbox(inbox)
    when 'Channel::Api'
      api_contactable_inbox(inbox)
    when 'Channel::WebWidget'
      website_contactable_inbox(inbox)
    end
  end

  def website_contactable_inbox(inbox)
    latest_contact_inbox = inbox.contact_inboxes.where(contact: @contact).last
    return unless latest_contact_inbox
    # FIXME : change this when multiple conversations comes in
    return if latest_contact_inbox.conversations.present?

    { source_id: latest_contact_inbox.source_id, inbox: inbox }
  end

  def api_contactable_inbox(inbox)
    latest_contact_inbox = inbox.contact_inboxes.where(contact: @contact).last
    source_id = latest_contact_inbox&.source_id || SecureRandom.uuid

    { source_id: source_id, inbox: inbox }
  end

  def email_contactable_inbox(inbox)
    return if @contact.email.blank?

    { source_id: @contact.email, inbox: inbox }
  end

  def whatsapp_contactable_inbox(inbox)
    phone_number = effective_whatsapp_phone_number
    return if phone_number.blank?

    # Remove the plus since thats the format 360 dialog uses
    { source_id: phone_number.delete('+'), inbox: inbox }
  end

  def sms_contactable_inbox(inbox)
    return if @contact.phone_number.blank?

    { source_id: @contact.phone_number, inbox: inbox }
  end

  def twilio_contactable_inbox(inbox)
    case inbox.channel.medium
    when 'sms'
      return if @contact.phone_number.blank?

      { source_id: @contact.phone_number, inbox: inbox }
    when 'whatsapp'
      phone_number = effective_whatsapp_phone_number
      return if phone_number.blank?

      { source_id: "whatsapp:#{phone_number}", inbox: inbox }
    end
  end

  def effective_whatsapp_phone_number
    fallback_phone = waha_phone_number_from_custom_attributes
    return fallback_phone if @contact.phone_number.blank?
    return fallback_phone if placeholder_phone_from_lid? && fallback_phone.present?

    @contact.phone_number
  end

  def placeholder_phone_from_lid?
    identifier = @contact.identifier.to_s
    return false unless identifier.end_with?('@lid')

    lid_digits = identifier.delete_suffix('@lid')
    return false if lid_digits.blank?

    @contact.phone_number == "+#{lid_digits}"
  end

  def waha_phone_number_from_custom_attributes # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    attributes = @contact.custom_attributes || {}
    jid = attributes['waha_whatsapp_jid'].presence
    chat_id = attributes['waha_whatsapp_chat_id'].presence

    source_jid = if whatsapp_user_jid?(jid)
                   jid
                 elsif whatsapp_user_jid?(chat_id)
                   chat_id
                 end
    return if source_jid.blank?

    clean_number = source_jid.to_s.split('@').first
    return if clean_number.blank?

    phone_number = clean_number.start_with?('+') ? clean_number : "+#{clean_number}"
    normalized_phone = Contacts::BrazilPhoneNormalizer.normalize(phone_number)
    return normalized_phone if normalized_phone.match?(/\+[1-9]\d{1,14}\z/)

    nil
  end

  def whatsapp_user_jid?(jid)
    jid.to_s.end_with?('@c.us')
  end
end

Contacts::ContactableInboxesService.prepend_mod_with('Contacts::ContactableInboxesService')
