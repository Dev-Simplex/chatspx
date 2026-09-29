# frozen_string_literal: true

# Disparo da AGENDADA escrita pela IA (CHAT-165; engrenagem 2 do docs/contratos/eixo-followup.md).
#
# Sai em nome da IA, nunca de um usuário: fala de usuário conta como resposta humana
# (Message#human_response?) e soltaria o espelho da IA na conversa.
#
# A forma é decidida AGORA, no disparo, e não no agendamento — a janela é medida pela última fala
# do cliente, que pode mudar até lá. Janela aberta: sai o texto pronto. Fechada: texto livre não
# passa no canal, então sai o template que o agente configurou em
# behavior['agendada']['template_fora_janela'] ({ 'name', 'language' }); sem template, não sai e
# a conversa ganha um aviso.
#
# Não olha handoff nem atribuição: o compromisso foi com o cliente. Quem não quer que ela saia
# cancela a agendada.
class ScheduledMessages::AssistantDeliveryService
  attr_reader :error

  def initialize(scheduled_message:)
    @scheduled_message = scheduled_message
    @conversation = scheduled_message.conversation
    @assistant = scheduled_message.captain_assistant
  end

  def perform
    return create_message(@scheduled_message.message) if @conversation.can_reply?

    deliver_template
  end

  private

  def deliver_template
    template = configured_template
    return fail_with(:window_closed_no_template) if template.nil?

    body = template_body(template)
    variables = body.scan(/\{\{(\d+)\}\}/).flatten.uniq
    return fail_with(:template_unsupported_variables) unless (variables - ['1']).empty?

    first_name = @conversation.contact&.name.to_s.split.first
    return fail_with(:template_without_contact_name) if variables.include?('1') && first_name.blank?

    params = variables.include?('1') ? { '1' => first_name } : {}
    create_message(body.gsub('{{1}}', first_name.to_s), template_params: template_params(template, params))
  end

  def template_params(template, body_params)
    { 'name' => template['name'], 'language' => template['language'], 'processed_params' => { 'body' => body_params } }
  end

  def configured_template
    config = @assistant.behavior&.dig('agendada', 'template_fora_janela')
    return if config.blank? || !@conversation.inbox.channel.respond_to?(:message_templates)

    Array(@conversation.inbox.channel.message_templates).find do |t|
      t['name'] == config['name'] &&
        t['language'].to_s.casecmp?(config['language'].to_s) &&
        t['status'].to_s.casecmp?('approved')
    end
  end

  def template_body(template)
    Array(template['components']).find { |c| c['type'].to_s.casecmp?('BODY') }&.dig('text').to_s
  end

  def create_message(content, template_params: nil)
    @conversation.messages.create!(
      message_type: :outgoing,
      account_id: @conversation.account_id,
      inbox_id: @conversation.inbox_id,
      sender: @assistant,
      content: content,
      content_attributes: {
        'scheduled_at' => @scheduled_message.scheduled_at&.iso8601,
        'scheduled_by' => { 'id' => @assistant.id, 'name' => @assistant.name }
      },
      additional_attributes: template_params ? { 'template_params' => template_params } : {}
    )
  end

  def fail_with(reason)
    @error = I18n.t("scheduled_messages.errors.#{reason}")
    I18n.with_locale(@conversation.account.locale) do
      @conversation.messages.create!(
        message_type: :activity,
        account_id: @conversation.account_id,
        inbox_id: @conversation.inbox_id,
        content: I18n.t('scheduled_messages.activity.assistant_not_sent',
                        reason: I18n.t("scheduled_messages.errors.#{reason}"))
      )
    end
    nil
  end
end
