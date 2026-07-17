# Operação do sistema de eval (LLM-as-a-Judge) — config-first, por conta.
#   spx:eval:enable[account_id]           liga o gate (custom_attributes['eval_enabled'])
#   spx:eval:disable[account_id]          desliga o gate
#   spx:eval:run[account_id,limit]        avalia agora as N conversas mais recentes (backfill)
#   spx:eval:report[account_id]           imprime o agregado atual (só atendimentos reais)
#   spx:eval:reprocess[account_id,limit]  re-julga evals existentes (preenche representatividade)
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

    desc 'Imprime o agregado do eval (só atendimentos reais): spx:eval:report[account_id]'
    task :report, %i[account_id] => :environment do |_t, args|
      account = Account.find(args[:account_id])
      all = Captain::ConversationEval.for_account(account.id)
      evals = all.em_escopo
      fora = all.where.not(representatividade: 'atendimento_real')
      puts "== Eval da conta #{account.id} (#{account.name}) =="
      puts "Total avaliadas: #{all.count} (em escopo: #{evals.count} · fora de escopo: #{fora.count})"
      puts "Fora de escopo: #{fora.group(:representatividade).count}" if fora.exists?
      next if evals.count.zero?

      puts '-- métricas (só atendimentos reais) --'
      puts "Interesse:      #{evals.where.not(interesse: nil).group(:interesse).count}"
      puts "Intenção:       #{evals.where.not(intencao: nil).group(:intencao).count}"
      puts "Funil:          #{evals.where.not(funil: nil).group(:funil).count}"
      puts "Handoff timing: #{evals.where.not(handoff_timing: nil).group(:handoff_timing).count}"
      nota = evals.where.not(nota: nil)
      puts "Nota média:     #{nota.average(:nota)&.round(2)} (n=#{nota.count})"
      falhas = Hash.new(0)
      evals.recent.limit(1000).pluck(:response_findings).each do |findings|
        Array(findings).each { |f| falhas[f['categoria']] += 1 if f.is_a?(Hash) && f['categoria'].present? }
      end
      puts "Top falhas:     #{falhas.sort_by { |_, v| -v }.first(8).to_h}"
    end

    desc 'Reprocessa evals existentes (re-julga p/ preencher representatividade): spx:eval:reprocess[account_id,limit]'
    task :reprocess, %i[account_id limit] => :environment do |_t, args|
      account = Account.find(args[:account_id])
      limit = (args[:limit] || 500).to_i
      evals = Captain::ConversationEval.for_account(account.id).recent.limit(limit).to_a
      puts "Reprocessando #{evals.size} eval(s) da conta #{account.id}..."
      ok = 0
      falhas = 0
      evals.each_with_index do |ev, index|
        conversation = Conversation.find_by(id: ev.conversation_id)
        next if conversation.nil?

        result = Captain::ConversationEvalService.new(
          account: account,
          conversation_display_id: conversation.display_id
        ).perform
        next if result[:error].present? || result[:verdict].blank?

        ev.update!(avaliado_em: Time.now.utc, **result[:verdict])
        ok += 1
        print "\r#{index + 1}/#{evals.size}"
      rescue StandardError => e
        falhas += 1
        warn "\nfalha na conv #{ev.conversation_id}: #{e.class} #{e.message.to_s[0, 80]}"
      end
      puts "\nReprocessadas OK: #{ok}, falhas: #{falhas}. Rode spx:eval:report[#{account.id}] pra ver o antes/depois."
    end
  end
end
