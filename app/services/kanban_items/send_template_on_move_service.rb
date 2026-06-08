# frozen_string_literal: true

# KANBAN-P3-03: envia o template configurado na stage destino após move.
# Constrói uma mensagem outgoing via MessageBuilder com content_attributes
# carregando o nome do template + variáveis (compatível com WAHA template send).
#
# Fluxo:
#   - Acha message_template a partir do `kanban_stage.default_message_template_id`
#     em `inbox.message_templates` (jsonb) OU em `account.canned_responses`
#     como fallback.
#   - Interpola variáveis usando dados do contato/item.
#   - Cria mensagem outgoing — webhook do WAHA processa o envio real.
#
# Retorna a mensagem criada (ou levanta erro).
class KanbanItems::SendTemplateOnMoveService
  class TemplateNotFound < StandardError; end

  attr_reader :item, :user, :template_id, :variables_override

  def initialize(item:, user:, template_id: nil, variables_override: {})
    @item = item
    @user = user
    @template_id = template_id || item.kanban_stage&.default_message_template_id
    @variables_override = variables_override || {}
  end

  def perform
    raise TemplateNotFound, 'no_template_id' if template_id.blank?

    template = lookup_template
    raise TemplateNotFound, 'template_not_found' if template.blank?

    content = interpolate(template, build_variables)
    create_message(content, template)
  end

  def self.call(**)
    new(**).perform
  end

  private

  def conversation
    @conversation ||= item.conversation
  end

  def lookup_template # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    inbox = conversation&.inbox
    if inbox.respond_to?(:message_templates) && inbox.message_templates.present?
      tpl = Array(inbox.message_templates).find { |t| match_template?(t, template_id) }
      return tpl if tpl
    end

    if defined?(Account)
      acc = item.kanban.account
      canned = acc.canned_responses.where(id: template_id).first if acc.respond_to?(:canned_responses)
      return canned if canned
    end
    nil
  end

  def match_template?(tpl, id)
    return false unless tpl.is_a?(Hash)

    tpl_id = tpl['id'] || tpl[:id] || tpl['name'] || tpl[:name]
    tpl_id.to_s == id.to_s
  end

  def build_variables # rubocop:disable Metrics/AbcSize
    contact = conversation&.contact
    {
      'name' => contact&.name.to_s.split.first.to_s,
      'last_name' => contact&.name.to_s.split.last.to_s,
      'full_name' => contact&.name.to_s,
      'phone' => contact&.phone_number.to_s,
      'value' => format_value(item.metadata.is_a?(Hash) ? item.metadata['value_cents'] : nil),
      'stage' => item.kanban_stage&.name.to_s
    }.merge(variables_override)
  end

  def format_value(cents)
    return '' if cents.blank?

    "R$ #{format('%.2f', cents.to_i / 100.0).tr('.', ',')}"
  end

  def interpolate(template, vars) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    text = if template.is_a?(Hash)
             template['body'] || template[:body] || template['content'] || template[:content] || ''
           elsif template.respond_to?(:content)
             template.content
           else
             template.to_s
           end
    vars.each do |key, value|
      text = text.gsub(/\{\{\s*#{Regexp.escape(key)}\s*\}\}/i, value.to_s)
                 .gsub(/\{\s*#{Regexp.escape(key)}\s*\}/i, value.to_s)
    end
    text
  end

  def create_message(content, template)
    params = ActionController::Parameters.new(
      content: content,
      message_type: 'outgoing',
      private: false,
      content_attributes: {
        template_id: template_id,
        template_name: template_name_of(template),
        sent_from: 'kanban_template_on_move'
      }
    )
    Messages::MessageBuilder.new(user, conversation, params).perform
  end

  def template_name_of(template)
    return template['name'] || template[:name] || template['slug'] if template.is_a?(Hash)
    return template.short_code if template.respond_to?(:short_code)

    template_id.to_s
  end
end
