# frozen_string_literal: true

module ScheduledMessages
  class SendService
    attr_reader :scheduled_message

    def initialize(scheduled_message:)
      @scheduled_message = scheduled_message
    end

    def perform
      return if scheduled_message.sent? || scheduled_message.cancelled?

      Rails.logger.info("ScheduledMessages::SendService#perform - Processando scheduled message #{scheduled_message.id}")

      # Se já existe message_id, usar a Message existente (backward compatibility)
      if scheduled_message.message_id.present?
        message = scheduled_message.message
        if message.present?
          Rails.logger.info("ScheduledMessages::SendService#perform - Usando Message existente: #{message.id}")
          # Remover o scheduled_message_id dos content_attributes para permitir o envio
          message.content_attributes ||= {}
          message.content_attributes.delete(:scheduled_message_id)
          message.save!
        else
          return mark_as_failed('Mensagem associada não encontrada')
        end
      else
        # Criar a Message agora (nova abordagem simplificada)
        Rails.logger.info("ScheduledMessages::SendService#perform - Criando Message para scheduled message #{scheduled_message.id}")
        
        conversation = scheduled_message.conversation
        user = conversation.assignee || Current.user
        
        unless user
          return mark_as_failed('Usuário não encontrado para enviar mensagem')
        end

        message_params = {
          content: scheduled_message.message,
          content_type: :text,
          message_type: :outgoing,
          private: false,
          content_attributes: {}
        }

        begin
          mb = Messages::MessageBuilder.new(user, conversation, message_params)
          message = mb.perform
          
          unless message&.persisted?
            return mark_as_failed('Falha ao criar mensagem: mensagem não foi persistida')
          end
          
          # Atualizar ScheduledMessage com o message_id
          scheduled_message.update!(message_id: message.id)
          Rails.logger.info("ScheduledMessages::SendService#perform - Message criada: #{message.id}")
        rescue StandardError => e
          Rails.logger.error("ScheduledMessages::SendService#perform - Erro ao criar Message: #{e.class.name}: #{e.message}")
          Rails.logger.error(e.backtrace.join("\n"))
          return mark_as_failed("Erro ao criar mensagem: #{e.message}")
        end
      end

      # Enviar usando o processo normal do Chatwoot
      Rails.logger.info("ScheduledMessages::SendService#perform - Agendando envio da mensagem #{message.id}")
      ::SendReplyJob.perform_later(message.id)

      # Atualizar status para sent após agendar o job
      # O envio real acontecerá de forma assíncrona via SendReplyJob
      scheduled_message.update!(
        status: :sent,
        sent_at: Time.current
      )

      Rails.logger.info("ScheduledMessages::SendService#perform - Scheduled message #{scheduled_message.id} marcado como enviado")
      message
    rescue StandardError => e
      Rails.logger.error("ScheduledMessages::SendService#perform - Erro: #{e.class.name}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      mark_as_failed(e.message)
      raise
    end

    private

    def mark_as_failed(error_message)
      scheduled_message.update!(
        status: :failed,
        error_message: error_message
      )
    end
  end
end

