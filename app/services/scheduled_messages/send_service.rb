# frozen_string_literal: true

module ScheduledMessages
  class SendService
    include FileTypeHelper

    attr_reader :scheduled_message

    def initialize(scheduled_message:)
      @scheduled_message = scheduled_message
    end

    def perform
      return if scheduled_message.sent? || scheduled_message.cancelled?

      if scheduled_message.message_id.present?
        message = scheduled_message.sent_message
        if message.blank?
          return mark_as_failed('Mensagem associada não encontrada')
        end
        message.content_attributes ||= {}
        message.content_attributes.delete(:scheduled_message_id)
        message.content_attributes['skip_signature'] = true
        scheduled_metadata.each { |key, value| message.content_attributes[key] ||= value }
        message.content = sanitize_scheduled_content(message.content, signature_candidates_for(message: message))
        message.save!
        attach_scheduled_attachments!(message)
      else
        conversation = scheduled_message.conversation
        user = scheduled_message.try(:scheduled_by) || conversation.assignee || Current.user
        return mark_as_failed('Usuário não encontrado para enviar mensagem') unless user

        message_params = {
          content: sanitize_scheduled_content(
            scheduled_message.message,
            signature_candidates_for(user: user)
          ),
          content_type: :text,
          message_type: 'outgoing',
          private: false,
          content_attributes: scheduled_metadata.merge('skip_signature' => true)
        }
        message_params[:attachments] = scheduled_message.attachments.map { |a| a.blob.signed_id } if scheduled_message.attachments.attached?

        mb = Messages::MessageBuilder.new(user, conversation, message_params.with_indifferent_access)
        message = mb.perform
        return mark_as_failed('Falha ao criar mensagem') unless message&.persisted?

        scheduled_message.update!(message_id: message.id) if scheduled_message.class.column_names.include?('message_id')
        # Garantir que anexos do agendamento sejam copiados para a mensagem (evita duplicar se já vieram via MessageBuilder)
        attach_scheduled_attachments!(message)
      end

      ::SendReplyJob.perform_later(message.id)
      attrs = { status: :sent }
      attrs[:sent_at] = Time.current if scheduled_message.class.column_names.include?('sent_at')
      scheduled_message.update!(attrs)
      message
    rescue StandardError => e
      Rails.logger.error "ScheduledMessages::SendService: #{e.class}: #{e.message}"
      mark_as_failed(e.message)
      raise
    end

    private

    def mark_as_failed(msg)
      attrs = { status: :failed }
      attrs[:error_message] = msg if scheduled_message.class.column_names.include?('error_message')
      scheduled_message.update!(attrs)
      nil
    end

    def scheduled_metadata
      meta = { 'scheduled_at' => scheduled_message.scheduled_at&.iso8601 }
      return meta unless scheduled_message.respond_to?(:scheduled_by_id)

      by = scheduled_message.scheduled_by
      meta['scheduled_by'] = { id: by.id, name: by.name } if by.present?
      meta
    end

    def signature_candidates_for(user: nil, message: nil)
      [scheduled_message.try(:scheduled_by)&.name, user&.name, message&.sender&.name,
       scheduled_message.conversation&.assignee&.name].compact.map(&:to_s).map(&:strip).reject(&:empty?).uniq
    end

    def sanitize_scheduled_content(content, signature_candidates = [])
      return content if content.blank?

      cleaned = content.to_s
      signature_candidates.each { |name| cleaned = cleaned.sub(/\A#{Regexp.escape(name)}\s*:\s*\n+/i, '') }
      cleaned.gsub(/\n\n--\s*\n\n.*$/m, '')
            .gsub(/\n\n\*\*:.*$/m, '')
            .gsub(/^\*\*:.*$/m, '')
            .gsub(/\*\*:\s*/, '')
            .strip
    end

    def attach_scheduled_attachments!(msg)
      return unless scheduled_message.attachments.attached?

      existing_blob_ids = msg.attachments.map { |a| a.file&.blob_id }.compact
      scheduled_message.attachments.each do |scheduled_attachment|
        blob = scheduled_attachment.blob
        next if existing_blob_ids.include?(blob.id)

        att = msg.attachments.build(account_id: msg.account_id)
        att.file.attach(blob)
        att.file_type = file_type(blob&.content_type)
        att.save!
      end
    end
  end
end
