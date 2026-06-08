# frozen_string_literal: true

# KANBAN DoD §35 / GAP-FIX: popula sample_cards nos 6 templates default.
# Cards-exemplo serao usados em previews do template picker e podem ser
# materializados como KanbanItems opcionalmente depois (nao na aplicacao base).
class SeedSampleCardsForKanbanTemplates < ActiveRecord::Migration[7.0]
  SAMPLE_CARDS = {
    'vendas-whatsapp' => [
      { 'contact_name' => 'Maria - exemplo', 'last_message' => 'Tenho interesse no plano Premium', 'stage_index' => 0,
        'note' => 'EXEMPLO -- apague depois' },
      { 'contact_name' => 'Joao - exemplo',  'last_message' => 'Quanto fica?',                     'stage_index' => 1, 'note' => 'EXEMPLO' },
      { 'contact_name' => 'Ana - exemplo',   'last_message' => 'Vou pensar e te aviso',           'stage_index' => 2, 'note' => 'EXEMPLO' }
    ],
    'suporte' => [
      { 'contact_name' => 'Cliente A - exemplo', 'last_message' => 'Meu sistema esta offline',     'stage_index' => 0, 'note' => 'EXEMPLO' },
      { 'contact_name' => 'Cliente B - exemplo', 'last_message' => 'Erro 500 no checkout',         'stage_index' => 1, 'note' => 'EXEMPLO' }
    ],
    'onboarding-cliente' => [
      { 'contact_name' => 'Empresa X - exemplo', 'last_message' => 'Acabamos de contratar',        'stage_index' => 0, 'note' => 'EXEMPLO' },
      { 'contact_name' => 'Empresa Y - exemplo', 'last_message' => 'Aguardando treinamento',       'stage_index' => 1, 'note' => 'EXEMPLO' }
    ],
    'imobiliaria' => [
      { 'contact_name' => 'Lead Apto - exemplo', 'last_message' => 'Quero ver apartamentos no Centro', 'stage_index' => 0, 'note' => 'EXEMPLO' },
      { 'contact_name' => 'Carlos - exemplo',    'last_message' => 'Posso fazer proposta?',            'stage_index' => 2, 'note' => 'EXEMPLO' }
    ],
    'ecommerce' => [
      { 'contact_name' => 'Carrinho 1234 - exemplo', 'last_message' => 'Esqueci no checkout',     'stage_index' => 0, 'note' => 'EXEMPLO' },
      { 'contact_name' => 'Pedido 5678 - exemplo',   'last_message' => 'Ja enviou?',              'stage_index' => 2, 'note' => 'EXEMPLO' }
    ],
    'clinica' => [
      { 'contact_name' => 'Paciente A - exemplo', 'last_message' => 'Quero agendar consulta',     'stage_index' => 0, 'note' => 'EXEMPLO' },
      { 'contact_name' => 'Paciente B - exemplo', 'last_message' => 'Em tratamento desde mar/26', 'stage_index' => 3, 'note' => 'EXEMPLO' }
    ]
  }.freeze

  def up
    SAMPLE_CARDS.each do |slug, cards|
      connection.exec_update(
        'UPDATE kanban_templates SET sample_cards = $1::jsonb, updated_at = NOW() WHERE slug = $2',
        'SeedSampleCards',
        [cards.to_json, slug]
      )
    end
  end

  def down
    SAMPLE_CARDS.each_key do |slug|
      connection.exec_update(
        "UPDATE kanban_templates SET sample_cards = '[]'::jsonb WHERE slug = $1",
        'RemoveSampleCards',
        [slug]
      )
    end
  end
end
