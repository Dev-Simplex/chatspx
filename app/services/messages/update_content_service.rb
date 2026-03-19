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
      persist_edit(waha_message_id)
      @message
    end

    private

    def validate!
      raise StandardError, 'Only outgoing messages can be edited' unless @message.outgoing?
      raise StandardError, 'Only text messages can be edited' unless @message.content_type.to_s == 'text'
      raise StandardError, 'Message has been deleted' if @message.content_attributes['deleted']
      raise StandardError, 'Inbox does not support message editing' unless waha_inbox?
      raise StandardError, 'Only the sender can edit this message' unless sent_by_current_user?
      raise StandardError, 'Message is too old to edit (15 minute limit)' unless within_edit_window?
    end

    def waha_inbox?
      inbox.channel_type == SUPPORTED_CHANNEL && inbox.waha_session_name.present?
    end

    def sent_by_current_user?
      Current.user && @message.sender_id == Current.user.id && @message.sender_type == 'User'
    end

    def within_edit_window?
      (Time.zone.now - @message.created_at) < EDIT_WINDOW_SECONDS
    end

    # Returns the WAHA message ID to use for editing.
    # Uses source_id if available, otherwise fetches from WAHA API.
    def resolve_waha_message_id
      return @message.source_id if @message.source_id.present?

      find_waha_message_id_from_api
    end

    def find_waha_message_id_from_api
      Rails.logger.info("[UpdateContentService] Looking up WAHA message for message_id=#{@message.id}, chat_id=#{chat_id}, " \
                        "session=#{inbox.waha_session_name}, content=#{@message.content.truncate(100).inspect}")

      messages = Waha::ApiService.new.get_messages(inbox.waha_session_name, chat_id, limit: 100)

      unless messages.is_a?(Array)
        Rails.logger.warn("[UpdateContentService] WAHA API returned non-array: #{messages.class} => #{messages.inspect.truncate(500)}")
        return nil
      end

      Rails.logger.info("[UpdateContentService] WAHA returned #{messages.size} messages")

      if messages.first
        sample = messages.first
        Rails.logger.info("[UpdateContentService] Sample message keys: #{sample.keys.inspect}")
        Rails.logger.info("[UpdateContentService] Sample message: #{sample.inspect.truncate(1000)}")
      end

      # Look for outgoing messages matching content and approximate timestamp
      created_at_ts = @message.created_at.to_i
      match = messages.find do |m|
        from_me    = m['fromMe'] == true || m['key']&.[]('fromMe') == true
        body       = m['body'] || m['text'] || m.dig('content', 'text') || ''
        timestamp  = m['timestamp'].to_i

        # WAHA prefixes outgoing message bodies with "*AgentName*:\n", strip it before comparing
        stripped_body = body.sub(/\A\*[^*]*\*:\n/, '')
        previous_content = @message.content_attributes&.[]('previous_content')
        content_match = stripped_body == @message.content || body == @message.content ||
                        (previous_content.present? && (stripped_body == previous_content || body == previous_content))
        time_diff = (timestamp - created_at_ts).abs
        time_match = time_diff < EDIT_WINDOW_SECONDS

        if from_me
          Rails.logger.info("[UpdateContentService] Candidate fromMe message: body=#{body.truncate(100).inspect}, " \
                            "timestamp=#{timestamp}, chatwoot_ts=#{created_at_ts}, time_diff=#{time_diff}s, " \
                            "content_match=#{content_match}, time_match=#{time_match}")
        end

        from_me && content_match && time_match
      end

      if match.nil?
        Rails.logger.warn("[UpdateContentService] No match found among #{messages.size} messages for content=#{@message.content.truncate(100).inspect}")
        raise StandardError, 'Message not found on WhatsApp. It may still be sending.'
      end

      waha_id = match.dig('key', 'id') || match['id']
      Rails.logger.info("[UpdateContentService] Match found! waha_message_id=#{waha_id}")
      waha_id
    rescue Waha::ApiService::Error => e
      Rails.logger.error("[UpdateContentService] WAHA API error: #{e.message}")
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
