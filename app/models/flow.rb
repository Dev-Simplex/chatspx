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
  # send_interactive — lista/botões WhatsApp, set_attribute). Um nó `type:"action"` só é válido
  # se seu `action_name` existir aqui —
  # espelha `Macro::ACTIONS_ATTRS` (macro.rb:33) e `AutomationRule#actions_attributes`
  # (automation_rule.rb:42), já normalizando as assimetrias (open/pending/remove_assigned_team
  # ficam disponíveis para ambos os modos). Ações enterprise (add_sla, assign_ai_agent e os nós
  # de IA ai_classify/ai_generate da Fase 3.2) somam via `Enterprise::Flow#allowed_action_names`.
  #
  # F1.5 — capacidades já existentes no produto, expostas ao motor: move_funnel_stage
  # (mover a conversa de etapa no Kanban, via FunnelItems::MoveService), call_macro
  # (rodar uma Macro existente sobre a conversa) e send_csat (disparar a pesquisa CSAT
  # via CsatSurveyService). Todas reusam o serviço real — o motor só orquestra.
  #
  # F1.6 — novas ações (community, sem dependência enterprise): add_participant (agente como
  # participante da conversa, via ConversationParticipant), enroll_in_sequence (inscreve a
  # conversa numa Message Sequence, via MessageSequences::EnrollService) e http_request (chamada
  # HTTP externa com guarda SSRF — ver Flows::HttpAction). São community porque nenhuma depende
  # de licença enterprise (Captain/SLA); o par assign_ai_agent(enterprise)/add_label(community)
  # guia a decisão.
  #
  # F3 — extras interativos WhatsApp Cloud (community): send_cta_url (botão de link),
  # send_location_request (pedir localização) e send_whatsapp_flow (formulário nativo/WhatsApp
  # Flows). Os três saem pelo passthrough genérico do provider (send_raw_interactive) via
  # content_attributes['interactive_payload']. send_whatsapp_flow, antes um TODO que sempre pulava,
  # agora ENVIA de verdade (integração concluída em Flows::WhatsappFlowAction) — por isso entrou.
  BASE_ACTION_NAMES = %w[
    send_message add_private_note send_attachment send_webhook_event send_email_to_team
    add_label remove_label assign_agent assign_team remove_assigned_team
    mute_conversation snooze_conversation resolve_conversation open_conversation pending_conversation
    change_status change_priority send_email_transcript
    send_template send_interactive set_attribute
    move_funnel_stage call_macro send_csat
    add_participant enroll_in_sequence http_request
    send_cta_url send_location_request send_whatsapp_flow
  ].freeze

  # `wait_for_reply` (F2): suspende o walk ESPERANDO a resposta do contato e ramifica pela opção
  # escolhida (o value da opção do send_interactive anterior == o id da reply == edge.branch) ou
  # por 'timeout' (quando o prazo vence sem resposta). Diferente do `wait` (tempo puro), que só
  # pausa e segue. Ver Flows::RunnerService#suspend_on_wait_for_reply e plano/F2-contrato-wait-for-reply.md.
  NODE_TYPES = %w[trigger action condition router wait wait_for_reply].freeze

  validates :name, presence: true
  validate :definition_shape
  validate :definition_action_names
  validate :interactive_nodes_are_sendable

  # F1 (R-2) — gatilho `external_webhook`: um endpoint PÚBLICO dispara o flow via POST externo.
  # A segurança inteira repousa sobre um token forte e não-adivinhável que IDENTIFICA o flow (o
  # id sequencial NUNCA é exposto). Ver Webhooks::FlowsController para o modelo de ameaça.
  before_save :ensure_webhook_token

  scope :active, -> { where(active: true) }

  # Localiza o flow pelo token público do webhook. Espelha Funnel.for_form_token (lookup por
  # igualdade no jsonb). Restringe a `external_webhook` — um token não pode disparar um flow de
  # outro tipo. O controller decide o comportamento dos não-elegíveis (inativo/engine-off), mas
  # devolve a MESMA resposta genérica para não vazar existência. Token em branco nunca casa.
  def self.for_webhook_token(token)
    return if token.blank?

    external_webhook.where("trigger_config ->> 'webhook_token' = ?", token.to_s).first
  end

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

  # Token público do webhook (nil se o flow não é external_webhook / ainda não foi salvo).
  # Lido pelo serializer (para o widget exibir a URL) e pelo controller (re-verificação).
  def webhook_token
    trigger_config['webhook_token'] if trigger_config.is_a?(Hash)
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

  # Materializa o token do webhook — BACKEND-AUTORITATIVO. O controller de autoria copia o
  # trigger_config cru do cliente (flows_controller.rb#assign_jsonb_attributes), então IGNORAMOS
  # qualquer `webhook_token` que venha de fora: reusa SEMPRE o token já persistido e só gera um
  # novo (SecureRandom.hex(24) = 192 bits de entropia) na primeira vez que o flow vira webhook.
  # Assim o cliente não define nem rotaciona o token, e a URL é ESTÁVEL entre edições. Ao sair de
  # external_webhook o token é preservado (a mesma URL volta a valer se reativar); não vaza porque
  # for_webhook_token filtra por external_webhook. TODO(F2): endpoint autenticado de rotação.
  def ensure_webhook_token
    return unless external_webhook?

    token = persisted_webhook_token.presence || SecureRandom.hex(24)
    self.trigger_config = trigger_config.to_h.merge('webhook_token' => token)
  end

  # O token como está PERSISTIDO (valor pré-alteração da atribuição atual). Numa criação é nil
  # (gera-se um novo); num update é o token do banco (preserva-se), mesmo que o cliente tente
  # sobrescrevê-lo no payload.
  def persisted_webhook_token
    previous = trigger_config_was
    previous['webhook_token'] if previous.is_a?(Hash)
  end

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

  # `send_interactive` sem corpo é ACEITO por aqui mas RECUSADO pela Meta na entrega
  # ("The parameter interactive.body.text is required" — o body é obrigatório em interactive).
  # A mensagem morre com status failed, o contato não vê nada e o `wait_for_reply` seguinte arma
  # a espera do mesmo jeito: o atendente vê "menu enviado", o cliente vê silêncio e a conversa
  # fica presa. Um nó sem nenhuma opção com título também não tem lista/botão a enviar
  # (sanitize_interactive_items descarta item sem título e o serviço levanta StepSkip).
  # Validar na gravação impede que a configuração quebrada chegue ao ar por qualquer cliente da
  # API — o canvas valida antes, mas ele não é a única porta.
  def interactive_nodes_are_sendable
    return unless definition.is_a?(Hash) && definition['nodes'].is_a?(Array)

    interactive_nodes.each { |node| validate_interactive_node(node) }
  end

  def interactive_nodes
    definition['nodes'].select do |node|
      node.is_a?(Hash) && node['type'] == 'action' && node['action_name'] == 'send_interactive'
    end
  end

  def validate_interactive_node(node)
    config = Array(node['action_params']).first
    config = {} unless config.is_a?(Hash)

    errors.add(:definition, "node #{node['id']}: send_interactive requires a non-blank content") if config['content'].to_s.strip.blank?
    return if interactive_titled_item?(config)

    errors.add(:definition, "node #{node['id']}: send_interactive requires at least one option with a title")
  end

  def interactive_titled_item?(config)
    Array(config['items']).any? { |item| item.is_a?(Hash) && item['title'].to_s.strip.present? }
  end
end

Flow.include_mod_with('Audit::Flow')
Flow.prepend_mod_with('Flow')
