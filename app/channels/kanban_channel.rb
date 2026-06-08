# frozen_string_literal: true

# Canal ActionCable do Kanban (KANBAN-P1-13).
#
# Cliente faz subscribe com:
#   { channel: 'KanbanChannel', kanban_id, account_id, user_id, pubsub_token }
#
# Após auth, stream em:
#   account_<account_id>_kanban_<kanban_id>
#
# Backend (Kanbans::BroadcastService) publica eventos kanban_item.*,
# kanban_stage.*, kanban.* nesse stream após o commit da transação.
class KanbanChannel < ApplicationCable::Channel
  def subscribed
    @current_user = resolve_user
    @current_account = resolve_account
    @kanban = resolve_kanban

    return reject if @current_user.blank? || @current_account.blank? || @kanban.blank?
    return reject unless authorized?

    stream_from kanban_stream
    transmit(event: 'subscribed', data: { kanban_id: @kanban.id, server_seq: current_seq })
  end

  def unsubscribed
    # cleanup no-op
  end

  private

  def authorized?
    KanbanPolicy.new(pundit_user, @kanban).show?
  end

  def pundit_user
    account_user = @current_account.account_users.find_by(user_id: @current_user.id)
    Struct.new(:user, :account_user, :account).new(@current_user, account_user, @current_account)
  end

  def resolve_user
    User.find_by(pubsub_token: params[:pubsub_token], id: params[:user_id])
  end

  def resolve_account
    return nil if @current_user.blank?

    @current_user.accounts.find_by(id: params[:account_id])
  end

  def resolve_kanban
    return nil if @current_account.blank?

    @current_account.kanbans.find_by(id: params[:kanban_id])
  end

  def kanban_stream
    "account_#{@current_account.id}_kanban_#{@kanban.id}"
  end

  def current_seq
    Kanbans::BroadcastService.current_seq(@kanban.id)
  end
end
