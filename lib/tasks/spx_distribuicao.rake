# Config-first (F1, §10.5): cria/mostra política de distribuição por time via console.
# A UI "Política de Distribuição" por time é F3.
#
#   bundle exec rails "spx:distribuicao:policy[6,27,rodizio,128:20,126:20,131:20,127:20]"
#     account=6 team=27(locação) modo=rodizio pool="user_id:cap:produto|produto:vista_corretor"
#     cap opcional (0/omisso = sem teto) · produtos opcional (omisso = atende TUDO)
#     vista_corretor opcional (sem ele o espelho do Vista não cria card pra essa pessoa)
#   bundle exec rails "spx:distribuicao:show[6,27]"
#   bundle exec rails "spx:distribuicao:produto[6,<slug>,<nome>,empreendimentos:<termo>|<termo>]"
#   bundle exec rails "spx:distribuicao:produtos[6]"
#
# Metrics/BlockLength desligado no arquivo inteiro: o bloco aqui é o DSL do rake, não lógica —
# quebrar em métodos só pra caber no cop deixaria um script de config menos legível. Mesmo
# tratamento que os outros rakes grandes do fork (spx_tozi, captain_chat) já recebem.
# rubocop:disable Metrics/BlockLength
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
        uid, cap, produtos, vista_corretor = tok.to_s.split(':')
        entry = { 'user_id' => uid.to_i, 'ativo' => true, 'cap' => cap.to_i }
        # 4º campo (opcional) = identificador do corretor NO VISTA. Sem ele o espelho não
        # cria card pra essa pessoa — de propósito: o DELETE do Vista é 401, então card no
        # corretor errado não tem desfazer.
        entry['vista_corretor'] = vista_corretor.to_s.strip if vista_corretor.present?
        # 3º campo (opcional) = slugs de produto que a pessoa atende, separados por "|".
        # AUSENTE = atende TUDO — é o default, e é o que preserva as políticas já
        # configuradas decidindo como decidiam antes do filtro de produto existir.
        lista = produtos.to_s.split('|').map(&:strip).compact_blank
        entry['produtos'] = lista.map { |slug| { 'produto' => slug } } if lista.any?
        entry
      end

      policy = Spx::Distribuicao::Policy.find_or_initialize_by(account_id: account_id, team_id: team_id)
      policy.assign_attributes(modo: modo, ativo: true, pool: pool)
      policy.save!
      team = Team.find_by(id: team_id)
      puts "OK policy ##{policy.id} conta=#{account_id} time=#{team_id}(#{team&.name}) modo=#{modo}"
      puts "  pool=#{pool.inspect}"
      puts "  membros do time=#{team&.members&.pluck(:id).inspect}"
    end

    desc 'Ajusta o SLA do repasse de um time. args: account, team, sla_minutos, max_repasses, destino_user_id'
    task :sla, %i[account_id team_id sla_minutos max_repasses destino_user_id] => :environment do |_t, args|
      pol = Spx::Distribuicao::Policy.for_team(args[:account_id].to_i, args[:team_id].to_i)
      if pol.nil?
        puts "sem política ativa (conta=#{args[:account_id]} time=#{args[:team_id]}) — crie com spx:distribuicao:policy antes"
        next
      end
      attrs = {}
      attrs[:sla_assumir_minutos] = args[:sla_minutos].to_i if args[:sla_minutos].present?
      attrs[:max_repasses] = args[:max_repasses].to_i if args[:max_repasses].present?
      attrs[:pool_esgotado_destino_user_id] = args[:destino_user_id].presence&.to_i if args[:destino_user_id]
      pol.update!(attrs)
      destino = pol.pool_esgotado_destino_user_id
      membro = destino && Team.find_by(id: pol.team_id)&.members&.exists?(id: destino)
      puts "OK policy ##{pol.id} sla=#{pol.sla_assumir_minutos}min max_repasses=#{pol.max_repasses} destino=#{destino.inspect}"
      puts '  ⚠️  destino NÃO é membro do time — a escalação seria descartada' if destino && !membro
      puts '  espelho_vista LIGADO: este time não repassa (o card já existe no Vista) — SLA vale só como medida' if pol.espelho_vista?
    end

    desc 'Mostra a política + estado do rodízio de um time'
    task :show, %i[account_id team_id] => :environment do |_t, args|
      pol = Spx::Distribuicao::Policy.for_team(args[:account_id].to_i, args[:team_id].to_i)
      if pol.nil?
        puts "sem política ativa (conta=#{args[:account_id]} time=#{args[:team_id]}) → Motor no-op"
        next
      end
      st = Spx::Distribuicao::State.find_by(team_id: pol.team_id)
      puts "policy ##{pol.id} modo=#{pol.modo} posse=#{pol.modo_posse} ativo=#{pol.ativo} " \
           "continuidade=#{pol.continuidade_ativa}/#{pol.continuidade_dias}d"
      puts "  repassa=#{pol.repassa?} sla=#{pol.sla_assumir_minutos}min max=#{pol.max_repasses} " \
           "destino=#{pol.pool_esgotado_destino_user_id.inspect} espelho_vista=#{pol.espelho_vista}"
      puts "  pool=#{pol.pool.inspect}"
      puts "  último escolhido (rodízio)=#{st&.last_user_id.inspect}"
      abertas = Spx::Distribuicao::Log.abertas
                                      .where(conversation_id: Conversation.where(team_id: pol.team_id).select(:id))
      puts "  designações ABERTAS (IA ainda atendendo)=#{abertas.count}"
      puts '  últimos logs:'
      Spx::Distribuicao::Log.where(conversation_id: Conversation.where(team_id: pol.team_id).select(:id))
                            .order(created_at: :desc).limit(5)
                            .each do |l|
        puts "    conv=#{l.conversation_id} → user=#{l.chosen_user_id.inspect} " \
             "(#{l.motivo}) produto=#{l.produto_slug.inspect} status=#{l.status.inspect}"
      end
    end

    desc 'Define quem fica com a posse após a escolha: assignee (atribui, IA cala) ou designacao (IA continua)'
    task :posse, %i[account_id team_id modo_posse] => :environment do |_t, args|
      policy = Spx::Distribuicao::Policy.for_team(args[:account_id].to_i, args[:team_id].to_i)
      if policy.nil?
        puts "sem política ativa (conta=#{args[:account_id]} time=#{args[:team_id]}) — crie com spx:distribuicao:policy"
        next
      end
      policy.update!(modo_posse: args[:modo_posse].to_s.strip)
      puts "OK policy ##{policy.id} time=#{policy.team_id} modo_posse=#{policy.modo_posse}"
      puts '  designacao => o Motor escolhe mas NÃO atribui; a IA segue atendendo até alguém assumir'
    end

    desc 'Cria/atualiza um produto do catálogo. matchers = chave:termo|termo (chaves: empreendimentos, campanhas, palavras)'
    task :produto, %i[account_id slug nome matchers] => :environment do |_t, args|
      account_id = args[:account_id].to_i
      slug = args[:slug].to_s.strip
      # Igual ao pool: o 1º token cai em args[:matchers], os demais em args.extras.
      tokens = [args[:matchers], *args.extras].compact_blank
      matchers = tokens.each_with_object({}) do |tok, acc|
        chave, termos = tok.to_s.split(':', 2)
        acc[chave.to_s.strip] = termos.to_s.split('|').map(&:strip).compact_blank
      end

      produto = Spx::Distribuicao::Produto.find_or_initialize_by(account_id: account_id, slug: slug)
      produto.assign_attributes(nome: args[:nome].presence || slug, ativo: true, matchers: matchers)
      produto.save!
      puts "OK produto ##{produto.id} conta=#{account_id} slug=#{produto.slug} nome=#{produto.nome}"
      puts "  matchers=#{produto.matchers.inspect}"
    end

    desc 'Lista o catálogo de produtos da conta'
    task :produtos, %i[account_id] => :environment do |_t, args|
      produtos = Spx::Distribuicao::Produto.where(account_id: args[:account_id].to_i).order(:slug)
      if produtos.empty?
        puts 'sem produtos cadastrados → o filtro de produto é no-op (pool inteiro elegível)'
        next
      end
      produtos.each do |p|
        puts "#{p.ativo ? '  ' : 'x '}#{p.slug.to_s.ljust(16)} #{p.nome.to_s.ljust(26)} #{p.matchers.inspect}"
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength
