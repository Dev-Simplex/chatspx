# Helpers privados para tasks de saneamento de waiting_since.
module ConversationsWaitingSinceTasks
  module_function

  def run_resolved_cleanup
    candidates = Conversation.where(status: :resolved).where.not(waiting_since: nil)
    count = candidates.count
    puts "\n== Saneamento waiting_since em conversas resolved =="
    puts "Conversas elegiveis: #{count}"
    return if count.zero?

    print_resolved_sample(candidates)

    if ENV['EXECUTE'] != 'true'
      puts "\nDRY-RUN. Para aplicar: EXECUTE=true bundle exec rails conversations:clear_waiting_since_resolved"
      return
    end

    affected = Conversation.transaction do
      Conversation.where(status: :resolved).where.not(waiting_since: nil)
                  .update_all(waiting_since: nil) # rubocop:disable Rails/SkipsModelValidations
    end
    puts "Linhas atualizadas: #{affected}"
  end

  def run_open_zero_incoming_realign
    base_scope = open_zero_incoming_scope
    count = base_scope.count
    puts "\n== Realinhamento waiting_since em conversas open zero-incoming =="
    puts "Conversas elegiveis: #{count}"
    return if count.zero?

    print_open_sample(base_scope)

    if ENV['EXECUTE'] != 'true'
      puts "\nDRY-RUN. Para aplicar: EXECUTE=true bundle exec rails conversations:clear_waiting_since_open_zero_incoming"
      return
    end

    affected = Conversation.transaction do
      base_scope.update_all('waiting_since = first_reply_created_at') # rubocop:disable Rails/SkipsModelValidations
    end
    puts "Linhas atualizadas: #{affected}"
  end

  def open_zero_incoming_scope
    no_incoming_sql = 'NOT EXISTS (SELECT 1 FROM messages ' \
                      'WHERE messages.conversation_id = conversations.id AND messages.message_type = 0)'
    Conversation.where(status: :open)
                .where.not(waiting_since: nil)
                .where.not(first_reply_created_at: nil)
                .where(no_incoming_sql)
  end

  def print_resolved_sample(scope)
    scope.order(updated_at: :desc).limit(5).pluck(:id, :display_id, :waiting_since).each do |id, did, ws|
      puts "  id=#{id} display=##{did} waiting_since=#{ws.iso8601}"
    end
  end

  def print_open_sample(scope)
    sample = scope.order(updated_at: :desc).limit(5)
                  .pluck(:id, :display_id, :waiting_since, :first_reply_created_at)
    sample.each do |id, did, ws, fr|
      puts "  id=#{id} display=##{did} waiting_since=#{ws.iso8601} first_reply=#{fr.iso8601}"
    end
  end
end

namespace :conversations do
  desc 'Limpa waiting_since orfaos em conversas com status=resolved. ' \
       'DRY-RUN por padrao; passe EXECUTE=true para aplicar.'
  task clear_waiting_since_resolved: :environment do
    ConversationsWaitingSinceTasks.run_resolved_cleanup
  end

  desc 'Realinha waiting_since em conversas open com zero incoming (proativas). ' \
       'Usa first_reply_created_at como baseline. DRY-RUN; passe EXECUTE=true para aplicar.'
  task clear_waiting_since_open_zero_incoming: :environment do
    ConversationsWaitingSinceTasks.run_open_zero_incoming_realign
  end
end
