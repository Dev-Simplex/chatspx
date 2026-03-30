# frozen_string_literal: true

class Contacts::WhatsappValidationJob < ApplicationJob
  queue_as :default

  def perform(account_id, batch_size: 200, only_missing: true)
    account = Account.find(account_id)
    session_names = resolve_session_names(account)
    return if session_names.blank?

    scope = account.contacts.where.not(phone_number: [nil, ''])
    scope = scope.where("custom_attributes ->> 'whatsapp_last_checked_at' IS NULL") if only_missing

    scope.find_in_batches(batch_size: batch_size) do |batch|
      batch.each do |contact|
        validate_contact(contact, session_names)
      end
    end
  end

  private

  def validate_contact(contact, session_names)
    normalized_phone = normalize_phone_number(contact.phone_number)
    return if normalized_phone.blank?

    result = check_number_exists(session_names, normalized_phone)
    return if result.nil?

    exists, session_used = result
    custom_attributes = contact.custom_attributes || {}
    custom_attributes['whatsapp_number_exists'] = exists
    custom_attributes['whatsapp_last_checked_at'] = Time.zone.now.iso8601
    custom_attributes['whatsapp_validation_source'] = session_used

    # Avoid validation failures on legacy duplicates by updating only JSONB.
    contact.update_columns( # rubocop:disable Rails/SkipsModelValidations
      custom_attributes: custom_attributes,
      updated_at: Time.zone.now
    )
  end

  def resolve_session_names(account)
    session_names = account.inboxes.where.not(waha_session_name: nil).pluck(:waha_session_name).uniq
    if session_names.blank?
      default_session = ENV.fetch('WAHA_DEFAULT_SESSION', nil)
      return [default_session] if default_session.present?

      Rails.logger.info('[WhatsappValidationJob] No WAHA sessions found and WAHA_DEFAULT_SESSION not set. Skipping.')
      return []
    end

    session_names
  end

  def normalize_phone_number(phone_number)
    normalized = Contacts::BrazilPhoneNormalizer.normalize(phone_number)
    normalized.to_s.delete_prefix('+')
  end

  def check_number_exists(session_names, normalized_phone) # rubocop:disable Metrics/CyclomaticComplexity
    service = waha_service
    had_response = false
    had_false = false
    last_session = nil

    session_names.each do |session_name|
      response = service.check_contact_exists(
        session_name: session_name,
        phone: normalized_phone
      )
      number_exists = response.fetch('numberExists') { response[:numberExists] }
      had_response = true
      last_session = session_name

      return [true, session_name] if number_exists

      had_false = true if number_exists == false
    rescue Waha::ApiService::Error
      next
    end

    return [false, last_session] if had_response && had_false

    nil
  end

  def waha_service
    @waha_service ||= Waha::ApiService.new
  end
end
