# frozen_string_literal: true

FactoryBot.define do
  factory :team_supervisor do
    team
    # o supervisor precisa pertencer à conta do time (validação do modelo)
    user { create(:user, account: team.account) }
  end
end
