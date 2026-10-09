# frozen_string_literal: true

# Chat interno — o que já circulou numa conversa, para o painel Detalhes: Mídia (imagens e vídeos),
# Docs (os outros arquivos, inclusive áudio) e Links (tirados do texto das mensagens). Só mensagens
# não apagadas, as mais recentes primeiro, com teto para não pesar em conversa longa.
class InternalChannels::SharedMediaService
  LIMIT = 200
  LINK_RE = %r{https?://[^\s<>"]+}

  def initialize(channel:)
    @channel = channel
  end

  def perform
    files = attachments.map { |attachment| file_json(attachment) }
    media, docs = files.partition { |file| file[:content_type].to_s.start_with?('image/', 'video/') }
    { media: media, docs: docs, links: links }
  end

  private

  def live_messages
    @channel.messages.where(deleted_at: nil)
  end

  def attachments
    ActiveStorage::Attachment
      .where(record_type: 'InternalMessage', name: 'attachments', record_id: live_messages.select(:id))
      .includes(:blob, record: :user)
      .order(created_at: :desc).limit(LIMIT)
  end

  def file_json(attachment)
    message = attachment.record
    {
      id: attachment.id, message_id: message.id, created_at: message.created_at.to_i, user_name: message.user&.name,
      filename: attachment.blob.filename.to_s, content_type: attachment.blob.content_type,
      url: Rails.application.routes.url_helpers.rails_blob_path(attachment.blob, only_path: true)
    }
  end

  def links
    live_messages.where('internal_messages.content ~* ?', 'https?://').includes(:user)
                 .reorder(created_at: :desc).limit(LIMIT)
                 .flat_map { |message| message_links(message) }
                 .first(LIMIT)
  end

  def message_links(message)
    preview = message.content_attributes['link_preview'] || {}
    message.content.to_s.scan(LINK_RE).uniq.filter_map do |url|
      url = url.sub(/[.,;:!?)\]]+\z/, '')
      {
        url: url, message_id: message.id, created_at: message.created_at.to_i, user_name: message.user&.name,
        domain: URI.parse(url).host.to_s.delete_prefix('www.'), title: (preview['title'] if preview['url'] == url)
      }
    rescue URI::InvalidURIError
      nil
    end
  end
end
