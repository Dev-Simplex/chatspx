namespace :tracking do
  desc 'Bloco 1.18 — provisiona as definições de origem nas contas. Idempotente: rodar de novo não duplica. ACCOUNT_ID=<id> limita a uma conta.'
  task seed_origin_definitions: :environment do
    escopo = ENV['ACCOUNT_ID'].present? ? Account.where(id: ENV['ACCOUNT_ID']) : Account.all
    total_contas = 0
    total_criadas = 0

    escopo.find_each do |account|
      criadas = Tracking::OriginDefinitionsSeeder.new(account).perform
      total_contas += 1
      total_criadas += criadas.size
      Rails.logger.info { "[1.18] conta #{account.id}: #{criadas.size} definições criadas" }
    end

    puts "[1.18] #{total_contas} conta(s) processada(s), #{total_criadas} definição(ões) criada(s)."
  end
end
