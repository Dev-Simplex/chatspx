FactoryBot.define do
  factory :webhook do
    account_id { 1 }
    # Bloco 4.13: era `inbox_id { 1 }` fixo — um id solto, quase sempre de outra conta ou
    # inexistente. Enquanto a entrega ignorava o campo isso nao aparecia; com o filtro
    # valendo, todo spec ficaria escopado por acidente a uma inbox que nao existe. Webhook
    # sem inbox e o caso comum e e o comportamento efetivo de antes.
    inbox_id { nil }
    url { 'https://api.chatwoot.com' }
    name { 'My Webhook' }
    subscriptions do
      %w[
        conversation_status_changed
        conversation_updated
        conversation_created
        contact_created
        contact_updated
        message_created
        message_updated
        webwidget_triggered
      ]
    end
  end
end
