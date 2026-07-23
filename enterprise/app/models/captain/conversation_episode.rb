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

  # F4.2 (Eval humano): notas privadas de gestores com o marcador #eval que pertencem
  # a ESTE episódio. Duas formas de vínculo: EXPLÍCITO (content_attributes.eval_episode_id,
  # setado pelo modal "Avaliar atendimento" — vale pra qualquer episódio, até antigo) e
  # TEMPORAL (nota solta sem âncora: janela do início deste episódio até o início do
  # seguinte, porque o gestor costuma comentar logo depois do fato).
  def human_annotations
    upper = self.class.where(conversation_id: conversation_id, seq: seq + 1).pick(:started_at) || Time.current
    base = conversation.messages
                       .where(private: true, sender_type: 'User')
                       .where('content ILIKE ?', '%#eval%')
    janela = base.where(created_at: started_at..upper)
                 .where("COALESCE(content_attributes->>'eval_episode_id', '') = ''")
    explicitas = base.where("content_attributes->>'eval_episode_id' = ?", id.to_s)
    base.where(id: janela.select(:id)).or(base.where(id: explicitas.select(:id))).reorder(:created_at)
  end
end
