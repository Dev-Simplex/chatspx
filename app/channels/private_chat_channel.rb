# frozen_string_literal: true

class PrivateChatChannel < ApplicationCable::Channel
  def subscribed
    token = params[:token]
    payload = PrivateChat::TokenService.decode(token)

    if payload.blank? || payload[:conversation_id].to_i != PrivateChat::Config.conversation_id
      reject
      return
    end

    stream_from "private_chat_#{PrivateChat::Config.account_id}_#{PrivateChat::Config.conversation_id}"
  end

  def unsubscribed
    stop_all_streams
  end
end
