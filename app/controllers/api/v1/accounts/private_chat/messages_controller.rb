# frozen_string_literal: true

module Api::V1::Accounts::PrivateChat
  class MessagesController < BaseController
    def index
      @messages = message_finder.perform
      render 'api/v1/accounts/private_chat/messages/index'
    end

    def create
      @message = Messages::MessageBuilder.new(Current.user, @conversation, message_params).perform
      broadcast_new_message
      render 'api/v1/accounts/private_chat/messages/create'
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
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
        "private_chat_#{PrivateChat::Config.conversation_id}",
        { event: 'message.created', message: payload }
      )
    end
  end
end
