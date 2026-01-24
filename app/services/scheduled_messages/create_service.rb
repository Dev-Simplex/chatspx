# frozen_string_literal: true

module ScheduledMessages
  class CreateService
    attr_reader :conversation, :inbox, :message_content, :scheduled_at, :user

    def initialize(conversation:, inbox:, message:, scheduled_at:, user: nil)
      @conversation = conversation
      @inbox = inbox
      @message_content = message
      @scheduled_at = scheduled_at
      @user = user || Current.user
      
      validate_inputs!
    end

    def perform
      Rails.logger.info("ScheduledMessages::CreateService#perform - Iniciando criação")
      Rails.logger.info("ScheduledMessages::CreateService#perform - Conversation: #{conversation.id}, Inbox: #{inbox.id}, User: #{user.id}")
      
      scheduled_at_time = parse_scheduled_at
      Rails.logger.info("ScheduledMessages::CreateService#perform - Scheduled at parsed: #{scheduled_at_time}")
      
      validate_scheduled_at!(scheduled_at_time)
      
      # Usar sempre o inbox da conversation (simplificado)
      inbox_to_use = conversation.inbox
      Rails.logger.info("ScheduledMessages::CreateService#perform - Usando inbox da conversation: #{inbox_to_use.id}")
      
      # Criar apenas o ScheduledMessage (sem criar Message antecipadamente)
      # A Message será criada pelo SendJob quando chegar a hora
      scheduled_message = ScheduledMessage.create!(
        conversation: conversation,
        inbox: inbox_to_use,
        message: message_content,
        message_id: nil, # Será preenchido pelo SendJob quando criar a Message
        scheduled_at: scheduled_at_time,
        status: :pending
      )
      
      Rails.logger.info("ScheduledMessages::CreateService#perform - ScheduledMessage criado: #{scheduled_message.id}")

      # Agendar job para envio
      Rails.logger.info("ScheduledMessages::CreateService#perform - Agendando job para: #{scheduled_at_time}")
      begin
        ScheduledMessages::SendJob.set(wait_until: scheduled_at_time).perform_later(scheduled_message.id)
        Rails.logger.info("ScheduledMessages::CreateService#perform - Job agendado com sucesso")
      rescue StandardError => e
        Rails.logger.error("ScheduledMessages::CreateService#perform - Erro ao agendar job: #{e.class.name}: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        # Não falhar a criação se o job não puder ser agendado - apenas logar o erro
      end

      Rails.logger.info("ScheduledMessages::CreateService#perform - Concluído com sucesso")
      scheduled_message
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("ScheduledMessages::CreateService#perform - RecordInvalid: #{e.message}")
      Rails.logger.error("ScheduledMessages::CreateService#perform - Errors: #{e.record.errors.full_messages.inspect}")
      Rails.logger.error(e.backtrace.join("\n"))
      raise ArgumentError, "Erro de validação: #{e.record.errors.full_messages.join(', ')}"
    rescue StandardError => e
      Rails.logger.error("ScheduledMessages::CreateService#perform - StandardError: #{e.class.name}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      raise e
    end

    private

    def validate_inputs!
      Rails.logger.debug("ScheduledMessages::CreateService#validate_inputs! - Validando inputs")
      
      if user.nil?
        Rails.logger.error("ScheduledMessages::CreateService#validate_inputs! - User é nil")
        raise ArgumentError, 'User é obrigatório'
      end
      
      if conversation.nil?
        Rails.logger.error("ScheduledMessages::CreateService#validate_inputs! - Conversation é nil")
        raise ArgumentError, 'Conversation é obrigatória'
      end
      
      if inbox.nil?
        Rails.logger.error("ScheduledMessages::CreateService#validate_inputs! - Inbox é nil")
        raise ArgumentError, 'Inbox é obrigatório'
      end
      
      # Validar que inbox pertence ao account da conversation
      unless inbox.account_id == conversation.account_id
        Rails.logger.error("ScheduledMessages::CreateService#validate_inputs! - Inbox #{inbox.id} não pertence ao account #{conversation.account_id}")
        raise ArgumentError, 'Inbox não pertence ao account da conversa'
      end
      
      if message_content.blank?
        Rails.logger.error("ScheduledMessages::CreateService#validate_inputs! - Mensagem está vazia")
        raise ArgumentError, 'Mensagem não pode estar vazia'
      end
      
      if scheduled_at.blank?
        Rails.logger.error("ScheduledMessages::CreateService#validate_inputs! - Scheduled_at está vazio")
        raise ArgumentError, 'Scheduled_at é obrigatório'
      end
      
      Rails.logger.debug("ScheduledMessages::CreateService#validate_inputs! - Validação concluída com sucesso")
    end

    def parse_scheduled_at
      Rails.logger.debug("ScheduledMessages::CreateService#parse_scheduled_at - Parseando: #{scheduled_at} (#{scheduled_at.class})")
      
      result = if scheduled_at.is_a?(String)
        # Tentar parsear com timezone primeiro, depois sem timezone
        parsed = Time.zone.parse(scheduled_at)
        parsed ||= Time.parse(scheduled_at)
        parsed
      else
        scheduled_at
      end
      
      unless result.is_a?(Time) || result.is_a?(ActiveSupport::TimeWithZone)
        Rails.logger.error("ScheduledMessages::CreateService#parse_scheduled_at - Resultado não é Time: #{result.class}")
        raise ArgumentError, "Data/hora inválida: #{scheduled_at}"
      end
      
      Rails.logger.debug("ScheduledMessages::CreateService#parse_scheduled_at - Parseado para: #{result}")
      result
    rescue ArgumentError => e
      Rails.logger.error("ScheduledMessages::CreateService#parse_scheduled_at - ArgumentError: #{e.message}")
      raise ArgumentError, "Data/hora inválida: #{scheduled_at}. Erro: #{e.message}"
    end

    def validate_scheduled_at!(scheduled_at_time)
      current_time = Time.current
      Rails.logger.debug("ScheduledMessages::CreateService#validate_scheduled_at! - Validando: #{scheduled_at_time} > #{current_time}")
      
      if scheduled_at_time <= current_time
        Rails.logger.error("ScheduledMessages::CreateService#validate_scheduled_at! - Data no passado: #{scheduled_at_time} <= #{current_time}")
        raise ArgumentError, 'Data/hora de agendamento deve ser no futuro'
      end
      
      Rails.logger.debug("ScheduledMessages::CreateService#validate_scheduled_at! - Validação OK")
    end
  end
end

