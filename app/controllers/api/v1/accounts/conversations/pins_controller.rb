# frozen_string_literal: true

# Fixar/desfixar a conversa no topo da lista de QUEM chamou.
#
# Mora num controller próprio (e não junto de `toggle_status`/`toggle_priority`)
# por dois motivos: o ConversationsController já passa do limite de tamanho do
# rubocop, e aqui herdamos de graça os guards de time e de isolamento por agente
# do Conversations::BaseController.
#
# Não há autorização extra além da herdada: o efeito é exclusivamente sobre a
# lista do próprio usuário — fixar não muda a tela de mais ninguém.
class Api::V1::Accounts::Conversations::PinsController < Api::V1::Accounts::Conversations::BaseController
  def toggle
    render json: { pinned: @conversation.toggle_pin_for(Current.user) }
  end
end
