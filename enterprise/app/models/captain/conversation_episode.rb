# Episódio de atendimento (Eval 2.0 F1): um ciclo delimitado de atendimento dentro
# da conversa perpétua do contato. É a unidade de avaliação do eval — o juiz julga
# episódios fechados, nunca o blob da conversa.
class Captain::ConversationEpisode < ApplicationRecord
  self.table_name = 'captain_conversation_episodes'

  BOUNDARY_REASONS = %w[resolve gap hsm_campanha aberto].freeze

  belongs_to :account
  belongs_to :conversation, class_name: '::Conversation'
  has_one :eval, class_name: 'Captain::ConversationEval', foreign_key: :episode_id,
                 inverse_of: :episode, dependent: :nullify

  validates :seq, presence: true, uniqueness: { scope: :conversation_id }
  validates :boundary_reason, inclusion: { in: BOUNDARY_REASONS }

  scope :closed, -> { where.not(ended_at: nil) }
  scope :open_ones, -> { where(ended_at: nil) }
  scope :for_account, ->(account_id) { where(account_id: account_id) }

  def closed?
    ended_at.present?
  end
end
