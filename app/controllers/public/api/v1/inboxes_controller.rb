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

  def normalize_waha_contact_params(source_id:, phone_number:)
    return { source_id: source_id, phone_number: phone_number } if source_id.blank?
    return { source_id: source_id, phone_number: phone_number } unless waha_lid?(source_id)

    session_name = waha_session_name
    return { source_id: source_id, phone_number: phone_number } if session_name.blank?

    response = waha_service.get_lid_phone_number(session_name, source_id)
    pn = response.is_a?(Hash) ? (response['pn'] || response[:pn]) : nil
    return { source_id: source_id, phone_number: phone_number } if pn.blank?

    {
      source_id: pn,
      phone_number: normalize_waha_phone_number(pn) || phone_number
    }
  rescue Waha::ApiService::Error => e
    Rails.logger.warn("WAHA LID lookup failed for #{source_id}: #{e.message}")
    { source_id: source_id, phone_number: phone_number }
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

  def waha_session_name
    @inbox_channel&.inbox&.waha_session_name
  end

  def waha_service
    @waha_service ||= Waha::ApiService.new
  end
end
