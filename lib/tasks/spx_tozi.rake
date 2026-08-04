# Tarefas SPX · Tozi — setup do funil de pré-venda (Kanban) para a cadência de follow-up.
#
# Uso:
#   bundle exec rails 'spx:tozi:setup_funnel[<account_id>,<inbox_id>]'
# Exemplos:
#   PAULAO (dev/WAHA):    bundle exec rails 'spx:tozi:setup_funnel[1,1]'
#   Produção (Cloud API): bundle exec rails 'spx:tozi:setup_funnel[6,91]'
#
# Idempotente: roda quantas vezes quiser. Cria o funil "Pré-Venda Tozi" se não
# existir e garante os 7 estágios na ordem/cor/automação corretas (atualiza os
# existentes por automation_type, sem duplicar).
namespace :spx do
  namespace :tozi do
    # 7 estágios da cadência de pré-venda. automation_type é a chave estável
    # usada pela state machine (Spx::Tozi::FunnelAutomationService, Bloco 3).
    PREVENDA_STAGES = [
      { automation_type: 'novo_lead',       name: 'Novo Lead',              color: '#F97316', position: 0 },
      { automation_type: 'aguardando_1a',   name: 'Aguardando 1ª Resposta', color: '#3B82F6', position: 1 },
      { automation_type: 'em_conversa',     name: 'Em Conversa',            color: '#10B981', position: 2 },
      { automation_type: 'em_silencio',     name: 'Em Silêncio',            color: '#F59E0B', position: 3 },
      { automation_type: 'agendado',        name: 'Agendado',               color: '#8B5CF6', position: 4 },
      { automation_type: 'qualificado',     name: 'Qualificado',            color: '#059669', position: 5 },
      { automation_type: 'frio',            name: 'Frio / Perdido',         color: '#94A3B8', position: 6 }
    ].freeze

    FUNNEL_NAME = 'Pré-Venda Tozi'

    desc 'Cria/atualiza o funil de pré-venda Tozi com 7 estágios (account_id, inbox_id)'
    task :setup_funnel, %i[account_id inbox_id] => :environment do |_t, args|
      account_id = Integer(args[:account_id])
      inbox_id = Integer(args[:inbox_id])

      account = Account.find(account_id)
      inbox = account.inboxes.find(inbox_id)

      funnel = account.funnels.find_or_initialize_by(name: FUNNEL_NAME)
      funnel.inbox_ids = [inbox.id]
      funnel.color ||= '#F97316'
      funnel.save!

      PREVENDA_STAGES.each do |spec|
        stage = funnel.funnel_stages.find_or_initialize_by(automation_type: spec[:automation_type])
        stage.name = spec[:name]
        stage.color = spec[:color]
        stage.position = spec[:position]
        stage.save!
      end

      puts "== Funil '#{FUNNEL_NAME}' (id=#{funnel.id}) pronto no Account #{account_id}, Inbox #{inbox_id} =="
      funnel.reload.funnel_stages.ordered.each do |s|
        puts "  [#{s.position}] #{s.name.ljust(24)} automation=#{s.automation_type.ljust(16)} color=#{s.color} (id=#{s.id})"
      end
    end

    # Templates HSM da cadência de pré-venda (formato Graph API), com os NOMES v2
    # aprovados no WABA da Tozi (ver Obsidian/credenciais/tozi.md). MARKETING =
    # ativação/reengajamento (pago); UTILITY = transacional (barato). Tom consultivo
    # "de Sinop" (morar/investir). Variáveis: {{1}}=nome; {{2}}=referência (empreendimento/cidade).
    #
    # ATENÇÃO: para o WABA da Tozi os 4 já estão aprovados — create_templates é
    # idempotente e PULA os existentes. Os corpos abaixo são a fonte reproduzível
    # (ex.: novo cliente). Para paridade exata com o aprovado, conferir via `svc.list`.
    # rubocop:disable Layout/LineLength
    CADENCE_TEMPLATES = [
      {
        name: 'tozi_lead_abertura', category: 'MARKETING', language: 'pt_BR',
        components: [{
          type: 'BODY',
          text: "Oi {{1}}, aqui é da Tozi Imóveis 👋\n\nVi seu interesse em {{2}}. Pra eu te ajudar do jeito certo: é pra morar ou investir? E já tem uma região de Sinop em mente?",
          example: { body_text: [%w[Maria Pacaembu]] }
        }]
      },
      {
        name: 'tozi_lead_followup', category: 'MARKETING', language: 'pt_BR',
        components: [{
          type: 'BODY',
          text: "Oi {{1}}, tudo bem? Fiquei de te ajudar a achar o imóvel certo e não quero te deixar sem retorno.\n\nQuando puder, me diz o que faz mais sentido pra você que eu já adianto umas opções boas. 🏡",
          example: { body_text: [['Maria']] }
        }]
      },
      {
        name: 'tozi_lead_reativacao', category: 'MARKETING', language: 'pt_BR',
        components: [{
          type: 'BODY',
          text: "Oi {{1}}! Apareceram novidades em {{2}} que têm a ver com o que você estava procurando com a gente.\n\nQuer que eu te mostre? Sem compromisso, só pra você não perder uma boa oportunidade.",
          example: { body_text: [%w[Maria Sinop]] }
        }]
      },
      {
        name: 'tozi_followup_horario_combinado', category: 'UTILITY', language: 'pt_BR',
        components: [{
          type: 'BODY',
          text: 'Oi {{1}}, conforme combinamos, voltei no horário que marcamos pra continuar de onde paramos. Pode falar agora?',
          example: { body_text: [['Maria']] }
        }]
      }
    ].freeze
    # rubocop:enable Layout/LineLength

    desc 'Cria os 4 templates HSM da cadência Tozi via Cloud API (account_id, inbox_id Cloud API). Idempotente.'
    task :create_templates, %i[account_id inbox_id] => :environment do |_t, args|
      account = Account.find(Integer(args[:account_id]))
      inbox = account.inboxes.find(Integer(args[:inbox_id]))
      raise "Inbox #{inbox.id} não é WhatsApp Cloud API (sem WABA)." unless inbox.channel_type == 'Channel::Whatsapp' && inbox.channel.provider_config['business_account_id'].present? # rubocop:disable Layout/LineLength

      svc = Whatsapp::TemplateManagementService.new(inbox.channel)
      listing = svc.list
      existing_names = listing[:success] ? Array(listing[:templates]).map { |t| t['name'] } : []
      puts "AVISO: não consegui listar templates existentes (#{listing[:error]}). Vou tentar criar mesmo assim." unless listing[:success]

      CADENCE_TEMPLATES.each do |spec|
        if existing_names.include?(spec[:name])
          puts "SKIP #{spec[:name].ljust(34)} → já existe no WABA (idempotente)"
          next
        end

        result = svc.create(name: spec[:name], language: spec[:language], category: spec[:category], components: spec[:components])
        if result[:success]
          puts "OK   #{spec[:name].ljust(34)} → #{result[:status]} (id=#{result[:template_id]})"
        else
          puts "FAIL #{spec[:name].ljust(34)} → #{result[:error]} | #{result[:response_body]}"
        end
      end
      puts '== Aguardar aprovação Meta (minutos a 24h). Status via sync_templates ou GET message_templates. =='
    end

    # Corretores que recebem os disparos (round-robin). IDs do Account 6 (AWS prod).
    # 128=Marcus 126=Kettlen 127=Lucas 131=Bruno 125=Guilherme(admin, também recebe).
    # Isolamento garantido pela custom role "Corretor" (conversation_participating_manage):
    # cada um só enxerga as conversas atribuídas a ele.
    DISPARO_BROKERS = [128, 126, 127, 131, 125].freeze

    # Templates aprovados do lançamento (rotacionam quando nenhum é fixado no arg).
    DISPARO_TEMPLATES = %w[
      tozi_lancamento_interagir
      tozi_lancamento_qualifica
      tozi_lancamento_curiosidade
    ].freeze

    desc 'Disparo em massa do lançamento: enfileira HSM espalhado em N min, round-robin corretores+templates. ' \
         'Args: [csv_path, limit, dry_run, spread_min, template, campaign_id]. dry_run=true (default) só IMPRIME o plano.'
    task :disparo, %i[csv_path limit dry_run spread_min template campaign_id] => :environment do |_t, args|
      require 'csv'

      csv_path = args[:csv_path].to_s
      raise "CSV não encontrado: #{csv_path.inspect}" unless File.exist?(csv_path)

      limit      = args[:limit].present? ? Integer(args[:limit]) : nil
      dry_run    = args[:dry_run].to_s.strip.downcase != 'false' # default TRUE (seguro)
      spread_min = args[:spread_min].present? ? Float(args[:spread_min]) : 120.0
      fixed_tmpl = args[:template].presence
      campaign_id = args[:campaign_id].presence && Integer(args[:campaign_id])

      raise "Campanha ##{campaign_id} não existe." if campaign_id && Campaign.where(id: campaign_id).none?

      if fixed_tmpl && DISPARO_TEMPLATES.exclude?(fixed_tmpl)
        raise "Template #{fixed_tmpl.inspect} desconhecido. Use um de: #{DISPARO_TEMPLATES.join(', ')}"
      end

      # Lê a audiência (colunas: nome, telefone_e164, canonical).
      leads = CSV.read(csv_path, headers: true).filter_map do |row|
        nome = (row['nome'] || row['name']).to_s.strip
        tel  = (row['telefone_e164'] || row['telefone'] || row['phone']).to_s.strip
        next if tel.blank?

        { nome: nome, telefone: tel }
      end
      leads = leads.first(limit) if limit

      total = leads.size
      raise 'Audiência vazia após leitura/limit.' if total.zero?

      spread_seconds = spread_min * 60
      step = total > 1 ? spread_seconds / (total - 1) : 0
      broker_counts = Hash.new(0)
      tmpl_counts = Hash.new(0)

      leads.each_with_index do |lead, i|
        assignee = DISPARO_BROKERS[i % DISPARO_BROKERS.size]
        template = fixed_tmpl || DISPARO_TEMPLATES[i % DISPARO_TEMPLATES.size]
        delay    = (step * i).round
        broker_counts[assignee] += 1
        tmpl_counts[template] += 1

        next if dry_run

        Spx::Tozi::DisparoLeadJob.set(wait: delay.seconds).perform_later(
          nome: lead[:nome], telefone: lead[:telefone], assignee_id: assignee,
          template: template, campaign_id: campaign_id
        )
      end

      mode = dry_run ? 'DRY-RUN (nada enfileirado)' : 'ENFILEIRADO'
      puts '=' * 64
      puts "== DISPARO LANÇAMENTO TOZI — #{mode} =="
      puts '=' * 64
      puts "audiência:        #{total} leads  (csv: #{File.basename(csv_path)})"
      puts "janela:           #{spread_min.round} min  (1 a cada ~#{step.round(1)}s)"
      puts "template:         #{fixed_tmpl || "rotação (#{DISPARO_TEMPLATES.size})"}"
      puts "campanha:         #{campaign_id ? "##{campaign_id}" : 'NENHUMA'}"
      if campaign_id.nil?
        puts ''
        puts '  ⚠  SEM campaign_id: as conversas nascem desvinculadas de campanha. Isso'
        puts '     (a) deixa este disparo FORA de qualquer corte por campanha,'
        puts '     (b) desarma a guarda que impede a IA de encerrar lead de campanha que'
        puts '         ainda não respondeu (campaign_without_reply?), e'
        puts '     (c) impede o roteamento da resposta pro dono do disparo.'
        puts '     Crie/reuse uma Campaign âncora e passe o id no 6º argumento.'
      end
      puts 'primeiro envio:   imediato (delay 0s)'
      puts "último envio:     ~#{(spread_seconds / 60).round} min após o start"
      puts "\n-- por corretor --"
      broker_counts.sort.each do |uid, n|
        u = User.find_by(id: uid)
        puts "  ##{uid} #{(u&.name || '?').to_s.ljust(20)} #{n} conversas"
      end
      puts "\n-- por template --"
      tmpl_counts.sort.each { |tmpl, n| puts "  #{tmpl.ljust(30)} #{n}" }
      puts "\n-- amostra (5) --"
      leads.first(5).each_with_index do |lead, i|
        assignee = DISPARO_BROKERS[i % DISPARO_BROKERS.size]
        template = fixed_tmpl || DISPARO_TEMPLATES[i % DISPARO_TEMPLATES.size]
        puts "  #{lead[:telefone].ljust(16)} #{lead[:nome][0, 24].ljust(24)} -> ##{assignee} | #{template}"
      end
      puts "\n#{dry_run ? '>>> DRY-RUN: rode de novo com dry_run=false pra ENVIAR.' : '>>> JOBS ENFILEIRADOS. Acompanhar via Sidekiq/logs.'}"
    end

    desc 'Disparo de TESTE: envia 1 HSM real imediato pra um número (valida ponta a ponta). ' \
         'Args: [nome, telefone, template, assignee_id]'
    task :disparo_teste, %i[nome telefone template assignee_id] => :environment do |_t, args|
      nome     = args[:nome].presence || 'Paulo'
      telefone = args[:telefone].to_s.strip
      raise 'Informe o telefone: spx:tozi:disparo_teste[Paulo,+5566996350491,tozi_lancamento_interagir,128]' if telefone.blank?

      template = args[:template].presence || DISPARO_TEMPLATES.first
      raise "Template #{template.inspect} desconhecido." if DISPARO_TEMPLATES.exclude?(template)

      assignee = args[:assignee_id].present? ? Integer(args[:assignee_id]) : DISPARO_BROKERS.first

      Spx::Tozi::DisparoLeadJob.perform_now(
        nome: nome, telefone: telefone, assignee_id: assignee, template: template
      )
      puts "== TESTE enviado: #{telefone} (#{nome}) -> corretor##{assignee} | #{template} =="
      puts '   Confira a chegada no WhatsApp e a conversa atribuída no SPX.'
    end

    desc 'Backfill: coloca leads existentes do Meta Lead Ads no estágio Novo Lead (account_id)'
    task :backfill_funnel, %i[account_id] => :environment do |_t, args|
      account = Account.find(Integer(args[:account_id]))
      funnel = account.funnels.find_by(name: FUNNEL_NAME)
      raise "Funil '#{FUNNEL_NAME}' não existe. Rode setup_funnel primeiro." if funnel.nil?

      stage = funnel.funnel_stages.with_automation('novo_lead').first
      raise "Estágio novo_lead não existe no funil." if stage.nil?

      convs = account.conversations.where("additional_attributes->>'source' = ?", 'meta_lead_ads')
      created = 0
      convs.find_each do |conversation|
        item = FunnelItem.find_or_initialize_by(conversation_id: conversation.id, funnel_id: funnel.id)
        next if item.persisted?

        item.funnel_stage_id = stage.id
        item.save!
        created += 1
      end

      puts "== Backfill concluído: #{created} leads Meta colocados em 'Novo Lead' (funil id=#{funnel.id}) =="
      puts "   Total de conversas meta_lead_ads no account: #{convs.count}"
    end
  end
end
