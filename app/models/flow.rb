# frozen_string_literal: true

# == Schema Information
#
# Table name: flows
#
#  id             :bigint           not null, primary key
#  active         :boolean          default(TRUE), not null
#  definition     :jsonb            not null
#  description    :text
#  goal_conditions :jsonb           not null
#  name           :string           not null
#  reentry_policy :integer          default("once"), not null
#  trigger_config :jsonb            not null
#  trigger_type   :integer          default("manual"), not null
#  version        :integer          default(1), not null
#  visibility     :integer          default("global"), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#  created_by_id  :bigint
#  updated_by_id  :bigint
#
# Indexes
#
#  index_flows_on_account_id                            (account_id)
#  index_flows_on_account_id_and_trigger_type_and_active (account_id,trigger_type,active)
#
# Motor único que funde Macro (trigger `manual`) e AutomationRule (trigger
# `conversation_event`) sobre o `ActionService` compartilhado. `definition` (jsonb com
# nodes+edges) é a fonte da verdade; o canvas apenas renderiza. Na Fase 1 o grafo é
# executado de forma linear e síncrona pelo `Flows::RunnerService` — `wait`/`schedule`
# (estado entre execuções) chegam na Fase 2. Ver plano/automacoes-plano-mestre.md §2.
class Flow < ApplicationRecord
  include Rails.application.routes.url_helpers

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :updated_by, class_name: 'User', optional: true
  has_many_attached :files

  enum trigger_type: { manual: 0, conversation_event: 1, schedule: 2, keyword: 3, external_webhook: 4 }
  enum reentry_policy: { once: 0, re_enroll: 1, re_enroll_after: 2 }
  enum visibility: { personal: 0, global: 1 }

  # Whitelist-união Macro ∪ AutomationRule (community) + os nós novos da F1 (send_template,
  # set_attribute). Um nó `type:"action"` só é válido se seu `action_name` existir aqui —
  # espelha `Macro::ACTIONS_ATTRS` (macro.rb:33) e `AutomationRule#actions_attributes`
  # (automation_rule.rb:42), já normalizando as assimetrias (open/pending/remove_assigned_team
  # ficam disponíveis para ambos os modos). Ações enterprise (add_sla, assign_ai_agent e os nós
  # de IA ai_classify/ai_generate da Fase 3.2) somam via `Enterprise::Flow#allowed_action_names`.
  #
  # F1.5 — capacidades já existentes no produto, expostas ao motor: move_funnel_stage
  # (mover a conversa de etapa no Kanban, via FunnelItems::MoveService), call_macro
  # (rodar uma Macro existente sobre a conversa) e send_csat (disparar a pesquisa CSAT
  # via CsatSurveyService). Todas reusam o serviço real — o motor só orquestra.
  BASE_ACTION_NAMES = %w[
    send_message add_private_note send_attachment send_webhook_event send_email_to_team
    add_label remove_label assign_agent assign_team remove_assigned_team
    mute_conversation snooze_conversation resolve_conversation open_conversation pending_conversation
    change_status change_priority send_email_transcript
    send_template set_attribute
    move_funnel_stage call_macro send_csat
  ].freeze

  NODE_TYPES = %w[trigger action condition router wait].freeze

  validates :name, presence: true
  validate :definition_shape
  validate :definition_action_names

  scope :active, -> { where(active: true) }

  def nodes
    definition_hash.fetch('nodes', [])
  end

  def edges
    definition_hash.fetch('edges', [])
  end

  # Sobrescrito por `Enterprise::Flow` para somar add_sla/assign_ai_agent no build enterprise.
  def allowed_action_names
    BASE_ACTION_NAMES
  end

  def file_base_data
    files.map do |file|
      {
        id: file.id,
        flow_id: id,
        file_type: file.content_type,
        account_id: account_id,
        file_url: url_for(file),
        blob_id: file.blob_id,
        filename: file.filename.to_s
      }
    end
  end

  private

  def definition_hash
    definition.is_a?(Hash) ? definition : {}
  end

  def definition_shape
    return if definition.blank?

    unless valid_definition_container?
      errors.add(:definition, 'must be a hash with nodes[] and edges[] arrays')
      return
    end

    # Cada elemento precisa ser um objeto — senão o walker (que faz node['id'], edge['from'])
    # quebraria fora do rescue best-effort. Ver Flows::RunnerService.
    errors.add(:definition, 'nodes must be objects') unless definition['nodes'].all?(Hash)
    errors.add(:definition, 'edges must be objects') unless definition['edges'].all?(Hash)
  end

  def valid_definition_container?
    definition.is_a?(Hash) && definition['nodes'].is_a?(Array) && definition['edges'].is_a?(Array)
  end

  def definition_action_names
    return unless definition.is_a?(Hash) && definition['nodes'].is_a?(Array)

    unsupported = action_node_names.reject { |name| allowed_action_names.include?(name) }
    errors.add(:definition, "unsupported actions: #{unsupported.join(',')}") if unsupported.any?
  end

  def action_node_names
    definition['nodes']
      .select { |node| node.is_a?(Hash) && node['type'] == 'action' }
      .filter_map { |node| node['action_name'] }
      .uniq
  end
end

Flow.include_mod_with('Audit::Flow')
Flow.prepend_mod_with('Flow')
