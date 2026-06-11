class Captain::Tools::Copilot::SetCustomAttributesService < Captain::Tools::BaseTool
  def self.name
    'set_custom_attributes'
  end
  description 'Set custom attributes on a conversation or contact'

  param :target_type, type: :string, desc: "Target type: 'conversation' or 'contact'", required: true
  param :target_id, type: :integer, desc: 'ID of the target (display_id for conversation, id for contact)', required: true
  param :attributes, type: :string, desc: 'JSON object of custom attributes to set', required: true

  def execute(target_type:, target_id:, attributes:)
    parsed_attrs = JSON.parse(attributes)
    return 'Attributes must be a JSON object' unless parsed_attrs.is_a?(Hash)

    target = find_target(target_type, target_id)
    return "#{target_type.capitalize} not found" if target.nil?

    merged = (target.custom_attributes || {}).merge(parsed_attrs)
    target.update!(custom_attributes: merged)
    "Custom attributes updated on #{target_type} ##{target_id}: #{parsed_attrs.keys.join(', ')}"
  rescue JSON::ParserError
    'Invalid JSON in attributes parameter'
  end

  def active?
    user_has_permission('conversation_manage') || user_has_permission('contact_manage')
  end

  private

  def find_target(target_type, target_id)
    case target_type
    when 'conversation'
      @assistant.account.conversations.find_by(display_id: target_id)
    when 'contact'
      Contact.find_by(id: target_id, account_id: @assistant.account_id)
    end
  end
end
