# == Schema Information
#
# Table name: inbox_members
#
#  id         :integer          not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  inbox_id   :integer          not null
#  user_id    :integer          not null
#
# Indexes
#
#  index_inbox_members_on_inbox_id              (inbox_id)
#  index_inbox_members_on_inbox_id_and_user_id  (inbox_id,user_id) UNIQUE
#

class InboxMember < ApplicationRecord
  validates :inbox_id, presence: true
  validates :user_id, presence: true
  validates :user_id, uniqueness: { scope: :inbox_id }

  belongs_to :user
  belongs_to :inbox

  after_create :add_agent_to_round_robin
  after_destroy :remove_agent_from_round_robin
  after_destroy :remove_isolation_exemptions
  after_commit :invalidate_member_tokens_cache

  private

  def invalidate_member_tokens_cache
    Rails.cache.delete("inbox:#{inbox_id}:member_pubsub_tokens")
  end

  def add_agent_to_round_robin
    ::AutoAssignment::InboxRoundRobinService.new(inbox: inbox).add_agent_to_queue(user_id)
  end

  def remove_agent_from_round_robin
    ::AutoAssignment::InboxRoundRobinService.new(inbox: inbox).remove_agent_from_queue(user_id) if inbox.present?
  end

  # Sair da caixa (por remoção direta ou porque o agente saiu da conta — o
  # Agents::DestroyJob destrói os inbox_members) leva a isenção junto. Sem isto a linha
  # sobrevive apontando para quem não é mais membro e, numa readmissão, devolve a isenção
  # em silêncio — o erro cairia justo para o lado de vazar.
  def remove_isolation_exemptions
    InboxIsolationExemption.where(inbox_id: inbox_id, user_id: user_id).destroy_all
  end
end

InboxMember.include_mod_with('Audit::InboxMember')
