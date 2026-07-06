# frozen_string_literal: true

namespace :flows do
  desc 'Backfill macros + automation_rules into flows. ACCOUNT_ID=<id> [DRY_RUN=true]'
  task backfill: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID'))
    dry_run = ENV['DRY_RUN'] == 'true'
    result = Flows::BackfillService.new(account: account, dry_run: dry_run).perform
    label = dry_run ? 'DRY-RUN (nada gravado)' : 'APLICADO'
    puts "Backfill #{label} — conta ##{account.id}: #{result}"
  end

  # Cutover explícito (o gate NÃO é o bitmask de features — está no limite no ChatSPX).
  desc 'Liga o motor Flow para uma conta (após validar o backfill). ACCOUNT_ID=<id>'
  task enable_engine: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID'))
    account.update!(internal_attributes: account.internal_attributes.merge('flows_engine_enabled' => true))
    puts "Motor Flow LIGADO — conta ##{account.id} (as AutomationRules antigas param; os Flows assumem)"
  end

  desc 'Desliga o motor Flow para uma conta (volta às AutomationRules). ACCOUNT_ID=<id>'
  task disable_engine: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID'))
    account.update!(internal_attributes: account.internal_attributes.merge('flows_engine_enabled' => false))
    puts "Motor Flow DESLIGADO — conta ##{account.id}"
  end
end
