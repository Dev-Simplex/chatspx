namespace :conversations do
  desc 'Limpa waiting_since orfaos em conversas com status=resolved. ' \
       'DRY-RUN por padrao; passe EXECUTE=true para aplicar.'
  task clear_waiting_since_resolved: :environment do
    candidates = Conversation.where(status: :resolved).where.not(waiting_since: nil)
    count = candidates.count
    puts "\n== Saneamento waiting_since em conversas resolved =="
    puts "Conversas elegiveis: #{count}"
    next if count.zero?

    candidates.order(updated_at: :desc).limit(5).pluck(:id, :display_id, :waiting_since).each do |id, did, ws|
      puts "  id=#{id} display=##{did} waiting_since=#{ws.iso8601}"
    end

    if ENV['EXECUTE'] != 'true'
      puts "\nDRY-RUN. Para aplicar: EXECUTE=true bundle exec rails conversations:clear_waiting_since_resolved"
      next
    end

    affected = Conversation.transaction do
      Conversation.where(status: :resolved).where.not(waiting_since: nil)
                  .update_all(waiting_since: nil) # rubocop:disable Rails/SkipsModelValidations
    end
    puts "Linhas atualizadas: #{affected}"
  end
end
