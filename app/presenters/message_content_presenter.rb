class MessageContentPresenter < SimpleDelegator
  def outgoing_content
    # Remove signature patterns from NPS and CSAT messages
    # The "**: " pattern is likely from markdown signature formatting
    cleaned_content = remove_signature_from_content(content)
    
    cleaned_content_to_send = if should_append_survey_link?
                        survey_link = survey_url(conversation.uuid)
                        custom_message = inbox.csat_config&.dig('message')
                        message_with_link = custom_message.present? ? "#{custom_message} #{survey_link}" : I18n.t('conversations.survey.response', link: survey_link)
    remove_signature_from_content(message_with_link)
                      else
                        content
                      end

    Messages::MarkdownRendererService.new(
      content_to_send,
      conversation.inbox.channel_type,
      conversation.inbox.channel
    ).render
  end

  private

  def should_append_survey_link?
    input_csat? && !inbox.web_widget?
  end

  def survey_url(conversation_uuid)
    "#{ENV.fetch('FRONTEND_URL', nil)}/survey/responses/#{conversation_uuid}"
  end

  def remove_signature_from_content(text)
    return text unless text.present?
    return text unless input_nps? || input_csat? || content_attributes&.dig(:skip_signature)
    
    # Remove signature patterns like "**: " or "--\n\n**:" or similar markdown signature formats
    # This removes common signature delimiters and markdown formatting
    text.gsub(/\n\n--\s*\n\n\*\*:.*$/m, '')
        .gsub(/\n\n\*\*:.*$/m, '')
        .gsub(/^\*\*:.*$/m, '')
        .gsub(/\*\*:\s*/, '')  # Remove "**: " from anywhere in the text
        .strip
  end
end
