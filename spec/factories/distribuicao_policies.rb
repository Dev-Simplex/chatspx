# frozen_string_literal: true

FactoryBot.define do
  factory :distribuicao_policy, class: 'Spx::Distribuicao::Policy' do
    account
    team
    ativo { true }
    modo { 'rodizio' }
    modo_posse { 'assignee' }
    continuidade_ativa { false }
    continuidade_dias { 30 }
    pool { [] }
    sla_assumir_minutos { 30 }

    # Repasse por SLA ligado. Nasce desligado no banco de propósito (ninguém que já roda hoje
    # muda de comportamento), então o teste que quer a AÇÃO pede este trait explicitamente.
    trait :com_repasse do
      repasse_automatico { true }
      max_repasses { 2 }
    end

    trait :fila do
      modo { 'fila' }
    end

    trait :designacao do
      modo_posse { 'designacao' }
    end
  end
end
