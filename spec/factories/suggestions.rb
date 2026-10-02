# frozen_string_literal: true

FactoryBot.define do
  factory :suggestion do
    account
    user
    name { 'Fulano de Tal' }
    company { 'Imobiliaria Teste' }
    content { 'Seria bom poder filtrar a lista por etiqueta.' }
    source { :in_app }
    status { :nova }
  end
end
