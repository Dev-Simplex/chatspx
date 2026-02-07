# frozen_string_literal: true

class Api::V1::Accounts::ScheduledMessagesController < Api::V1::Accounts::BaseController
  before_action :set_scheduled_message, except: [:index, :create, :inboxes]
  before_action :check_authorization

  def index
    scope = policy_scope(ScheduledMessage).upcoming
    scope = scope.where(conversation_id: params[:conversation_id]) if params[:conversation_id].present?
    @scheduled_messages = scope
    render 'api/v1/accounts/scheduled_messages/index', formats: [:json]
  end

  def show
    render 'api/v1/accounts/scheduled_messages/show', formats: [:json]
  end

  def create
    unless Current.user.present?
      render json: { error: 'Usuário não autenticado' }, status: :unauthorized
      return
    end

    unless Current.account.present?
      render json: { error: 'Conta não encontrada' }, status: :unauthorized
      return
    end

    sm_params = scheduled_message_params
    unless sm_params
      render json: { error: 'Parâmetros inválidos: envie { scheduled_message: { conversation_id, message, scheduled_at } }' },
             status: :unprocessable_entity
      return
    end

    conv = conversation
    unless conv
      render json: { error: 'Conversa não encontrada' }, status: :not_found
      return
    end

    unless conv.account_id == Current.account.id
      render json: { error: 'Conversa não encontrada' }, status: :not_found
      return
    end

    inbox_to_use = conv.inbox
    unless inbox_to_use
      render json: { error: 'Conversa não tem inbox associado' }, status: :unprocessable_entity
      return
    end

    message_content = sm_params[:message] || sm_params['message'] || params[:message]
    scheduled_at_param = sm_params[:scheduled_at] || sm_params['scheduled_at'] || params[:scheduled_at]

    raw_sm = params[:scheduled_message] || params['scheduled_message']
    raw_attachments = raw_sm.present? && (raw_sm[:attachments] || raw_sm['attachments'])
    attachments_param =
      sm_params[:attachments] ||
      sm_params['attachments'] ||
      params.dig(:scheduled_message, :attachments) ||
      params.dig('scheduled_message', 'attachments') ||
      raw_attachments
    attachments_list = Array(attachments_param || []).compact.select do |a|
      a.is_a?(String) || a.respond_to?(:tempfile)
    end

    @scheduled_message = ScheduledMessages::CreateService.new(
      conversation: conv,
      inbox: inbox_to_use,
      message: message_content,
      scheduled_at: scheduled_at_param,
      user: Current.user,
      attachments: attachments_list
    ).perform

    render 'api/v1/accounts/scheduled_messages/create', formats: [:json], status: :created
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Conversa ou inbox não encontrado' }, status: :not_found
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActionController::ParameterMissing => e
    render json: { error: "Parâmetros inválidos: #{e.message}" }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error "ScheduledMessagesController#create: #{e.class}: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
    msg = e.message.to_s
    msg += ' (rode db:migrate se a tabela scheduled_messages estiver desatualizada)' if msg.include?('column') && msg.include?('does not exist')
    render json: {
      error: "Erro ao criar mensagem agendada: #{msg}",
      error_class: e.class.name
    }, status: :internal_server_error
  end

  def update
    sm_params = scheduled_message_params
    unless sm_params.present?
      render json: { error: 'Parâmetros inválidos' }, status: :unprocessable_entity
      return
    end
    @scheduled_message.update!(sm_params)
    render 'api/v1/accounts/scheduled_messages/update', formats: [:json]
  end

  def destroy
    @scheduled_message.update!(status: :cancelled)
    head :ok
  end

  def inboxes
    authorize(ScheduledMessage.new, :inboxes?)
    @inboxes = Current.account.inboxes
    render 'api/v1/accounts/scheduled_messages/inboxes', formats: [:json]
  end

  private

  def conversation
    conversation_id = params[:conversation_id] || params.dig(:scheduled_message, :conversation_id)
    return nil unless conversation_id.present?

    @conversation ||= Current.account.conversations.find_by(id: conversation_id)
    @conversation ||= Current.account.conversations.find_by(display_id: conversation_id)
    @conversation = nil if @conversation && @conversation.account_id != Current.account.id
    @conversation
  end

  def set_scheduled_message
    @scheduled_message = policy_scope(ScheduledMessage).find(params[:id])
  end

  def scheduled_message_params
    raw = params[:scheduled_message] || params['scheduled_message']
    return nil if raw.blank?

    if raw.is_a?(ActionController::Parameters)
      raw.permit(:message, :scheduled_at, :inbox_id, :conversation_id, attachments: [])
    elsif raw.respond_to?(:to_unsafe_h)
      ActionController::Parameters.new(raw.to_unsafe_h).permit(:message, :scheduled_at, :inbox_id, :conversation_id, attachments: [])
    else
      ActionController::Parameters.new(raw.to_h).permit(:message, :scheduled_at, :inbox_id, :conversation_id, attachments: [])
    end
  end

  def check_authorization
    case action_name
    when 'inboxes'
      authorize(ScheduledMessage.new, :inboxes?)
    when 'index', 'create'
      authorize(ScheduledMessage.new, action_name == 'create' ? :create? : :index?)
    else
      authorize(@scheduled_message)
    end
  end
end
