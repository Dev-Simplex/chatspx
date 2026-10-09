# frozen_string_literal: true

# Prévia do primeiro link da mensagem do chat interno: busca fora da requisição de envio, guarda em
# content_attributes.link_preview e avisa a tela de todos pelo mesmo evento de mensagem atualizada.
class InternalMessages::LinkPreviewJob < ApplicationJob
  queue_as :low

  LINK_RE = %r{https?://[^\s<>"]+}

  def perform(message_id)
    message = InternalMessage.find_by(id: message_id)
    return if message.blank? || message.deleted?

    url = first_link(message.content)
    return if url.blank? || message.content_attributes.dig('link_preview', 'url') == url

    preview = InternalMessages::LinkPreviewService.new(url).perform
    return if preview.blank?

    message.update!(content_attributes: message.content_attributes.merge('link_preview' => preview))
    InternalMessages::BroadcastService.updated(message)
  end

  def self.link?(content)
    content.to_s.match?(LINK_RE)
  end

  private

  def first_link(content)
    content.to_s[LINK_RE]&.sub(/[.,;:!?)\]]+\z/, '')
  end
end
