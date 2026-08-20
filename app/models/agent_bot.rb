# == Schema Information
#
# Table name: agent_bots
#
#  id                   :bigint           not null, primary key
#  bot_config           :jsonb
#  bot_type             :integer          default("webhook")
#  description          :string
#  name                 :string
#  outgoing_url         :string
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint
#  captain_assistant_id :bigint
#  secret               :string
#
# Indexes
#
#  index_agent_bots_on_account_id            (account_id)
#  index_agent_bots_on_captain_assistant_id  (captain_assistant_id) UNIQUE WHERE (captain_assistant_id IS NOT NULL)
#
# Foreign Keys
#
#  fk_rails_...  (captain_assistant_id => captain_assistants.id) ON DELETE => nullify
#

class AgentBot < ApplicationRecord
  include AccessTokenable
  include Avatarable

  include WebhookSecretable

  scope :accessible_to, lambda { |account|
    account_id = account&.id
    where(account_id: [nil, account_id])
  }

  has_many :agent_bot_inboxes, dependent: :destroy_async
  has_many :inboxes, through: :agent_bot_inboxes
  has_many :messages, as: :sender, dependent: :nullify
  has_many :platform_app_permissibles, as: :permissible, dependent: :destroy
  has_many :assigned_conversations, class_name: 'Conversation',
                                    foreign_key: :assignee_agent_bot_id,
                                    dependent: :nullify,
                                    inverse_of: :assignee_agent_bot
  belongs_to :account, optional: true
  belongs_to :captain_assistant, class_name: 'Captain::Assistant', optional: true
  enum bot_type: { webhook: 0, captain: 1 }

  validates :outgoing_url, length: { maximum: Limits::URL_LENGTH_LIMIT }
  validates :captain_assistant_id, presence: true, if: :captain?
  validates :captain_assistant_id, absence: true, if: :webhook?
  validates :outgoing_url, absence: true, if: :captain? # espelho NUNCA tem webhook URL

  def available_name
    name
  end

  def push_event_data(inbox = nil)
    {
      id: id,
      name: name,
      avatar_url: avatar_url.presence || captain_assistant&.push_event_data&.dig(:avatar_url) || inbox&.avatar_url,
      type: 'agent_bot',
      # Discrimina espelho captain (IA) de bot webhook. O front filtra abas IA /
      # Não Atribuídas por este flag para casar com o backend (bot_type = 1),
      # já que `type` é 'agent_bot' para QUALQUER bot. Campo aditivo: não quebra
      # consumidores que leem id/name/type/avatar_url.
      is_captain: captain?
    }
  end

  def webhook_data
    {
      id: id,
      name: name,
      type: 'agent_bot'
    }
  end

  def system_bot?
    account.nil?
  end
end

AgentBot.include_mod_with('Audit::AgentBot')
