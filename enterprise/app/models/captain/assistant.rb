# == Schema Information
#
# Table name: captain_assistants
#
#  id                  :bigint           not null, primary key
#  config              :jsonb            not null
#  description         :text
#  guardrails          :jsonb
#  name                :string           not null
#  response_guidelines :jsonb
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#
# Indexes
#
#  index_captain_assistants_on_account_id  (account_id)
#
class Captain::Assistant < ApplicationRecord
  DESCRIPTION_LENGTH_LIMIT = 500

  include Avatarable
  include Concerns::CaptainToolsHelpers
  include Concerns::Agentable

  self.table_name = 'captain_assistants'

  belongs_to :account
  has_one :agent_bot, foreign_key: :captain_assistant_id, dependent: :destroy, inverse_of: :captain_assistant
  has_many :documents, class_name: 'Captain::Document', dependent: :destroy_async
  has_many :responses, class_name: 'Captain::AssistantResponse', dependent: :destroy_async
  has_many :faq_suggestions, class_name: 'Captain::FaqSuggestion', dependent: :destroy_async
  has_many :captain_inboxes,
           class_name: 'CaptainInbox',
           foreign_key: :captain_assistant_id,
           dependent: :destroy_async
  has_many :inboxes,
           through: :captain_inboxes
  has_many :messages, as: :sender, dependent: :nullify
  has_many :copilot_threads, dependent: :destroy_async
  has_many :scenarios, class_name: 'Captain::Scenario', dependent: :destroy_async
  has_many :assistant_logs, class_name: 'Captain::AssistantLog', foreign_key: :captain_assistant_id, dependent: :destroy
  has_many :document_chunks, class_name: 'Captain::DocumentChunk', dependent: :destroy_async
  has_many :agent_sessions, class_name: 'Captain::AgentSession', dependent: :destroy_async

  store_accessor :config, :temperature, :feature_faq, :feature_memory, :feature_contact_attributes, :product_name
  store_accessor :behavior, :debounce_seconds, :business_hours_config, :humanizer_config, :media_pipeline_config,
                 :router_config, :copilot_trigger_config, :dedup_config

  validates :name, presence: true
  validates :description, presence: true, length: { maximum: DESCRIPTION_LENGTH_LIMIT }
  validates :account_id, presence: true

  scope :ordered, -> { order(created_at: :desc) }

  scope :for_account, ->(account_id) { where(account_id: account_id) }

  after_commit :sync_mirror_agent_bot, on: [:create, :update]
  after_touch :sync_mirror_agent_bot # attach de avatar (ActiveStorage) faz touch, não update

  def mirror_agent_bot
    agent_bot || Captain::AssistantMirrorService.new(self).sync!
  end

  def available_name
    name
  end

  def available_agent_tools
    tools = self.class.built_in_agent_tools.dup

    custom_tools = account.captain_custom_tools.enabled.where(copilot_only: false).map(&:to_tool_metadata)
    tools.concat(custom_tools)

    tools
  end

  def available_tool_ids
    available_agent_tools.pluck(:id)
  end

  # Modo de knowledge/RAG: 'faq' (só FAQ Q&A, padrão/legado), 'chunks' (só chunk-RAG),
  # 'hybrid' (FAQ + chunk-RAG). Default 'faq' preserva o comportamento de contas existentes.
  def knowledge_mode
    config['knowledge_mode'].presence || 'faq'
  end

  def faq_knowledge_enabled?
    %w[faq hybrid].include?(knowledge_mode)
  end

  def chunk_knowledge_enabled?
    %w[chunks hybrid].include?(knowledge_mode)
  end

  # Contextual retrieval (1 chamada LLM por chunk). Ligado por padrão quando chunk-RAG ativo;
  # desligue com config['contextual_chunks'] = false pra economizar custo de ingestão.
  def contextual_chunks_enabled?
    chunk_knowledge_enabled? && config['contextual_chunks'] != false
  end

  def push_event_data
    {
      id: id,
      name: name,
      avatar_url: avatar_url.presence || default_avatar_url,
      description: description,
      created_at: created_at,
      type: 'captain_assistant'
    }
  end

  def webhook_data
    {
      id: id,
      name: name,
      avatar_url: avatar_url.presence || default_avatar_url,
      description: description,
      created_at: created_at,
      type: 'captain_assistant'
    }
  end

  private

  def sync_mirror_agent_bot
    Captain::AssistantMirrorService.new(self).sync!
  rescue StandardError => e
    Rails.logger.error("[Captain] mirror sync falhou assistant=#{id}: #{e.message}")
  end

  def agent_name
    name.parameterize(separator: '_')
  end

  def agent_tools
    tools = [
      self.class.resolve_tool_class('faq_lookup').new(self),
      self.class.resolve_tool_class('handoff').new(self),
      *account.captain_custom_tools.enabled.map { |custom_tool| custom_tool.tool(self) }
    ]

    if chunk_knowledge_enabled? && (knowledge_tool = self.class.resolve_tool_class('search_knowledge'))
      tools.unshift(knowledge_tool.new(self))
    end

    tools.concat(configured_agent_tools)
    tools.uniq(&:name)
  end

  # B3 do modelo IA-como-agente: tools de negocio armadas direto no assistant via
  # config['tools'] (lista de ids validada contra available_agent_tools) — um agente
  # standalone busca imovel/manda foto sem depender de cenario. filter_map descarta
  # ids invalidos (nil na lista de tools derruba a execucao na gem).
  def configured_agent_tools
    ids = Array(config['tools']).map(&:to_s).uniq - %w[faq_lookup handoff search_knowledge]
    return [] if ids.empty?

    available = available_agent_tools
    # select(&:active?) gateia tool que depende de config do assistente (ex.: responder_em_audio
    # exige voice_id) — sem a config, a tool nem entra no toolset do agente.
    ids.filter_map do |tool_id|
      meta = available.find { |t| t[:id] == tool_id }
      instantiate_configured_tool(tool_id, meta) if meta
    end.select(&:active?)
  end

  def instantiate_configured_tool(tool_id, meta)
    if meta[:custom]
      Captain::CustomTool.find_by(slug: tool_id, account_id: account_id, enabled: true)&.tool(self)
    else
      self.class.resolve_tool_class(tool_id)&.new(self)
    end
  end

  def prompt_context
    {
      name: name,
      description: description,
      instructions: config['instructions'].presence,
      product_name: config['product_name'] || 'this product',
      scenarios: scenarios.enabled.map do |scenario|
        {
          title: scenario.title,
          key: scenario.handoff_key,
          description: scenario.description
        }
      end,
      response_guidelines: response_guidelines || [],
      guardrails: guardrails || []
    }
  end

  def default_avatar_url
    "#{ENV.fetch('FRONTEND_URL', nil)}/assets/images/dashboard/captain/logo.svg"
  end
end
