# frozen_string_literal: true

FactoryBot.define do
  factory :inbox_isolation_exemption do
    inbox
    # o isento precisa pertencer à conta da caixa (validação do modelo)
    user { create(:user, account: inbox.account) }
    isolation_type { 'agent_message' }
  end
end
