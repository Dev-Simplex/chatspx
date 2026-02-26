class ContactMergeAction
  include Events::Types
  pattr_initialize [:account!, :base_contact!, :mergee_contact!]

  def perform
    # This case happens when an agent updates a contact email in dashboard,
    # while the contact also update his email via email collect box
    return @base_contact if base_contact.id == mergee_contact.id

    ActiveRecord::Base.transaction do
      validate_contacts
      merge_contact_inboxes
      merge_conversations
      merge_messages
      merge_contact_notes
      merge_nps_responses
      merge_csat_survey_responses
      merge_and_remove_mergee_contact
    end
    @base_contact
  end

  private

  def validate_contacts
    return if belongs_to_account?(@base_contact) && belongs_to_account?(@mergee_contact)

    raise StandardError, 'contact does not belong to the account'
  end

  def belongs_to_account?(contact)
    @account.id == contact.account_id
  end

  def merge_conversations
    # rubocop:disable Rails/SkipsModelValidations
    Conversation.where(contact_id: @mergee_contact.id).update_all(contact_id: @base_contact.id, updated_at: Time.zone.now)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def merge_contact_notes
    # rubocop:disable Rails/SkipsModelValidations
    Note.where(contact_id: @mergee_contact.id, account_id: @mergee_contact.account_id)
        .update_all(contact_id: @base_contact.id, updated_at: Time.zone.now)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def merge_messages
    # rubocop:disable Rails/SkipsModelValidations
    Message.where(sender: @mergee_contact).update_all(sender_id: @base_contact.id, sender_type: 'Contact', updated_at: Time.zone.now)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def merge_contact_inboxes
    base_contact_inboxes = ContactInbox.where(contact_id: @base_contact.id)
                                       .index_by { |contact_inbox| [contact_inbox.inbox_id, contact_inbox.source_id] }

    ContactInbox.where(contact_id: @mergee_contact.id).find_each do |mergee_contact_inbox|
      key = [mergee_contact_inbox.inbox_id, mergee_contact_inbox.source_id]
      base_contact_inbox = base_contact_inboxes[key]

      if base_contact_inbox
        # rubocop:disable Rails/SkipsModelValidations
        Conversation.where(contact_inbox_id: mergee_contact_inbox.id)
                    .update_all(contact_id: @base_contact.id, contact_inbox_id: base_contact_inbox.id, updated_at: Time.zone.now)
        # rubocop:enable Rails/SkipsModelValidations
        mergee_contact_inbox.destroy!
        next
      end

      mergee_contact_inbox.update!(contact_id: @base_contact.id)
      base_contact_inboxes[key] = mergee_contact_inbox
    end
  end

  def merge_nps_responses
    # rubocop:disable Rails/SkipsModelValidations
    NpsResponse.where(contact_id: @mergee_contact.id).update_all(contact_id: @base_contact.id, updated_at: Time.zone.now)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def merge_csat_survey_responses
    # rubocop:disable Rails/SkipsModelValidations
    CsatSurveyResponse.where(contact_id: @mergee_contact.id).update_all(contact_id: @base_contact.id, updated_at: Time.zone.now)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def merge_and_remove_mergee_contact
    mergable_attribute_keys = %w[identifier name email phone_number additional_attributes custom_attributes]
    base_contact_attributes = base_contact.attributes.slice(*mergable_attribute_keys).compact_blank
    mergee_contact_attributes = mergee_contact.attributes.slice(*mergable_attribute_keys).compact_blank

    # attributes in base contact are given preference
    merged_attributes = mergee_contact_attributes.deep_merge(base_contact_attributes)

    @mergee_contact.reload.destroy!
    Rails.configuration.dispatcher.dispatch(CONTACT_MERGED, Time.zone.now, contact: @base_contact,
                                                                           tokens: [@base_contact.contact_inboxes.filter_map(&:pubsub_token)])
    @base_contact.update!(merged_attributes)
  end
end
