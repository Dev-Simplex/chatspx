# frozen_string_literal: true

# Instala o prompt caching da Anthropic (ver Spx::AnthropicPromptCache).
#
# Faz prepend do ProviderPatch no provider Anthropic do ruby_llm pra marcar as
# tools com cache_control depois do payload ser montado. Fail-closed: se o modulo
# do provider nao for encontrado (drift de versao do ruby_llm), nao instala nada
# e loga um aviso — nenhuma chamada e afetada.
#
# CONFIRMAR na VM (com o ruby_llm instalado), caso o log diga "nao encontrado":
#   path=$(bundle show ruby_llm); grep -rn "def render_payload" "$path"
# e adicionar o modulo correto em CANDIDATES.
Rails.application.config.after_initialize do
  candidates = %w[
    RubyLLM::Providers::Anthropic
    RubyLLM::Protocols::Anthropic
    RubyLLM::Providers::Anthropic::Chat
    RubyLLM::Protocols::Anthropic::Chat
  ]

  target = candidates.filter_map { |name| name.safe_constantize }.find do |const|
    const.instance_methods.include?(:render_payload) ||
      const.private_instance_methods.include?(:render_payload)
  end

  if target
    target.prepend(Spx::AnthropicPromptCache::ProviderPatch)
    Rails.logger.info("[prompt-cache] instalado em #{target} (cache de tools ON)")
  else
    Rails.logger.warn('[prompt-cache] provider Anthropic (render_payload) nao encontrado no ruby_llm; caching NAO instalado')
  end
rescue StandardError => e
  Rails.logger.error("[prompt-cache] falha ao instalar: #{e.class}: #{e.message}")
end
