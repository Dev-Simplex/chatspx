FactoryBot.define do
  factory :conversation_takeover_request do
    account
    conversation
    status { :pending }
    # owner é SNAPSHOT do dono no momento do pedido (ver o model): quem cria o
    # cenário decide, não se deriva de conversation.assignee_id.
    requester { association :user }
    owner { association :user }
  end
end
