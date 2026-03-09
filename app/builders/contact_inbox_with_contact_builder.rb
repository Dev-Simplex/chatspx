# This Builder will create a contact and contact inbox with specified attributes.
# If an existing identified contact exisits, it will be returned.
# for contact inbox logic it uses the contact inbox builder

class ContactInboxWithContactBuilder
  pattr_initialize [:inbox!, :contact_attributes!, :source_id, :hmac_verified]

  def perform
    find_or_create_contact_and_contact_inbox
  # in case of race conditions where contact is created by another thread
  # we will try to find the contact and create a contact inbox
  rescue ActiveRecord::RecordNotUnique
    find_or_create_contact_and_contact_inbox
  end

  def find_or_create_contact_and_contact_inbox
    @contact_inbox = inbox.contact_inboxes.find_by(source_id: source_id) if source_id.present?
    return @contact_inbox if @contact_inbox

    migrated = find_and_migrate_waha_lid_to_pn if waha_api_inbox? && source_id.present?
    return migrated if migrated

    ActiveRecord::Base.transaction(requires_new: true) do
      build_contact_with_contact_inbox
    end
    update_contact_avatar(@contact) unless @contact.avatar.attached?
    @contact_inbox
  end

  private

  def build_contact_with_contact_inbox
    @contact = find_contact || create_contact
    @contact_inbox = create_contact_inbox
  end

  def account
    @account ||= inbox.account
  end

  def create_contact_inbox
    ContactInboxBuilder.new(
      contact: @contact,
      inbox: @inbox,
      source_id: @source_id,
      hmac_verified: hmac_verified
    ).perform
  end

  def update_contact_avatar(contact)
    ::Avatar::AvatarFromUrlJob.perform_later(contact, contact_attributes[:avatar_url]) if contact_attributes[:avatar_url]
  end

  def create_contact
    account.contacts.create!(
      name: contact_attributes[:name] || ::Haikunator.haikunate(1000),
      phone_number: contact_attributes[:phone_number],
      email: contact_attributes[:email],
      identifier: contact_attributes[:identifier],
      additional_attributes: contact_attributes[:additional_attributes],
      custom_attributes: contact_attributes[:custom_attributes]
    )
  end

  def find_contact
    contact = find_contact_by_identifier(contact_attributes[:identifier])
    contact ||= find_contact_by_email(contact_attributes[:email])
    contact ||= find_contact_by_phone_number(contact_attributes[:phone_number])
    contact ||= find_contact_by_instagram_source_id(source_id) if instagram_channel?

    contact
  end

  def instagram_channel?
    inbox.channel_type == 'Channel::Instagram'
  end

  # There might be existing contact_inboxes created through Channel::FacebookPage
  # with the same Instagram source_id. New Instagram interactions should create fresh contact_inboxes
  # while still reusing contacts if found in Facebook channels so that we can create
  # new conversations with the same contact.
  def find_contact_by_instagram_source_id(instagram_id)
    return if instagram_id.blank?

    existing_contact_inbox = ContactInbox.joins(:inbox)
                                         .where(source_id: instagram_id)
                                         .where(
                                           'inboxes.channel_type = ? AND inboxes.account_id = ?',
                                           'Channel::FacebookPage',
                                           account.id
                                         ).first

    existing_contact_inbox&.contact
  end

  def find_contact_by_identifier(identifier)
    return if identifier.blank?

    account.contacts.find_by(identifier: identifier)
  end

  def find_contact_by_email(email)
    return if email.blank?

    account.contacts.from_email(email)
  end

  def find_contact_by_phone_number(phone_number)
    return if phone_number.blank?

    contact = account.contacts.find_by(phone_number: phone_number)
    return contact if contact

    normalized_phone_number = Contacts::BrazilPhoneNormalizer.normalize(phone_number)
    return if normalized_phone_number == phone_number

    account.contacts.find_by(phone_number: normalized_phone_number)
  end

  def waha_api_inbox?
    inbox.channel_type == 'Channel::Api' && inbox.waha_session_name.present?
  end

  # Find LID contact_inbox for PN and migrate to PN to avoid duplicate contacts/conversations.
  def find_and_migrate_waha_lid_to_pn
    target_phone = target_phone_for_waha_match
    return if target_phone.blank?

    inbox.contact_inboxes.where('source_id LIKE ?', '%@lid').find_each do |ci|
      contact = ci.contact
      effective_phone = waha_effective_phone_for(contact)
      next unless effective_phone.present? && phones_match?(effective_phone, target_phone)

      normalized_phone = contact_attributes[:phone_number].present? ? normalize_phone_for_waha(contact_attributes[:phone_number]) : target_phone
      ActiveRecord::Base.transaction do
        ci.update!(source_id: source_id)
        contact.update!(phone_number: normalized_phone) if normalized_phone.present? && contact.phone_number != normalized_phone
      end
      return ci.reload
    end
    nil
  end

  def target_phone_for_waha_match
    phone = contact_attributes[:phone_number].presence
    return normalize_phone_for_waha(phone) if phone.present?

    return unless source_id.to_s.end_with?('@c.us')

    normalize_phone_for_waha("+#{source_id.to_s.split('@').first}")
  end

  def normalize_phone_for_waha(phone)
    return if phone.blank?

    normalized = Contacts::BrazilPhoneNormalizer.normalize(phone)
    normalized if normalized&.match?(/\+[1-9]\d{1,14}\z/)
  end

  def waha_effective_phone_for(contact)
    attrs = contact.custom_attributes || {}
    jid = attrs['waha_whatsapp_jid'].presence || attrs['waha_whatsapp_chat_id'].presence
    return nil unless jid.to_s.end_with?('@c.us')

    normalize_phone_for_waha("+#{jid.to_s.split('@').first}")
  end

  def phones_match?(phone_a, phone_b)
    return false if phone_a.blank? || phone_b.blank?

    n_a = Contacts::BrazilPhoneNormalizer.normalize(phone_a)
    n_b = Contacts::BrazilPhoneNormalizer.normalize(phone_b)
    n_a.present? && n_b.present? && n_a == n_b
  end
end
