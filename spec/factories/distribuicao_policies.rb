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
    max_repasses { 2 }

    # Espelho no Vista: o card do lead já existe no nome do corretor e o DELETE de lá é 401,
    # então esta política NÃO repassa — o SLA volta a ser só medida.
    trait :espelho_vista do
      espelho_vista { true }
    end

    trait :fila do
      modo { 'fila' }
    end

    trait :designacao do
      modo_posse { 'designacao' }
    end
  end
end
