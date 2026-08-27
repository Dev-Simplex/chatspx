FactoryBot.define do
  factory :social_publicacao, class: 'Spx::Social::Publicacao' do
    association :account
    inbox { association :inbox, account: account }
    sequence(:external_id) { |n| "publicacao-#{n}" }
    tipo { 'REELS' }
  end

  factory :social_comentario, class: 'Spx::Social::Comentario' do
    association :account
    inbox { association :inbox, account: account }
    sequence(:external_id) { |n| "comentario-#{n}" }
    sequence(:autor_username) { |n| "cliente#{n}" }
    texto { 'No domingo que horas abre a loja' }
    proprio { false }
    comentado_em { Time.current }
  end
end
