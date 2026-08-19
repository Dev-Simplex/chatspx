# frozen_string_literal: true

FactoryBot.define do
  factory :distribuicao_log, class: 'Spx::Distribuicao::Log' do
    # O modelo não declara `belongs_to :account` (o log sobrevive à conversa apagada), então a
    # conta entra pela coluna e é derivada da conversa.
    conversation
    account_id { conversation.account_id }
    motivo { 'rodizio' }
    candidatos { [] }
    repasse_n { 0 }

    # Designação ABERTA de modo push: é o estado que o SLA mede — atribuído e ainda sem
    # primeira resposta.
    trait :aberta do
      status { 'designado' }
      designado_em { 40.minutes.ago }
      policy_snapshot { { 'modo_posse' => 'assignee' } }
    end
  end
end
