# frozen_string_literal: true

class Messages::UpdateContentService
  include Messages::WahaMessageResolvable

  # Maximum age of a message that can be edited (WhatsApp limitation: ~15 minutes)
  EDIT_WINDOW_SECONDS = 900

  def initialize(message, new_content)
    @message     = message
    @new_content = new_content.strip
  end

  def perform
    validate!
    waha_message_id = resolve_waha_message_id
    edit_on_waha(waha_message_id)
    persist_edit(waha_message_id)
    @message
  end

  private

  def validate!
    raise ArgumentError, 'Only outgoing messages can be edited' unless @message.outgoing?
    raise ArgumentError, 'Only text messages can be edited' unless @message.content_type.to_s == 'text'
    raise ArgumentError, 'Message has been deleted' if @message.content_attributes['deleted']
    raise ArgumentError, 'Inbox does not support message editing' unless waha_inbox?
    raise ArgumentError, 'Only the sender can edit this message' unless sent_by_current_user?
    raise ArgumentError, 'Message is too old to edit (15 minute limit)' unless within_edit_window?
  end

  def within_edit_window?
    (Time.zone.now - @message.created_at) < EDIT_WINDOW_SECONDS
  end

  def edit_on_waha(waha_message_id)
    raise ArgumentError, 'Message not found on WhatsApp. It may still be sending.' if waha_message_id.blank?

    Waha::ApiService.new.edit_message(
      inbox.waha_session_name,
      chat_id,
      waha_message_id,
      @new_content
    )
  rescue Waha::ApiService::Error => e
    raise ArgumentError, "WAHA API error: #{e.message}"
  end

  def persist_edit(waha_message_id)
    previous = @message.content
    editor = Current.user
    attrs = {
      content: @new_content,
      content_attributes: @message.content_attributes.merge(
        'previous_content' => previous,
        'edited' => true,
        'edited_at' => Time.zone.now.iso8601,
        'edited_by' => editor ? { 'id' => editor.id, 'name' => editor.name } : nil
      )
    }
    # Persist WAHA message ID so future edits skip the API lookup
    attrs[:source_id] = waha_message_id if @message.source_id.blank? && waha_message_id.present?
    @message.update!(attrs)
  end
end
