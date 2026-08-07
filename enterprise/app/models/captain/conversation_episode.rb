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
  # Desfechos (F3) são DERIVADOS da fronteira do episódio: se a re-segmentação apaga o
  # episódio (mudança de regra/versão — ver o destroy_all do EpisodeSegmenterService),
  # os degraus daquela fronteira deixam de valer. `destroy` em vez de `nullify` porque
  # outcome órfão continuaria entrando nos agregados por account_id, inflando a conversão
  # com episódios que não existem mais. O backfill recalcula sobre a fronteira nova.
  has_many :outcomes, class_name: 'Captain::EpisodeOutcome', foreign_key: :episode_id,
                      inverse_of: :episode, dependent: :destroy

  validates :seq, presence: true, uniqueness: { scope: :conversation_id }
  validates :boundary_reason, inclusion: { in: BOUNDARY_REASONS }

  scope :closed, -> { where.not(ended_at: nil) }
  scope :open_ones, -> { where(ended_at: nil) }
  scope :for_account, ->(account_id) { where(account_id: account_id) }

  def closed?
    ended_at.present?
  end

  # Atendimento EM ANDAMENTO da conversa. É o corte que o runtime da IA usa pra não mandar
  # o fio perpétuo inteiro pro modelo (inbox com lock_to_single_conversation).
  def self.atual(conversation_id)
    open_ones.where(conversation_id: conversation_id).reorder(seq: :desc).first
  end

  # Atendimentos já encerrados, do mais recente pro mais antigo.
  def self.anteriores(conversation_id, limite:)
    closed.where(conversation_id: conversation_id).reorder(seq: :desc).limit(limite).to_a
  end

  # F4.2 (Eval humano): notas privadas de gestores com o marcador #eval que pertencem
  # a ESTE episódio. Duas formas de vínculo: EXPLÍCITO (content_attributes.eval_episode_id,
  # setado pelo modal "Avaliar atendimento" — vale pra qualquer episódio, até antigo) e
  # TEMPORAL (nota solta sem âncora: janela do início deste episódio até o início do
  # seguinte, porque o gestor costuma comentar logo depois do fato).
  # Message#content_attributes é `store ... coder: JSON` sobre coluna jsonb — DUPLA
  # serialização: o jsonb guarda uma STRING JSON. O `#>> '{}'` desembrulha o scalar
  # pra texto (e é inócuo quando o valor é objeto de verdade) antes do cast/extração.
  EPISODE_ANCHOR_SQL = "(content_attributes #>> '{}')::jsonb ->> 'eval_episode_id'".freeze

  def human_annotations
    upper = self.class.where(conversation_id: conversation_id, seq: seq + 1).pick(:started_at) || Time.current
    base = conversation.messages
                       .where(private: true, sender_type: 'User')
                       .where('content ILIKE ?', '%#eval%')
    janela = base.where(created_at: started_at..upper)
                 .where("COALESCE(#{EPISODE_ANCHOR_SQL}, '') = ''")
    explicitas = base.where("#{EPISODE_ANCHOR_SQL} = ?", id.to_s)
    base.where(id: janela.select(:id)).or(base.where(id: explicitas.select(:id))).reorder(:created_at)
  end
end
