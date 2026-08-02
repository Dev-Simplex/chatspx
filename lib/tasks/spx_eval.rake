# Operação do sistema de eval (LLM-as-a-Judge) — config-first, por conta.
#   spx:eval:enable[account_id]           liga o gate (custom_attributes['eval_enabled'])
#   spx:eval:disable[account_id]          desliga o gate
#   spx:eval:run[account_id,limit]        avalia agora as N conversas mais recentes (backfill)
#   spx:eval:report[account_id]           imprime o agregado atual (só atendimentos reais)
#   spx:eval:reprocess[account_id,limit]  re-julga evals existentes (preenche representatividade)
#   spx:eval:unit[account_id,unit]        define a unidade: episode (Eval 2.0) | conversation
#   spx:eval:segment[account_id,limit]    segmenta as N conversas mais recentes em episódios (backfill F1)
#   spx:eval:run_episodes[account_id,limit] julga agora N episódios fechados sem eval
#   spx:eval:outcomes[account_id,limit]   desfecho + traços de conduta dos episódios fechados (F3, sem LLM)
#                                         e imprime o cruzamento conduta × desfecho por campanha
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

    desc 'Define a unidade de avaliação: spx:eval:unit[account_id,unit] (episode | conversation)'
    task :unit, %i[account_id unit] => :environment do |_t, args|
      account = Account.find(args[:account_id])
      unit = args[:unit].to_s
      abort "unit inválida: #{unit} (use episode | conversation)" unless %w[episode conversation].include?(unit)

      attrs = account.custom_attributes || {}
      attrs['eval_unit'] = unit
      account.update!(custom_attributes: attrs)
      puts "eval_unit=#{unit} na conta #{account.id} (#{account.name})"
    end

    desc 'Segmenta conversas em episódios (backfill F1): spx:eval:segment[account_id,limit]'
    task :segment, %i[account_id limit] => :environment do |_t, args|
      account = Account.find(args[:account_id])
      limit = (args[:limit] || 500).to_i
      captain_inbox_ids = CaptainInbox.where(inbox_id: account.inboxes.select(:id)).distinct.pluck(:inbox_id)
      conversations = account.conversations
                             .where(inbox_id: captain_inbox_ids)
                             .order(last_activity_at: :desc)
                             .limit(limit)
                             .to_a
      puts "Segmentando #{conversations.size} conversa(s) da conta #{account.id}..."
      falhas = 0
      conversations.each_with_index do |conversation, index|
        Captain::EpisodeSegmenterService.new(conversation: conversation).perform
        print "\r#{index + 1}/#{conversations.size}"
      rescue StandardError => e
        falhas += 1
        warn "\nfalha na conv #{conversation.display_id}: #{e.class} #{e.message.to_s[0, 80]}"
      end
      episodes = Captain::ConversationEpisode.for_account(account.id)
      puts "\nConcluído (falhas: #{falhas}). Episódios: #{episodes.count} " \
           "(fechados: #{episodes.closed.count} · abertos: #{episodes.open_ones.count}) " \
           "em #{episodes.distinct.count(:conversation_id)} conversa(s). " \
           "Fechamento: #{episodes.closed.group(:boundary_reason).count}"
    end

    desc 'Julga agora N episódios fechados sem eval: spx:eval:run_episodes[account_id,limit]'
    task :run_episodes, %i[account_id limit] => :environment do |_t, args|
      account = Account.find(args[:account_id])
      unless Captain::ConversationEval.enabled_for?(account)
        abort "Conta #{account.id} está com eval_enabled=false. Rode spx:eval:enable[#{account.id}] antes."
      end

      limit = (args[:limit] || 100).to_i
      judged = Captain::ConversationEval.for_account(account.id).por_episodio.select(:episode_id)
      episodes = Captain::ConversationEpisode.closed
                                             .for_account(account.id)
                                             .where.not(id: judged)
                                             .order(ended_at: :desc)
                                             .limit(limit)
                                             .to_a
      puts "Julgando #{episodes.size} episódio(s) fechado(s) da conta #{account.id}..."
      falhas = 0
      episodes.each_with_index do |episode, index|
        Captain::EpisodeEvalJob.perform_now(episode)
        print "\r#{index + 1}/#{episodes.size}"
      rescue StandardError => e
        falhas += 1
        warn "\nfalha no episódio #{episode.id} (conv #{episode.conversation_id}): #{e.class} #{e.message.to_s[0, 80]}"
      end
      puts "\nConcluído (falhas: #{falhas}). Evals por episódio: " \
           "#{Captain::ConversationEval.for_account(account.id).por_episodio.count}"
    end

    desc 'Imprime o agregado do eval (só atendimentos reais): spx:eval:report[account_id]'
    task :report, %i[account_id] => :environment do |_t, args|
      account = Account.find(args[:account_id])
      base = Captain::ConversationEval.for_account(account.id)
      # Unidade episódio: quando existem evals por episódio, o agregado usa SÓ eles
      # (misturar com os antigos por-conversa duplicaria as mesmas mensagens).
      all = base.por_episodio.exists? ? base.por_episodio : base
      if base.por_episodio.exists?
        puts "Unidade: EPISÓDIO — #{all.count} episódios de #{all.distinct.count(:conversation_id)} conversa(s) " \
             "(evals legados por conversa fora do agregado: #{base.where(episode_id: nil).count})"
      end
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

    desc 'Desfecho + traços de conduta dos episódios fechados (F3, custo zero): spx:eval:outcomes[account_id,limit]'
    task :outcomes, %i[account_id limit] => :environment do |_t, args|
      account = Account.find(args[:account_id])
      unless Captain::ConversationEval.enabled_for?(account)
        abort "Conta #{account.id} está com eval_enabled=false. Rode spx:eval:enable[#{account.id}] antes."
      end

      limit = (args[:limit] || 500).to_i
      episodes = Captain::ConversationEpisode.closed
                                             .for_account(account.id)
                                             .order(ended_at: :desc)
                                             .limit(limit)
                                             .joins(:conversation)
                                             .to_a

      puts "Lendo desfecho + traços de #{episodes.size} episódio(s) fechado(s) da conta #{account.id} (sem LLM)..."
      gravados = 0
      falhas = 0
      episodes.each_with_index do |episode, index|
        gravados += Captain::EpisodeOutcomeService.new(episode: episode).perform.size
        Captain::EpisodeTraitsService.new(episode: episode).perform
        print "\r#{index + 1}/#{episodes.size}"
      rescue StandardError => e
        falhas += 1
        warn "\nfalha no episódio #{episode.id} (conv #{episode.conversation_id}): #{e.class} #{e.message.to_s[0, 80]}"
      end

      escopo = Captain::EpisodeOutcome.for_account(account.id)
      puts "\nDegraus gravados nesta passada: #{gravados} (falhas: #{falhas}). Total na conta: #{escopo.count}"
      puts "\nEscada (SPX — o CRM externo NÃO entra):"
      Captain::EpisodeOutcome::DEGRAUS.each do |degrau|
        total = escopo.do_spx.where(degrau: degrau).count
        next if total.zero?

        autoria = escopo.do_spx.where(degrau: degrau).group(:causado_por).count
                        .sort_by { |_, v| -v }.map { |k, v| "#{k} #{v}" }.join(' · ')
        marca = Captain::EpisodeOutcome::DEGRAUS_CONVERSAO.include?(degrau) ? '*' : ' '
        puts format('  %<marca>s %<degrau>-12s %<total>5d   (%<autoria>s)',
                    marca: marca, degrau: degrau, total: total, autoria: autoria)
      end
      puts '  (* = degrau que compõe a conversão)'

      externos = escopo.externos.count
      puts "\nCamada externa (CRM Vista), fora da conversão: #{externos}" if externos.positive?

      campanhas = escopo.do_spx.where(degrau: Captain::EpisodeOutcome::DEGRAUS_CONVERSAO)
                        .where.not(campanha: nil).group(:campanha).count
      if campanhas.present?
        puts "\nConversão por campanha:"
        campanhas.sort_by { |_, v| -v }.first(10).each { |nome, total| puts format('    %<n>-45s %<t>5d', n: nome.to_s[0, 45], t: total) }
      end

      # ── conduta × desfecho: o payoff do F3 ──────────────────────────────────
      # Unidade = EPISÓDIO, não a linha de desfecho. Assim o episódio que não atingiu
      # degrau nenhum (HSM enviado, lead nunca respondeu) continua no denominador —
      # que é justamente onde mora a resposta sobre o opener.
      convertidos = Captain::EpisodeOutcome.for_account(account.id).do_spx
                                           .where(degrau: Captain::EpisodeOutcome::DEGRAUS_CONVERSAO)
                                           .select(:episode_id)
      com_traco = Captain::ConversationEpisode.for_account(account.id).closed.where.not(turnos_ia: nil)

      resumo = lambda do |rotulo, escopo|
        total = escopo.count
        next if total.zero?

        midia = escopo.where(enviou_midia: true).count
        puts format('    %<r>-15s %<t>5d eps · %<c>4d chars/resposta · %<u>4.1f turnos IA · %<f>4.1f tools · %<m>3d%% mídia',
                    r: rotulo, t: total, c: escopo.average(:chars_resposta_media).to_i,
                    u: escopo.average(:turnos_ia).to_f, f: escopo.average(:ferramentas_usadas).to_f,
                    m: (100.0 * midia / total).round)
      end

      if com_traco.exists?
        puts "\nConduta × desfecho — correlação, NÃO causalidade:"
        resumo.call('converteu', com_traco.where(id: convertidos))
        resumo.call('não converteu', com_traco.where.not(id: convertidos))

        com_traco.where.not(campanha: nil).group(:campanha).count.sort_by { |_, v| -v }.first(3).each do |campanha, total|
          puts "\n  campanha: #{campanha.to_s[0, 60]} (#{total} eps)"
          escopo = com_traco.where(campanha: campanha)
          resumo.call('converteu', escopo.where(id: convertidos))
          resumo.call('não converteu', escopo.where.not(id: convertidos))
        end
      else
        puts "\n(sem traço calculado ainda — confira se a migration dos traços subiu)"
      end
    end
  end
end
