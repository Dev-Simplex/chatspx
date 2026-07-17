# == Schema Information
#
# Table name: conversation_takeover_requests
#
#  id                :bigint           not null, primary key
#  reason            :text
#  resolution_source :integer
#  responded_at      :datetime
#  response_note     :text
#  status            :integer          default("pending"), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  conversation_id   :bigint           not null
#  owner_id          :bigint
#  responded_by_id   :bigint
#  requester_id      :bigint           not null
#
# Indexes
#
#  idx_takeover_requests_account_status    (account_id,status)
#  idx_takeover_requests_conversation      (conversation_id)
#  idx_takeover_requests_owner_status      (owner_id,status)
#  idx_takeover_requests_requester_status  (requester_id,status)
#  idx_takeover_requests_unique_pending    (conversation_id,requester_id) UNIQUE WHERE (status = 0)
#
class ConversationTakeoverRequest < ApplicationRecord
  # Tabela PRÓPRIA e não Notification, de propósito: o
  # Notification::RemoveDuplicateNotificationJob apaga todas as notificações do
  # mesmo user_id + primary_actor_id IGNORANDO o tipo, e roda a cada criação —
  # o pedido pendente morreria na próxima mensagem da conversa. A Notification é
  # só o aviso; o pedido sobrevive aqui.
  belongs_to :account
  belongs_to :conversation
  belongs_to :requester, class_name: 'User'
  # optional: a FK é ON DELETE NULLIFY — o pedido sobrevive ao agente sair.
  belongs_to :owner, class_name: 'User', optional: true
  belongs_to :responded_by, class_name: 'User', optional: true

  enum status: { pending: 0, approved: 1, denied: 2, cancelled: 3, superseded: 4 }
  # Os três juntos importam: responded_by_id sozinho não distingue "o dono
  # aprovou" de "um admin que por acaso é o dono" de "o sistema encerrou".
  enum resolution_source: { owner: 0, admin: 1, system: 2 }, _prefix: :resolved_by

  validates :account_id, presence: true
  validates :conversation_id, presence: true
  validates :requester_id, presence: true

  scope :incoming_for, ->(user) { where(owner_id: user.id) }
  scope :outgoing_for, ->(user) { where(requester_id: user.id) }

  def close!(status:, source:, responder: nil, note: nil)
    update!(
      status: status,
      resolution_source: source,
      responded_by: responder,
      response_note: note,
      responded_at: Time.current
    )
  end
end
