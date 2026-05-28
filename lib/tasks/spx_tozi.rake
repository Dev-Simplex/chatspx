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

    # Templates HSM da cadência de pré-venda (formato Graph API).
    # MARKETING = ativação/reengajamento (pago). UTILITY = transacional (barato).
    CADENCE_TEMPLATES = [
      {
        name: 'tozi_lead_inicial', category: 'MARKETING', language: 'pt_BR',
        components: [{
          type: 'BODY',
          text: "Oi {{1}}! Sou da equipe Tozi Imóveis 👋\n\nVi que você se interessou pelo anúncio \"{{2}}\".\n\nPosso te ajudar a achar o imóvel certo? Me conta um pouco do que você procura.",
          example: { body_text: [%w[Maria Apartamento]] }
        }]
      },
      {
        name: 'tozi_lead_followup_dia', category: 'MARKETING', language: 'pt_BR',
        components: [{
          type: 'BODY',
          text: "Oi {{1}}, ainda procurando imóvel?\n\nSou da Tozi Imóveis e estou aqui pra ajudar. Se tiver 2 minutinhos, me responde tipo de imóvel e bairro que tenho boas opções.",
          example: { body_text: [['Maria']] }
        }]
      },
      {
        name: 'tozi_lead_reativacao', category: 'MARKETING', language: 'pt_BR',
        components: [{
          type: 'BODY',
          text: "Oi {{1}}!\n\nLembra que você se interessou pela Tozi Imóveis? Apareceram novos imóveis em {{2}} que podem combinar com o que você procurava.\n\nQuer que eu te mande?",
          example: { body_text: [%w[Maria Sinop]] }
        }]
      },
      {
        name: 'tozi_followup_horario_combinado', category: 'UTILITY', language: 'pt_BR',
        components: [{
          type: 'BODY',
          text: "Oi {{1}}, conforme combinamos, voltei aqui pra continuar nossa conversa.\n\nAinda quer falar sobre o imóvel?",
          example: { body_text: [['Maria']] }
        }]
      }
    ].freeze

    desc 'Cria os 4 templates HSM da cadência Tozi via Cloud API (account_id, inbox_id Cloud API)'
    task :create_templates, %i[account_id inbox_id] => :environment do |_t, args|
      account = Account.find(Integer(args[:account_id]))
      inbox = account.inboxes.find(Integer(args[:inbox_id]))
      raise "Inbox #{inbox.id} não é WhatsApp Cloud API (sem WABA)." unless inbox.channel_type == 'Channel::Whatsapp' && inbox.channel.provider_config['business_account_id'].present?

      svc = Whatsapp::TemplateManagementService.new(inbox.channel)
      CADENCE_TEMPLATES.each do |spec|
        result = svc.create(name: spec[:name], language: spec[:language], category: spec[:category], components: spec[:components])
        if result[:success]
          puts "OK   #{spec[:name].ljust(34)} → #{result[:status]} (id=#{result[:template_id]})"
        else
          puts "FAIL #{spec[:name].ljust(34)} → #{result[:error]} | #{result[:response_body]}"
        end
      end
      puts '== Aguardar aprovação Meta (minutos a 24h). Status via sync_templates ou GET message_templates. =='
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
