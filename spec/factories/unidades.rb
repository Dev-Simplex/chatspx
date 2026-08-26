FactoryBot.define do
  factory :spx_unidade, class: 'Spx::Unidade' do
    association :account
    sequence(:slug) { |n| "unidade-#{n}" }
    sequence(:nome) { |n| "Unidade #{n}" }
    cidade { 'Cuiabá' }
    uf { 'MT' }
    timezone { 'America/Cuiaba' }
    ativa { true }
  end

  factory :spx_unidade_horario, class: 'Spx::UnidadeHorario' do
    association :unidade, factory: :spx_unidade
    dia_semana { 1 }
    abre { '08:00' }
    fecha { '18:00' }
    fechada { false }
  end

  factory :spx_unidade_excecao, class: 'Spx::UnidadeExcecao' do
    association :account
    data_inicio { Time.zone.today }
    data_fim { Time.zone.today }
    fechada { false }
  end
end
