# frozen_string_literal: true

require 'agents'

Rails.application.config.after_initialize do
  # Sem este patch, o runner do gem `ai-agents` cria `RubyLLM::Chat.new(model:)` sem contexto e cai
  # SEMPRE na chave global da instalação: a chave por conta (tela Conexões) fica decorativa e uma
  # conta que estoura a cota derruba a IA de todas as outras da mesma VM. O patch só injeta contexto
  # quando há um `with_account` ativo, então conta sem chave própria segue na global, como hoje.
  Llm::AccountScopedContext.install_ruby_llm_patch!
  # Ferramenta fora da lista do agente vira resposta ao modelo em vez de derrubar o turno.
  Llm::MissingToolGuard.install!

  api_key = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
  anthropic_key = InstallationConfig.find_by(name: 'CAPTAIN_ANTHROPIC_API_KEY')&.value
  model = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence || LlmConstants::DEFAULT_MODEL
  api_endpoint = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value || LlmConstants::OPENAI_API_ENDPOINT

  if api_key.present? || anthropic_key.present?
    Agents.configure do |config|
      if api_key.present?
        config.openai_api_key = api_key
        if api_endpoint.present?
          api_base = "#{api_endpoint.chomp('/')}/v1"
          config.openai_api_base = api_base
        end
      end
      config.anthropic_api_key = anthropic_key if anthropic_key.present?
      config.default_model = model
      config.debug = false
    end
  end
rescue StandardError => e
  Rails.logger.error "Failed to configure AI Agents SDK: #{e.message}"
end
