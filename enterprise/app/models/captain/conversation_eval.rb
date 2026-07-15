class Captain::ConversationEval < ApplicationRecord
  self.table_name = 'captain_conversation_evals'

  belongs_to :account
  belongs_to :conversation, class_name: '::Conversation'
  belongs_to :captain_assistant, class_name: 'Captain::Assistant', optional: true

  validates :conversation_id, uniqueness: true

  scope :for_account, ->(account_id) { where(account_id: account_id) }
  scope :recent, -> { order(avaliado_em: :desc) }
  scope :em_escopo, -> { where(representatividade: 'atendimento_real') }

  # Gate por conta (opt-in, multi-tenant). Comportamento novo nunca liga sozinho:
  # a conta precisa de custom_attributes['eval_enabled'] = true.
  def self.enabled_for?(account)
    ActiveModel::Type::Boolean.new.cast(account&.custom_attributes&.dig('eval_enabled'))
  end
end
