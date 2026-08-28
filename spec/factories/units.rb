# frozen_string_literal: true

FactoryBot.define do
  # Atenção: `Unit` cria a grade da semana inteira num `after_create`, então uma
  # unidade recém-criada já vem com sete `unit_working_hours`.
  factory :unit do
    account
    sequence(:name) { |n| "Filial #{n}" }
    timezone { 'America/Cuiaba' }
  end

  factory :unit_working_hour do
    unit
    day_of_week { 1 }
    closed_all_day { false }
    open_hour { 8 }
    open_minutes { 0 }
    close_hour { 18 }
    close_minutes { 0 }
  end

  factory :unit_exception do
    unit
    sequence(:name) { |n| "Feriado #{n}" }
    starts_on { Date.new(2026, 12, 25) }
    category { :feriado }
    frequency { :nao_repete }
    closed_all_day { true }
  end
end
