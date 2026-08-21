# Dedicated controller for the star/unstar message endpoint.
# Splits the toggle behavior into explicit, idempotent verbs:
#   - POST   /messages/:message_id/star  -> create  (sets starred = true)
#   - DELETE /messages/:message_id/star  -> destroy (sets starred = false)
#
# Both actions are idempotent: calling POST on an already-starred message,
# or DELETE on an already-unstarred message, is a no-op that still returns
# 200 with the current state. The MESSAGE_UPDATED event is only dispatched
# when the persisted state actually changes, so subscribers (ActionCable,
# webhooks) are not spammed with redundant notifications.
#
# Pattern: mirrors the dedicated Messages::ReactionsController
# (see reactions_controller.rb) — Chatwoot uses per-action controllers
# for narrow, side-effect-heavy operations on messages.
class Api::V1::Accounts::Conversations::Messages::StarController < Api::V1::Accounts::Conversations::BaseController
  def create
    set_starred(true)
  end

  def destroy
    set_starred(false)
  end

  private

  # O MESSAGE_UPDATED sai do PROPRIO modelo: `Message#dispatch_update_event`
  # (after_update_commit) ja dispara, e ja sai cedo quando `previous_changes` esta vazio — que
  # e exatamente a garantia de idempotencia descrita no topo. O disparo explicito que existia
  # aqui era um SEGUNDO evento para a mesma alteracao: os assinantes (ActionCable, webhooks)
  # recebiam tudo em duplicata, justo o que o comentario acima diz querer evitar.
  # Nenhum listener de `message_updated` le `performed_by`, entao nada se perde; e o evento do
  # modelo ainda carrega `previous_changes`, que o daqui nao levava.
  def set_starred(value)
    message.update!(starred: value) if message.starred? != value
    render json: { id: message.id, starred: message.starred }
  end

  def message
    @message ||= @conversation.messages.find(params[:message_id])
  end
end
