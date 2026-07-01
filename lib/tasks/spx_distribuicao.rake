# Config-first (F1, §10.5): cria/mostra política de distribuição por time via console.
# A UI "Política de Distribuição" por time é F3.
#
#   bundle exec rails "spx:distribuicao:policy[6,27,rodizio,128:20,126:20,131:20,127:20]"
#     account=6 team=27(locação) modo=rodizio pool="user_id:cap" (cap opcional; 0/omisso = sem teto)
#   bundle exec rails "spx:distribuicao:show[6,27]"
namespace :spx do
  namespace :distribuicao do
    desc 'Cria/atualiza a política de distribuição de um time. pool = user_id:cap separado por vírgula'
    task :policy, %i[account_id team_id modo pool] => :environment do |_t, args|
      account_id = args[:account_id].to_i
      team_id = args[:team_id].to_i
      modo = (args[:modo].presence || 'rodizio')
      # pool = tokens "user_id:cap" separados por vírgula: o 1º cai em args[:pool],
      # os demais em args.extras. Junta os dois.
      pool_tokens = [args[:pool], *args.extras].compact_blank
      pool = pool_tokens.map do |tok|
        uid, cap = tok.to_s.split(':')
        { 'user_id' => uid.to_i, 'ativo' => true, 'cap' => cap.to_i }
      end

      policy = Spx::Distribuicao::Policy.find_or_initialize_by(account_id: account_id, team_id: team_id)
      policy.assign_attributes(modo: modo, ativo: true, pool: pool)
      policy.save!
      team = Team.find_by(id: team_id)
      puts "OK policy ##{policy.id} conta=#{account_id} time=#{team_id}(#{team&.name}) modo=#{modo}"
      puts "  pool=#{pool.inspect}"
      puts "  membros do time=#{team&.members&.pluck(:id).inspect}"
    end

    desc 'Mostra a política + estado do rodízio de um time'
    task :show, %i[account_id team_id] => :environment do |_t, args|
      pol = Spx::Distribuicao::Policy.for_team(args[:account_id].to_i, args[:team_id].to_i)
      if pol.nil?
        puts "sem política ativa (conta=#{args[:account_id]} time=#{args[:team_id]}) → Motor no-op"
        next
      end
      st = Spx::Distribuicao::State.find_by(team_id: pol.team_id)
      puts "policy ##{pol.id} modo=#{pol.modo} ativo=#{pol.ativo} continuidade=#{pol.continuidade_ativa}/#{pol.continuidade_dias}d"
      puts "  pool=#{pol.pool.inspect}"
      puts "  último escolhido (rodízio)=#{st&.last_user_id.inspect}"
      puts '  últimos logs:'
      Spx::Distribuicao::Log.where(conversation_id: Conversation.where(team_id: pol.team_id).select(:id))
                            .order(created_at: :desc).limit(5)
                            .each { |l| puts "    conv=#{l.conversation_id} → user=#{l.chosen_user_id.inspect} (#{l.motivo})" }
    end
  end
end
