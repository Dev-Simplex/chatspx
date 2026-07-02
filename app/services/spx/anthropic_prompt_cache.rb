# frozen_string_literal: true

# Prompt caching para chamadas Anthropic (Claude) feitas via ruby_llm.
#
# Marca o PREFIXO ESTATICO das requests com cache_control, pra cortar o custo de
# INPUT nos turnos seguintes de uma conversa (leitura de cache = 0.1x do input).
#
# Ordem canonica do payload Anthropic: tools -> system -> messages.
# Um breakpoint cacheia tudo ate ele (inclusive):
#   - marcar a ULTIMA tool        => cacheia [tools]        (sempre seguro; tools sao estaveis)
#   - marcar o 1o bloco de system => cacheia [tools+system] (exige system estavel)
#
# Aqui cuidamos apenas das TOOLS. O system e cacheado no Concerns::Agentable via
# RubyLLM::Content::Raw (dois blocos: estavel + volatil), so quando
# SPX_PROMPT_CACHE_SYSTEM=1. O ProviderPatch abaixo e instalado pelo initializer
# config/initializers/anthropic_prompt_cache.rb (prepend no provider do ruby_llm).
module Spx
  module AnthropicPromptCache
    CACHE_CONTROL = { type: 'ephemeral' }.freeze

    module_function

    # payload: Hash montado pelo protocolo Anthropic do ruby_llm (render_payload).
    def apply!(payload)
      mark_last_tool!(payload[:tools] || payload['tools'])
      payload
    end

    def mark_last_tool!(tools)
      return unless tools.is_a?(Array) && tools.any?

      block = tools.last
      block[:cache_control] = CACHE_CONTROL if block.is_a?(Hash)
    end

    # Prepend no provider Anthropic do ruby_llm. Fail-safe: qualquer erro na
    # marcacao devolve o payload original (nunca quebra uma resposta por causa
    # de uma otimizacao de custo).
    module ProviderPatch
      def render_payload(...)
        payload = super
        begin
          Spx::AnthropicPromptCache.apply!(payload) if payload.is_a?(Hash)
        rescue StandardError => e
          Rails.logger.warn("[prompt-cache] pulando cache_control nas tools: #{e.class}: #{e.message}")
        end
        payload
      end
    end
  end
end
