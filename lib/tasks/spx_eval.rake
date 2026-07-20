# Operação do sistema de eval (LLM-as-a-Judge) — config-first, por conta.
#   spx:eval:enable[account_id]           liga o gate (custom_attributes['eval_enabled'])
#   spx:eval:disable[account_id]          desliga o gate
#   spx:eval:run[account_id,limit]        avalia agora as N conversas mais recentes (backfill)
#   spx:eval:report[account_id]           imprime o agregado atual
namespace :spx do
  namespace :eval do
    desc 'Liga o eval na conta: spx:eval:enable[account_id]'
    task :enable, %i[account_id] => :environment do |_t, args|
      account = Account.find(args[:account_id])
      attrs = account.custom_attributes || {}
      attrs['eval_enabled'] = true
      account.update!(custom_attributes: attrs)
      puts "eval_enabled=true na conta #{account.id} (#{account.name})"
    end

    desc 'Desliga o eval na conta: spx:eval:disable[account_id]'
    task :disable, %i[account_id] => :environment do |_t, args|
      account = Account.find(args[:account_id])
      attrs = account.custom_attributes || {}
      attrs['eval_enabled'] = false
      account.update!(custom_attributes: attrs)
      puts "eval_enabled=false na conta #{account.id} (#{account.name})"
    end

    desc 'Avalia agora as N conversas mais recentes (backfill): spx:eval:run[account_id,limit]'
    task :run, %i[account_id limit] => :environment do |_t, args|
      account = Account.find(args[:account_id])
      unless Captain::ConversationEval.enabled_for?(account)
        abort "Conta #{account.id} está com eval_enabled=false. Rode spx:eval:enable[#{account.id}] antes."
      end

      limit = (args[:limit] || 100).to_i
      captain_inbox_ids = CaptainInbox.where(inbox_id: account.inboxes.select(:id)).distinct.pluck(:inbox_id)
      conversations = account.conversations
                             .where(inbox_id: captain_inbox_ids)
                             .order(last_activity_at: :desc)
                             .limit(limit)
                             .to_a

      puts "Avaliando #{conversations.size} conversa(s) da conta #{account.id}..."
      conversations.each_with_index do |conversation, index|
        Captain::ConversationEvalJob.perform_now(conversation)
        print "\r#{index + 1}/#{conversations.size}"
      end
      puts "\nConcluído. Evals na conta: #{Captain::ConversationEval.for_account(account.id).count}"
    end

    desc 'Imprime o agregado do eval: spx:eval:report[account_id]'
    task :report, %i[account_id] => :environment do |_t, args|
      account = Account.find(args[:account_id])
      evals = Captain::ConversationEval.for_account(account.id)
      puts "== Eval da conta #{account.id} (#{account.name}) =="
      puts "Total avaliadas: #{evals.count}"
      next if evals.count.zero?

      puts "Interesse:      #{evals.where.not(interesse: nil).group(:interesse).count}"
      puts "Intenção:       #{evals.where.not(intencao: nil).group(:intencao).count}"
      puts "Funil:          #{evals.where.not(funil: nil).group(:funil).count}"
      puts "Handoff timing: #{evals.where.not(handoff_timing: nil).group(:handoff_timing).count}"
      falhas = Hash.new(0)
      evals.recent.limit(1000).pluck(:response_findings).each do |findings|
        Array(findings).each { |f| falhas[f['categoria']] += 1 if f.is_a?(Hash) && f['categoria'].present? }
      end
      puts "Top falhas:     #{falhas.sort_by { |_, v| -v }.first(8).to_h}"
    end
  end
end
