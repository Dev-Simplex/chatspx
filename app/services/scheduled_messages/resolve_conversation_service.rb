# frozen_string_literal: true

class ScheduledMessages::ResolveConversationService
  def initialize(account:, conversation_id: nil, contact_id: nil, inbox_id: nil)
    @account = account
    @conversation_id = conversation_id
    @contact_id = contact_id
    @inbox_id = inbox_id
  end

  def perform
    return find_conversation if conversation_id.present?

    resolve_or_create_conversation_for_contact
  end

  private

  attr_reader :account, :conversation_id, :contact_id, :inbox_id

  def find_conversation
    conversation = account.conversations.find_by(id: conversation_id)
    conversation ||= account.conversations.find_by(display_id: conversation_id)
    raise ActiveRecord::RecordNotFound, 'Conversation not found' if conversation.blank?

    conversation
  end

  def resolve_or_create_conversation_for_contact # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    raise ArgumentError, 'contact_id is required when conversation_id is not provided' if contact_id.blank?
    raise ArgumentError, 'inbox_id is required when conversation_id is not provided' if inbox_id.blank?

    contact = account.contacts.find(contact_id)
    inbox = account.inboxes.find(inbox_id)
    contact_inbox = contact.contact_inboxes.find_by(inbox_id: inbox.id)
    contact_inbox ||= ContactInboxBuilder.new(contact: contact, inbox: inbox, source_id: nil).perform

    conversation = account.conversations
                          .where(contact_id: contact.id, inbox_id: inbox.id, contact_inbox_id: contact_inbox.id)
                          .where.not(status: :resolved)
                          .order(last_activity_at: :desc, id: :desc)
                          .first
    return conversation if conversation.present?

    ConversationBuilder.new(
      params: ActionController::Parameters.new(
        inbox_id: inbox.id,
        contact_id: contact.id,
        status: 'open'
      ),
      contact_inbox: contact_inbox
    ).perform
  end
end
