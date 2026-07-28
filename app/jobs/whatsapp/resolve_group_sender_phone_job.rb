# frozen_string_literal: true

# Enriquece `content_attributes['group_sender']` com o telefone do participante.
#
# Roda SEMPRE fora do request: a ingestao da mensagem nao pode esperar a WAHA
# (timeout de 8s no `Waha::ApiService`). Se a resolucao falhar, a mensagem ja
# entrou com `phone => nil` e o front cai no nome — nada quebra.
class Whatsapp::ResolveGroupSenderPhoneJob < ApplicationJob
  queue_as :low

  # Backoff curto: se a WAHA estiver fora, o valor chega atrasado e nao ha
  # prejuizo. Poucas tentativas de proposito — grupo movimentado enfileira muito.
  retry_on Waha::ApiService::Error, wait: ->(executions) { [15, 60, 300][executions - 1] || 300 }, attempts: 3
  discard_on ActiveRecord::RecordNotFound

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return if message.blank?

    sender = pending_sender(message)
    return if sender.blank?

    session_name = message.inbox&.waha_session_name
    return if session_name.blank?

    phone = Whatsapp::GroupSenderPhoneResolver.new(session_name).phone_for(sender['lid'])
    return if phone.blank?

    persist_phone(message, phone)
  end

  private

  # Autor que ainda precisa de telefone: tem LID e nao tem numero.
  def pending_sender(message)
    sender = message.content_attributes&.dig('group_sender')
    return nil if sender.blank? || sender['phone'].present? || sender['lid'].blank?

    sender
  end

  # Releitura + merge: `content_attributes` e jsonb e pode ter sido tocado por
  # outro caminho entre a ingestao e este job.
  def persist_phone(message, phone)
    message.reload
    attributes = message.content_attributes.presence || {}
    sender = attributes['group_sender']
    return if sender.blank? || sender['phone'].present?

    attributes['group_sender'] = sender.merge('phone' => phone)
    message.update!(content_attributes: attributes)
  rescue ActiveRecord::RecordNotFound
    nil
  end
end
