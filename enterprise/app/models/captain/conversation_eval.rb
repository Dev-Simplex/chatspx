class Captain::ConversationEval < ApplicationRecord
  self.table_name = 'captain_conversation_evals'

  belongs_to :account
  belongs_to :conversation, class_name: '::Conversation'
  belongs_to :captain_assistant, class_name: 'Captain::Assistant', optional: true
  belongs_to :episode, class_name: 'Captain::ConversationEpisode', optional: true

  # Unidade episódio: 1 eval por episódio (N por conversa). Unidade conversa (legado):
  # 1 eval por conversa.
  validates :conversation_id, uniqueness: true, if: -> { episode_id.nil? }
  validates :episode_id, uniqueness: true, allow_nil: true

  scope :for_account, ->(account_id) { where(account_id: account_id) }
  scope :recent, -> { order(avaliado_em: :desc) }
  scope :em_escopo, -> { where(representatividade: 'atendimento_real') }
  scope :por_episodio, -> { where.not(episode_id: nil) }

  # Gate por conta (opt-in, multi-tenant). Comportamento novo nunca liga sozinho:
  # a conta precisa de custom_attributes['eval_enabled'] = true.
  def self.enabled_for?(account)
    ActiveModel::Type::Boolean.new.cast(account&.custom_attributes&.dig('eval_enabled'))
  end

  # Unidade de avaliação da conta: 'episode' (Eval 2.0) ou 'conversation' (legado).
  # Opt-in por conta — o switch é custom_attributes['eval_unit'] = 'episode'.
  def self.episode_unit?(account)
    account&.custom_attributes&.dig('eval_unit') == 'episode'
  end
end
