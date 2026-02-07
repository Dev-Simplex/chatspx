# frozen_string_literal: true

module ScheduledMessages
  class CreateService
    attr_reader :conversation, :inbox, :message_content, :scheduled_at, :user, :attachments

    def initialize(conversation:, inbox:, message:, scheduled_at:, user: nil, attachments: [])
      @conversation = conversation
      @inbox = inbox
      @message_content = message
      @scheduled_at = scheduled_at
      @user = user || Current.user
      @attachments = attachments

      validate_inputs!
    end

    def perform
      scheduled_at_time = parse_scheduled_at
      validate_scheduled_at!(scheduled_at_time)

      inbox_to_use = conversation.inbox

      scheduled_message_params = {
        conversation: conversation,
        inbox: inbox_to_use,
        scheduled_at: scheduled_at_time,
        status: :pending
      }
      scheduled_message_params[:account_id] = conversation.account_id if ScheduledMessage.column_names.include?('account_id')
      scheduled_message_params[:message] = (message_content.presence || '').to_s if ScheduledMessage.column_names.include?('message')
      scheduled_message_params[:scheduled_by] = user if ScheduledMessage.column_names.include?('scheduled_by_id')

      scheduled_message = ScheduledMessage.new(scheduled_message_params)

      attachable = normalize_attachments(attachments)
      if attachable.present?
        begin
          scheduled_message.attachments.attach(attachable)
        rescue StandardError => e
          Rails.logger.error "ScheduledMessages::CreateService: attach falhou: #{e.class}: #{e.message}"
          Rails.logger.error e.backtrace.first(5).join("\n")
          raise ArgumentError, "Erro ao anexar arquivos: #{e.message}"
        end
      end

      scheduled_message.save!

      begin
        ScheduledMessages::SendJob.set(wait_until: scheduled_at_time).perform_later(scheduled_message.id)
      rescue StandardError => e
        Rails.logger.error "ScheduledMessages::CreateService: job enqueue falhou: #{e.class}: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
      end

      scheduled_message
    rescue ActiveRecord::RecordInvalid => e
      raise ArgumentError, "Erro de validação: #{e.record.errors.full_messages.join(', ')}"
    end

    private

    def validate_inputs!
      raise ArgumentError, 'User é obrigatório' if user.nil?
      raise ArgumentError, 'Conversation é obrigatória' if conversation.nil?
      raise ArgumentError, 'Inbox é obrigatório' if inbox.nil?
      raise ArgumentError, 'Inbox não pertence ao account da conversa' unless inbox.account_id == conversation.account_id
      raise ArgumentError, 'É necessário texto ou pelo menos um anexo' if message_content.blank? && !attachments_present?
      raise ArgumentError, 'Scheduled_at é obrigatório' if scheduled_at.blank?
    end

    def parse_scheduled_at
      result = if scheduled_at.is_a?(String)
                 Time.zone.parse(scheduled_at) || Time.parse(scheduled_at)
               else
                 scheduled_at
               end
      raise ArgumentError, "Data/hora inválida: #{scheduled_at}" unless result.is_a?(Time) || result.is_a?(ActiveSupport::TimeWithZone)
      result
    rescue ArgumentError => e
      raise ArgumentError, "Data/hora inválida: #{scheduled_at}. Erro: #{e.message}"
    end

    def validate_scheduled_at!(scheduled_at_time)
      # Tolerância de 2 min no passado: evita rejeitar por diferença de relógio ou fuso (Manaus).
      raise ArgumentError, 'Data/hora de agendamento deve ser no futuro' if scheduled_at_time <= 2.minutes.ago
    end

    def attachments_present?
      Array(attachments).any?(&:present?)
    end

    # Mantém apenas o que o Active Storage aceita: String (signed_id) ou UploadedFile (multipart).
    # Descarta hashes vazios, nils e qualquer outro tipo.
    def normalize_attachments(attachments_param)
      return [] if attachments_param.blank?

      Array(attachments_param).compact.select do |a|
        a.is_a?(String) || a.respond_to?(:tempfile)
      end
    end
  end
end
