class Captain::Tools::Copilot::SendTemplateService < Captain::Tools::BaseTool
  include Captain::Tools::Copilot::ConversationScope

  def self.name
    'send_template'
  end
  description 'Send a WhatsApp template (HSM) message in a conversation'

  param :conversation_id, type: :integer, desc: 'Display ID of the conversation', required: true
  param :template_name, type: :string, desc: 'Name of the WhatsApp template to send', required: true
  param :template_params, type: :string, desc: 'JSON array of template parameter values (optional)'

  def execute(conversation_id:, template_name:, template_params: nil)
    conversation = find_permissible_conversation(conversation_id)
    return conversation_refusal(conversation_id) if conversation.blank?
    return 'Conversation inbox is not a WhatsApp channel' unless conversation.inbox&.channel_type == 'Channel::Whatsapp'

    parsed_params = parse_template_params(template_params)
    additional_attributes = { template_params: { name: template_name, processed_params: parsed_params } }

    params = { content: nil, private: false, content_attributes: {}, additional_attributes: additional_attributes }
    message = Messages::MessageBuilder.new(nil, conversation, params).perform

    "WhatsApp template '#{template_name}' sent in conversation ##{conversation_id} (message id: #{message.id})"
  end

  def active?
    user_has_permission('conversation_manage')
  end

  private

  def parse_template_params(template_params)
    return [] if template_params.blank?

    JSON.parse(template_params)
  rescue JSON::ParserError
    []
  end
end
