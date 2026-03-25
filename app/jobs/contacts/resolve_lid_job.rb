# frozen_string_literal: true

class Contacts::ResolveLidJob < ApplicationJob
  queue_as :high
  # Backoff agressivo: 5s, 15s, 30s, 60s, 120s, 300s, 600s (~18min total)
  retry_on Waha::ApiService::Error, wait: ->(executions) { [5, 15, 30, 60, 120, 300, 600][executions - 1] || 600 }, attempts: 7

  def perform(contact_inbox_id)
    contact_inbox = ContactInbox.find_by(id: contact_inbox_id)
    return if contact_inbox.blank?
    return unless contact_inbox.source_id.to_s.end_with?('@lid')

    inbox = contact_inbox.inbox
    session_name = inbox.waha_session_name
    return if session_name.blank?

    waha_service = Waha::ApiService.new
    pn = resolve_lid(waha_service, session_name, contact_inbox.source_id)

    if pn.blank?
      Rails.logger.info("[ResolveLidJob] LID #{contact_inbox.source_id} still unresolved (contact_inbox=#{contact_inbox_id})")
      raise Waha::ApiService::Error, "LID not yet resolvable: #{contact_inbox.source_id}"
    end

    normalized_phone = normalize_phone(pn)
    merge_or_update(inbox, contact_inbox, pn, normalized_phone)

    # Notificar frontend via ActionCable que o contato foi atualizado
    broadcast_contact_update(contact_inbox, inbox)
  end

  private

  def resolve_lid(waha_service, session_name, lid)
    response = waha_service.get_lid_phone_number(session_name, lid)
    pn = extract_pn(response)
    return pn if pn.present?

    list = waha_service.get_lids_list(session_name, limit: 500, offset: 0)
    return nil unless list.is_a?(Array)

    entry = list.find { |item| (item['lid'] || item[:lid]).to_s == lid.to_s }
    extract_pn(entry || {})
  end

  def extract_pn(hash)
    return nil unless hash.is_a?(Hash)

    hash['pn'].presence || hash[:pn].presence || hash['number'].presence || hash[:number].presence
  end

  def normalize_phone(pn)
    clean_number = pn.to_s.split('@').first
    return nil if clean_number.blank?

    phone_number = clean_number.start_with?('+') ? clean_number : "+#{clean_number}"
    Contacts::BrazilPhoneNormalizer.normalize(phone_number)
  end

  def merge_or_update(inbox, contact_inbox_by_lid, pn, normalized_phone)
    contact_inbox_by_pn = inbox.contact_inboxes.find_by(source_id: pn)

    ActiveRecord::Base.transaction do
      if contact_inbox_by_pn.present? && contact_inbox_by_pn.id != contact_inbox_by_lid.id
        base_contact = contact_inbox_by_pn.contact
        mergee_contact = contact_inbox_by_lid.contact
        unless base_contact.id == mergee_contact.id
          ContactMergeAction.new(
            account: inbox.account,
            base_contact: base_contact,
            mergee_contact: mergee_contact
          ).perform
        end
        contact_inbox_by_lid.reload
        contact_inbox_by_lid.destroy! if contact_inbox_by_lid.persisted?

        Rails.logger.info("[ResolveLidJob] Merged LID contact #{mergee_contact.id} into PN contact #{base_contact.id}")
      else
        contact_inbox_by_lid.update!(source_id: pn)
        contact = contact_inbox_by_lid.contact
        contact.update!(phone_number: normalized_phone) if normalized_phone.present? && contact.phone_number.blank?
        update_contact_name_from_phone(contact, normalized_phone) if contact.name.match?(/\A[a-z]+-[a-z]+-\d+\z/)

        Rails.logger.info("[ResolveLidJob] Updated LID #{contact_inbox_by_lid.source_id} to PN #{pn}")
      end
    end
  end

  def update_contact_name_from_phone(contact, phone)
    return if phone.blank?

    contact.update!(name: phone)
  end

  def broadcast_contact_update(contact_inbox, inbox)
    contact = contact_inbox.contact.reload
    account = inbox.account

    Rails.configuration.dispatcher.dispatch(
      'contact.updated',
      Time.zone.now,
      contact: contact,
      account: account
    )
  rescue StandardError => e
    Rails.logger.warn("[ResolveLidJob] Failed to broadcast contact update: #{e.message}")
  end
end
