# frozen_string_literal: true

module Messages
  class UpdateContentService
    SUPPORTED_CHANNEL = 'Channel::Api'
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
      persist_edit
      @message
    end

    private

    def validate!
      raise StandardError, 'Only outgoing messages can be edited' unless @message.outgoing?
      raise StandardError, 'Only text messages can be edited' unless @message.content_type.to_s == 'text'
      raise StandardError, 'Message has been deleted' if @message.content_attributes['deleted']
      raise StandardError, 'Inbox does not support message editing' unless waha_inbox?
    end

    def waha_inbox?
      inbox.channel_type == SUPPORTED_CHANNEL && inbox.waha_session_name.present?
    end

    # Returns the WAHA message ID to use for editing.
    # Uses source_id if available, otherwise fetches from WAHA API.
    def resolve_waha_message_id
      return @message.source_id if @message.source_id.present?

      find_waha_message_id_from_api
    end

    def find_waha_message_id_from_api
      messages = Waha::ApiService.new.get_messages(inbox.waha_session_name, chat_id, limit: 50)
      return nil unless messages.is_a?(Array)

      # Look for outgoing messages matching content and approximate timestamp
      created_at_ts = @message.created_at.to_i
      match = messages.find do |m|
        from_me    = m['fromMe'] == true || m['key']&.[]('fromMe') == true
        body       = m['body'] || m['text'] || m.dig('content', 'text') || ''
        timestamp  = m['timestamp'].to_i

        from_me && body == @message.content && (timestamp - created_at_ts).abs < EDIT_WINDOW_SECONDS
      end

      raise StandardError, 'Message not found on WhatsApp. It may still be sending.' if match.nil?

      # WAHA message IDs can be in key.id or id field
      match.dig('key', 'id') || match['id']
    rescue Waha::ApiService::Error => e
      raise StandardError, "WAHA API error: #{e.message}"
    end

    def edit_on_waha(waha_message_id)
      raise StandardError, 'Message not found on WhatsApp. It may still be sending.' if waha_message_id.blank?

      Waha::ApiService.new.edit_message(
        inbox.waha_session_name,
        chat_id,
        waha_message_id,
        @new_content
      )
    rescue Waha::ApiService::Error => e
      raise StandardError, "WAHA API error: #{e.message}"
    end

    def persist_edit
      previous = @message.content
      editor = Current.user
      @message.update!(
        content: @new_content,
        content_attributes: @message.content_attributes.merge(
          'previous_content' => previous,
          'edited'           => true,
          'edited_at'        => Time.zone.now.iso8601,
          'edited_by'        => editor ? { 'id' => editor.id, 'name' => editor.name } : nil
        )
      )
    end

    def inbox
      @inbox ||= @message.conversation.inbox
    end

    def chat_id
      # Prefer the explicit WAHA chat ID stored in contact custom attributes
      waha_chat_id = @message.conversation.contact.custom_attributes&.[]('waha_whatsapp_chat_id')
      return waha_chat_id if waha_chat_id.present?

      # Fallback: contact_inbox source_id (may be the WhatsApp JID)
      jid = @message.conversation.contact_inbox.source_id
      return jid if jid.present? && jid.include?('@')

      # Last resort: build from phone number
      phone = @message.conversation.contact.phone_number.to_s.gsub(/\D/, '')
      "#{phone}@c.us"
    end
  end
end
