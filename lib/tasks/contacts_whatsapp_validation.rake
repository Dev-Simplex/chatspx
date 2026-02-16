namespace :contacts do
  desc 'Validate WhatsApp numbers for contacts in an account. Usage: rake contacts:validate_whatsapp[ACCOUNT_ID,BATCH_SIZE,ONLY_MISSING]'
  task :validate_whatsapp, %i[account_id batch_size only_missing] => :environment do |_task, args|
    account_id = args[:account_id]
    raise 'account_id is required' if account_id.blank?

    batch_size = (args[:batch_size] || 200).to_i
    only_missing = args[:only_missing].to_s != 'false'

    Contacts::WhatsappValidationJob.perform_later(
      account_id,
      batch_size: batch_size,
      only_missing: only_missing
    )
  end
end
