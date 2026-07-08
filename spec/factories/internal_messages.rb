# frozen_string_literal: true

FactoryBot.define do
  factory :internal_message do
    internal_channel
    user
    content { 'Mensagem interna de teste' }
  end
end
