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
  end
end
