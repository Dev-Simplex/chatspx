# frozen_string_literal: true

class Api::V1::Accounts::ScheduledMessagesController < Api::V1::Accounts::BaseController
  before_action :scheduled_message, except: [:index, :create, :inboxes]
  before_action :check_authorization

  def index
    # Buscar mensagens agendadas do account atual
    scope = ScheduledMessage.joins(:conversation).where(conversations: { account_id: Current.account.id })
    scope = scope.where(conversation_id: params[:conversation_id]) if params[:conversation_id].present?
    @scheduled_messages = scope.upcoming
  end

  def show; end

  def create
    Rails.logger.info("ScheduledMessagesController#create - Params: #{params.inspect}")
    Rails.logger.info("ScheduledMessagesController#create - Account ID: #{Current.account.id}, User: #{Current.user&.id}")
    
    unless Current.user.present?
      Rails.logger.warn("ScheduledMessagesController#create - Usuário não autenticado")
      render json: { error: 'Usuário não autenticado' }, status: :unauthorized
      return
    end

    # Buscar conversa - pode vir de params direto ou de scheduled_message
    conv = conversation
    Rails.logger.info("ScheduledMessagesController#create - Conversation: #{conv&.id}, Account: #{conv&.account_id}")
    
    unless conv
      Rails.logger.error("ScheduledMessagesController#create - Conversa não encontrada. Conversation ID: #{params[:conversation_id] || params.dig(:scheduled_message, :conversation_id)}")
      render json: { error: 'Conversa não encontrada' }, status: :not_found
      return
    end

    # Validar que a conversation pertence ao account
    unless conv.account_id == Current.account.id
      Rails.logger.error("ScheduledMessagesController#create - Conversation #{conv.id} não pertence ao account #{Current.account.id}")
      render json: { error: 'Conversa não encontrada' }, status: :not_found
      return
    end

    # Sempre usar o inbox da conversation (simplificado)
    inbox_to_use = conv.inbox
    Rails.logger.info("ScheduledMessagesController#create - Usando inbox da conversation: #{inbox_to_use.id}")
    
    unless inbox_to_use
      Rails.logger.error("ScheduledMessagesController#create - Conversation não tem inbox associado")
      render json: { error: 'Conversa não tem inbox associado' }, status: :unprocessable_entity
      return
    end

    message_content = scheduled_message_params[:message] || params[:message]
    scheduled_at_param = scheduled_message_params[:scheduled_at] || params[:scheduled_at]
    
    Rails.logger.info("ScheduledMessagesController#create - Message length: #{message_content&.length}, Scheduled at: #{scheduled_at_param}")
    
    @scheduled_message = ScheduledMessages::CreateService.new(
      conversation: conv,
      inbox: inbox_to_use,
      message: message_content,
      scheduled_at: scheduled_at_param,
      user: Current.user
    ).perform
    
    Rails.logger.info("ScheduledMessagesController#create - Scheduled message criado com sucesso: #{@scheduled_message.id}")
    render json: scheduled_message_json(@scheduled_message), status: :created
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error("ScheduledMessagesController#create - RecordNotFound: #{e.class.name}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    render json: { error: 'Conversa ou inbox não encontrado' }, status: :not_found
  rescue ArgumentError => e
    Rails.logger.error("ScheduledMessagesController#create - ArgumentError: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    render json: { error: e.message }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error("ScheduledMessagesController#create - StandardError: #{e.class.name}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    render json: { error: "Erro ao criar mensagem agendada: #{e.message}" }, status: :internal_server_error
  end

  def update
    @scheduled_message.update!(scheduled_message_params)
  end

  def destroy
    @scheduled_message.update!(status: :cancelled)
    head :ok
  end

  def inboxes
    @inboxes = Current.account.inboxes
  end

  private

  def conversation
    conversation_id = params[:conversation_id] || params.dig(:scheduled_message, :conversation_id)
    return nil unless conversation_id.present?
    
    # Buscar conversation e garantir que pertence ao account
    @conversation ||= Current.account.conversations.find_by(id: conversation_id)
    
    if @conversation && @conversation.account_id != Current.account.id
      Rails.logger.error("ScheduledMessagesController#conversation - Conversation #{@conversation.id} não pertence ao account #{Current.account.id}")
      @conversation = nil
    end
    
    @conversation
  end

  # Método removido - sempre usamos inbox da conversation

  def scheduled_message
    @scheduled_message ||= ScheduledMessage.find(params[:id])
  end

  def scheduled_message_params
    params.require(:scheduled_message).permit(:message, :scheduled_at, :inbox_id, :conversation_id)
  end

  def scheduled_message_json(scheduled_message)
    {
      id: scheduled_message.id,
      conversation_id: scheduled_message.conversation_id,
      inbox_id: scheduled_message.inbox_id,
      message: scheduled_message.message,
      scheduled_at: scheduled_message.scheduled_at&.iso8601,
      status: scheduled_message.status,
      waha_session_name: scheduled_message.waha_session_name,
      sent_at: scheduled_message.sent_at&.iso8601,
      error_message: scheduled_message.error_message,
      created_at: scheduled_message.created_at&.iso8601,
      updated_at: scheduled_message.updated_at&.iso8601
    }
  end

  def check_authorization
    if action_name == 'inboxes'
      # Para inboxes, verificamos permissão diretamente
      unless Current.account_user&.agent? || Current.account_user&.administrator?
        raise Pundit::NotAuthorizedError
      end
    elsif action_name == 'index'
      # Para index, verificamos permissão diretamente sem precisar de conversation
      unless Current.account_user&.agent? || Current.account_user&.administrator?
        raise Pundit::NotAuthorizedError
      end
    else
      # Para outras ações, precisamos de uma conversation ou scheduled_message
      authorize(@scheduled_message || ScheduledMessage.new(conversation: conversation || Current.account.conversations.first))
    end
  end
end

