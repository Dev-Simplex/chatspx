# frozen_string_literal: true

class Api::V1::Accounts::PrivateChat::MessagesController < Api::V1::Accounts::PrivateChat::BaseController
  def index
    @messages = message_finder.perform.reject { |m| m.content_attributes&.dig('deleted') }
    render 'api/v1/accounts/private_chat/messages/index'
  end

  def create
    @message = Messages::MessageBuilder.new(Current.user, @conversation, message_params).perform
    broadcast_new_message
    render 'api/v1/accounts/private_chat/messages/create'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def clear
    @conversation.messages.find_each do |message|
      message.update!(
        content: I18n.t('conversations.messages.deleted'),
        content_type: :text,
        content_attributes: (message.content_attributes || {}).merge('deleted' => true)
      )
      message.attachments.destroy_all
    end
    ActionCable.server.broadcast(
      "private_chat_#{PrivateChat::Config.account_id}_#{PrivateChat::Config.conversation_id}",
      { event: 'conversation.cleared' }
    )
    head :no_content
  end

  private

  def message_finder
    @message_finder ||= MessageFinder.new(@conversation, params)
  end

  def message_params
    params.permit(:content, :content_type, :private, content_attributes: {}, attachments: [])
  end

  def broadcast_new_message
    payload = @message.push_event_data
    ActionCable.server.broadcast(
      "private_chat_#{PrivateChat::Config.account_id}_#{PrivateChat::Config.conversation_id}",
      { event: 'message.created', message: payload }
    )
  end
end
