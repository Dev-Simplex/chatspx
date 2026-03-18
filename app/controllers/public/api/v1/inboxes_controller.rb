class Public::Api::V1::InboxesController < PublicController
  before_action :set_inbox_channel
  before_action :set_contact_inbox
  before_action :set_conversation

  def show
    @inbox_channel = ::Channel::Api.find_by!(identifier: params[:id])
  end

  private

  def set_inbox_channel
    return if params[:inbox_id].blank?

    @inbox_channel = ::Channel::Api.find_by!(identifier: params[:inbox_id])
  end

  def set_contact_inbox
    return if params[:contact_id].blank?

    source_id = params[:contact_id]
    normalized = normalize_waha_contact_params(source_id: source_id, phone_number: nil)
    resolved_source_id = normalized[:source_id]

    @contact_inbox = @inbox_channel.inbox.contact_inboxes.find_by(source_id: resolved_source_id)
    @contact_inbox ||= @inbox_channel.inbox.contact_inboxes.find_by!(source_id: source_id)
  end

  def set_conversation
    return if params[:conversation_id].blank?

    @conversation = @contact_inbox.contact.conversations.find_by!(display_id: params[:conversation_id])
  end

  def normalize_waha_contact_params(source_id:, phone_number:, custom_attributes: nil)
    return { source_id: source_id, phone_number: phone_number } if source_id.blank?
    return { source_id: source_id, phone_number: phone_number } unless waha_lid?(source_id)

    pn_from_custom_attributes = extract_pn_from_custom_attributes(custom_attributes)
    if pn_from_custom_attributes.present?
      normalized_phone = normalize_waha_phone_number(pn_from_custom_attributes) || phone_number
      merge_waha_lid_contact_inbox_to_pn(
        lid: source_id,
        pn: pn_from_custom_attributes,
        normalized_phone: normalized_phone
      )

      return {
        source_id: pn_from_custom_attributes,
        phone_number: normalized_phone
      }
    end

    session_name = waha_session_name
    return { source_id: source_id, phone_number: phone_number } if session_name.blank?

    pn = resolve_lid_to_pn(session_name, source_id)
    if pn.blank?
      Rails.logger.warn("WAHA LID resolved to null for #{source_id} (inbox_id=#{@inbox_channel&.inbox&.id})")
      schedule_lid_retry(source_id)
      return { source_id: source_id, phone_number: phone_number }
    end

    normalized_phone = normalize_waha_phone_number(pn) || phone_number
    merge_waha_lid_contact_inbox_to_pn(lid: source_id, pn: pn, normalized_phone: normalized_phone)

    {
      source_id: pn,
      phone_number: normalized_phone
    }
  rescue Waha::ApiService::Error => e
    Rails.logger.warn("WAHA LID lookup failed for #{source_id}: #{e.message}")
    schedule_lid_retry(source_id)
    { source_id: source_id, phone_number: phone_number }
  end

  # WAHA response may use 'pn' or (in some engines) 'number'. Prefer pn.
  def extract_pn_from_response(hash)
    return nil unless hash.is_a?(Hash)

    hash['pn'].presence || hash[:pn].presence || hash['number'].presence || hash[:number].presence
  end

  def extract_pn_from_custom_attributes(custom_attributes)
    return nil unless custom_attributes.is_a?(Hash)

    jid = custom_attributes['waha_whatsapp_jid'].presence || custom_attributes[:waha_whatsapp_jid].presence
    return jid if whatsapp_user_jid?(jid)

    chat_id = custom_attributes['waha_whatsapp_chat_id'].presence || custom_attributes[:waha_whatsapp_chat_id].presence
    return chat_id if whatsapp_user_jid?(chat_id)

    nil
  end

  def resolve_lid_to_pn(session_name, lid)
    response = waha_service.get_lid_phone_number(session_name, lid)
    pn = extract_pn_from_response(response)
    return pn if pn.present?

    # Fallback: GET /api/{session}/lids list and find this LID in the array
    list = waha_service.get_lids_list(session_name, limit: 500, offset: 0)
    return nil unless list.is_a?(Array)

    entry = list.find { |item| (item['lid'] || item[:lid]).to_s == lid.to_s }
    extract_pn_from_response(entry || {})
  rescue Waha::ApiService::Error
    nil
  end

  # When LID resolved to pn, unify contact_inbox: update orphan LID contact_inbox to pn, or merge contacts if both exist.
  def merge_waha_lid_contact_inbox_to_pn(lid:, pn:, normalized_phone:)
    inbox = @inbox_channel&.inbox
    return if inbox.blank?

    contact_inbox_by_pn = inbox.contact_inboxes.find_by(source_id: pn)
    contact_inbox_by_lid = inbox.contact_inboxes.find_by(source_id: lid)
    return if contact_inbox_by_lid.blank?

    # Lock in consistent order (by id) to avoid deadlocks between concurrent merges.
    to_lock = [contact_inbox_by_lid, contact_inbox_by_pn].compact.sort_by(&:id)

    ActiveRecord::Base.transaction do
      to_lock.each(&:lock!)
      contact_inbox_by_lid.reload

      if contact_inbox_by_pn.present? && contact_inbox_by_pn.id != contact_inbox_by_lid.id
        # Two contact_inboxes for same person (pn and LID). Merge LID contact into pn contact, then remove LID contact_inbox.
        base_contact = contact_inbox_by_pn.contact
        mergee_contact = contact_inbox_by_lid.contact
        unless base_contact.id == mergee_contact.id
          ContactMergeAction.new(
            account: inbox.account,
            base_contact: base_contact,
            mergee_contact: mergee_contact
          ).perform
          contact_inbox_by_lid.reload
          contact_inbox_by_lid.destroy!
        end
      else
        # Only LID contact_inbox exists: update it to pn and set contact phone_number
        contact_inbox_by_lid.update!(source_id: pn)
        contact_inbox_by_lid.contact.update!(phone_number: normalized_phone) if normalized_phone.present?
      end
    end
  end

  def normalize_waha_phone_number(pn)
    clean_number = pn.to_s.split('@').first
    return nil if clean_number.blank?

    phone_number = clean_number.start_with?('+') ? clean_number : "+#{clean_number}"
    Contacts::BrazilPhoneNormalizer.normalize(phone_number)
  end

  def waha_lid?(source_id)
    source_id.to_s.end_with?('@lid')
  end

  def whatsapp_user_jid?(jid)
    jid.to_s.end_with?('@c.us')
  end

  def schedule_lid_retry(lid_source_id)
    inbox = @inbox_channel&.inbox
    return if inbox.blank?

    contact_inbox = inbox.contact_inboxes.find_by(source_id: lid_source_id)
    Contacts::ResolveLidJob.set(wait: 10.seconds).perform_later(contact_inbox.id) if contact_inbox.present?
  end

  def waha_session_name
    @inbox_channel&.inbox&.waha_session_name
  end

  def waha_service
    @waha_service ||= Waha::ApiService.new
  end
end
