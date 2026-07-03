# frozen_string_literal: true

# Kanban v2 (Fase 8) — seeds the built-in funnel templates idempotently (upsert
# by slug). Called lazily when the template catalog is listed.
class Kanban::EnsureFunnelTemplatesService
  TEMPLATES = [
    {
      slug: 'support', name: 'Suporte', description: 'Triagem e resolução de chamados', position: 0,
      definition: {
        'color' => '#3b82f6',
        'stages' => [
          { 'name' => 'Novo', 'color' => '#94a3b8', 'automation_type' => 'open' },
          { 'name' => 'Em atendimento', 'color' => '#3b82f6', 'automation_type' => nil },
          { 'name' => 'Aguardando cliente', 'color' => '#f59e0b', 'automation_type' => nil },
          { 'name' => 'Resolvido', 'color' => '#10b981', 'automation_type' => 'resolved' }
        ],
        'custom_fields' => [
          { 'key' => 'motivo', 'label' => 'Motivo', 'field_type' => 'dropdown', 'show_on_card' => true,
            'options' => { 'choices' => %w[Dúvida Problema Reclamação Elogio] } }
        ]
      }
    },
    {
      slug: 'sales', name: 'Vendas', description: 'Funil comercial do lead ao fechamento', position: 1,
      definition: {
        'color' => '#22c55e',
        'stages' => [
          { 'name' => 'Lead', 'color' => '#94a3b8', 'automation_type' => 'open' },
          { 'name' => 'Qualificação', 'color' => '#6366f1', 'automation_type' => nil },
          { 'name' => 'Proposta', 'color' => '#f59e0b', 'automation_type' => nil },
          { 'name' => 'Ganho', 'color' => '#10b981', 'automation_type' => 'resolved' }
        ],
        'custom_fields' => [
          { 'key' => 'valor', 'label' => 'Valor da venda', 'field_type' => 'number', 'show_on_card' => true, 'options' => {} }
        ]
      }
    },
    {
      slug: 'collections', name: 'Cobrança', description: 'Recuperação de pagamentos', position: 2,
      definition: {
        'color' => '#ef4444',
        'stages' => [
          { 'name' => 'Em aberto', 'color' => '#94a3b8', 'automation_type' => 'open' },
          { 'name' => 'Notificado', 'color' => '#f59e0b', 'automation_type' => nil },
          { 'name' => 'Negociando', 'color' => '#6366f1', 'automation_type' => nil },
          { 'name' => 'Pago', 'color' => '#10b981', 'automation_type' => 'resolved' }
        ],
        'custom_fields' => []
      }
    },
    {
      slug: 'post_sale', name: 'Pós-venda', description: 'Acompanhamento após a compra', position: 3,
      definition: {
        'color' => '#a855f7',
        'stages' => [
          { 'name' => 'Onboarding', 'color' => '#94a3b8', 'automation_type' => 'open' },
          { 'name' => 'Acompanhamento', 'color' => '#6366f1', 'automation_type' => nil },
          { 'name' => 'Concluído', 'color' => '#10b981', 'automation_type' => 'resolved' }
        ],
        'custom_fields' => []
      }
    }
  ].freeze

  def perform
    TEMPLATES.each do |template|
      record = FunnelTemplate.find_or_initialize_by(slug: template[:slug])
      record.assign_attributes(
        name: template[:name],
        description: template[:description],
        position: template[:position],
        definition: template[:definition]
      )
      record.save!
    end
    FunnelTemplate.ordered
  end
end
