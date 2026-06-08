class SeedDefaultKanbanTemplates < ActiveRecord::Migration[7.0]
  def up
    return if connection.exec_query("SELECT 1 FROM kanban_templates WHERE slug='vendas-whatsapp' LIMIT 1").any?

    stages = [
      { 'name' => 'Lead novo',        'color' => '#94a3b8', 'automation_type' => 'open',                          'rot_after_days' => 1, 'position' => 0 },
      { 'name' => 'Em conversa',      'color' => '#3b82f6',                                                       'rot_after_days' => 2, 'position' => 1 },
      { 'name' => 'Ja conversamos',   'color' => '#8b5cf6',                                                       'rot_after_days' => 3, 'probability' => 30,  'position' => 2 },
      { 'name' => 'Proposta mandada', 'color' => '#f59e0b',                                                       'rot_after_days' => 4, 'probability' => 60,  'position' => 3 },
      { 'name' => 'Ta pra fechar',    'color' => '#ef4444',                                                       'rot_after_days' => 5, 'probability' => 80,  'position' => 4 },
      { 'name' => 'Fechou',           'color' => '#16a34a', 'won_loss_type' => 'won',  'automation_type' => 'resolved',                  'probability' => 100, 'position' => 5 },
      { 'name' => 'Nao rolou',        'color' => '#64748b', 'won_loss_type' => 'loss',                                                  'probability' => 0,   'position' => 6 }
    ]

    stages_json = stages.to_json
    description = 'Pipeline de vendas pra atendimento via WhatsApp.'

    connection.exec_insert(<<~SQL, 'SeedDefaultKanbanTemplates', [stages_json, description])
      INSERT INTO kanban_templates
        (slug, name, description, vertical, icon, color, locale, version,
         stages_config, sample_cards, automations_config, is_official,
         created_at, updated_at)
      VALUES
        ('vendas-whatsapp', 'Vendas WhatsApp', $2, 'sales', 'i-lucide-trending-up',
         '#22c55e', 'pt-BR', 1, $1::jsonb, '[]'::jsonb, '[]'::jsonb,
         true, NOW(), NOW())
    SQL
  end

  def down
    connection.execute("DELETE FROM kanban_templates WHERE slug='vendas-whatsapp'")
  end
end
