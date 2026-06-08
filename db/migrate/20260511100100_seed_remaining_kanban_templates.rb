class SeedRemainingKanbanTemplates < ActiveRecord::Migration[7.0]
  TEMPLATES = [
    {
      slug: 'suporte',
      name: 'Suporte ao cliente',
      description: 'Atendimento de chamados e tickets via WhatsApp ou email.',
      vertical: 'support',
      icon: 'i-lucide-life-buoy',
      color: '#0ea5e9',
      stages: [
        { 'name' => 'Aberto',              'color' => '#94a3b8', 'automation_type' => 'open', 'rot_after_days' => 1, 'position' => 0 },
        { 'name' => 'Em analise',          'color' => '#3b82f6', 'rot_after_days' => 2, 'position' => 1 },
        { 'name' => 'Aguardando cliente',  'color' => '#f59e0b', 'rot_after_days' => 3, 'position' => 2 },
        { 'name' => 'Resolvido',           'color' => '#16a34a', 'automation_type' => 'resolved', 'won_loss_type' => 'won', 'probability' => 100,
          'position' => 3 },
        { 'name' => 'Nao resolvido',       'color' => '#64748b', 'won_loss_type' => 'loss', 'probability' => 0,
          'position' => 4 }
      ]
    },
    {
      slug: 'onboarding-cliente',
      name: 'Onboarding de cliente',
      description: 'Acompanhe ativacao e adocao desde o cadastro ate o primeiro uso.',
      vertical: 'onboarding',
      icon: 'i-lucide-rocket',
      color: '#8b5cf6',
      stages: [
        { 'name' => 'Novo cliente',  'color' => '#94a3b8', 'automation_type' => 'open', 'rot_after_days' => 1, 'position' => 0 },
        { 'name' => 'Setup inicial', 'color' => '#3b82f6', 'rot_after_days' => 3, 'position' => 1 },
        { 'name' => 'Treinamento',   'color' => '#8b5cf6', 'rot_after_days' => 5, 'probability' => 60, 'position' => 2 },
        { 'name' => 'Ativo',         'color' => '#16a34a', 'automation_type' => 'resolved', 'won_loss_type' => 'won', 'probability' => 100,
          'position' => 3 },
        { 'name' => 'Cancelado',     'color' => '#64748b', 'won_loss_type' => 'loss', 'probability' => 0,
          'position' => 4 }
      ]
    },
    {
      slug: 'imobiliaria',
      name: 'Imobiliaria',
      description: 'Pipeline de captacao, visita e fechamento de imoveis.',
      vertical: 'real_estate',
      icon: 'i-lucide-home',
      color: '#f59e0b',
      stages: [
        { 'name' => 'Lead',             'color' => '#94a3b8', 'automation_type' => 'open', 'rot_after_days' => 1, 'position' => 0 },
        { 'name' => 'Qualificado',      'color' => '#3b82f6', 'rot_after_days' => 2, 'probability' => 20, 'position' => 1 },
        { 'name' => 'Visita agendada',  'color' => '#8b5cf6', 'rot_after_days' => 4, 'probability' => 40, 'position' => 2 },
        { 'name' => 'Proposta',         'color' => '#f59e0b', 'rot_after_days' => 5, 'probability' => 60, 'position' => 3 },
        { 'name' => 'Negociacao',       'color' => '#ef4444', 'rot_after_days' => 7, 'probability' => 80, 'position' => 4 },
        { 'name' => 'Fechou',           'color' => '#16a34a', 'automation_type' => 'resolved', 'won_loss_type' => 'won', 'probability' => 100,
          'position' => 5 },
        { 'name' => 'Nao fechou',       'color' => '#64748b', 'won_loss_type' => 'loss', 'probability' => 0,
          'position' => 6 }
      ]
    },
    {
      slug: 'ecommerce',
      name: 'E-commerce',
      description: 'Recupere carrinhos, confirme pedidos e acompanhe entregas.',
      vertical: 'ecommerce',
      icon: 'i-lucide-shopping-cart',
      color: '#22c55e',
      stages: [
        { 'name' => 'Carrinho abandonado', 'color' => '#94a3b8', 'automation_type' => 'open', 'rot_after_days' => 1, 'position' => 0 },
        { 'name' => 'Em conversa',         'color' => '#3b82f6', 'rot_after_days' => 1, 'probability' => 30, 'position' => 1 },
        { 'name' => 'Pedido confirmado',   'color' => '#8b5cf6', 'rot_after_days' => 2, 'probability' => 70, 'position' => 2 },
        { 'name' => 'Enviado',             'color' => '#f59e0b', 'rot_after_days' => 5, 'probability' => 90, 'position' => 3 },
        { 'name' => 'Entregue',            'color' => '#16a34a', 'automation_type' => 'resolved', 'won_loss_type' => 'won', 'probability' => 100,
          'position' => 4 },
        { 'name' => 'Cancelado',           'color' => '#64748b', 'won_loss_type' => 'loss', 'probability' => 0,
          'position' => 5 }
      ]
    },
    {
      slug: 'clinica',
      name: 'Clinica',
      description: 'Agende consultas, acompanhe tratamentos e fidelize pacientes.',
      vertical: 'clinic',
      icon: 'i-lucide-stethoscope',
      color: '#ec4899',
      stages: [
        { 'name' => 'Lead',              'color' => '#94a3b8', 'automation_type' => 'open', 'rot_after_days' => 1, 'position' => 0 },
        { 'name' => 'Consulta agendada', 'color' => '#3b82f6', 'rot_after_days' => 2, 'probability' => 40, 'position' => 1 },
        { 'name' => 'Em atendimento',    'color' => '#8b5cf6', 'rot_after_days' => 3, 'probability' => 60, 'position' => 2 },
        { 'name' => 'Tratamento ativo',  'color' => '#f59e0b', 'rot_after_days' => 14, 'probability' => 80, 'position' => 3 },
        { 'name' => 'Fidelizado',        'color' => '#16a34a', 'automation_type' => 'resolved', 'won_loss_type' => 'won', 'probability' => 100,
          'position' => 4 },
        { 'name' => 'Desistiu',          'color' => '#64748b', 'won_loss_type' => 'loss', 'probability' => 0,
          'position' => 5 }
      ]
    }
  ].freeze

  def up # rubocop:disable Metrics/AbcSize
    TEMPLATES.each do |tpl|
      next if connection.exec_query("SELECT 1 FROM kanban_templates WHERE slug=#{connection.quote(tpl[:slug])} LIMIT 1").any?

      connection.exec_insert(<<~SQL.squish, 'SeedRemainingKanbanTemplates', [tpl[:stages].to_json, tpl[:description]])
        INSERT INTO kanban_templates
          (slug, name, description, vertical, icon, color, locale, version,
           stages_config, sample_cards, automations_config, is_official,
           created_at, updated_at)
        VALUES
          (#{connection.quote(tpl[:slug])}, #{connection.quote(tpl[:name])}, $2,
           #{connection.quote(tpl[:vertical])}, #{connection.quote(tpl[:icon])},
           #{connection.quote(tpl[:color])}, 'pt-BR', 1,
           $1::jsonb, '[]'::jsonb, '[]'::jsonb,
           true, NOW(), NOW())
      SQL
    end
  end

  def down
    slugs = TEMPLATES.map { |t| connection.quote(t[:slug]) }.join(', ')
    connection.execute("DELETE FROM kanban_templates WHERE slug IN (#{slugs})")
  end
end
