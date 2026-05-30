class AddTemplateParamsToScheduledMessages < ActiveRecord::Migration[7.1]
  # Permite que uma mensagem agendada carregue os parametros de um template HSM
  # (WhatsApp Cloud API). O MessageBuilder ja faz a ponte template_params ->
  # message.additional_attributes['template_params'], lido por SendOnWhatsappService.
  def change
    add_column :scheduled_messages, :template_params, :jsonb
  end
end
