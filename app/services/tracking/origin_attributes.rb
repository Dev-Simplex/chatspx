# frozen_string_literal: true

# Catálogo canônico das chaves de origem (bloco 1.18, consumido por 1.19 e 1.22).
#
# Uma lista só, num lugar só. Se cada frente inventar a sua, o painel do cliente mostra
# `utm_source` duas vezes com normalizações diferentes — é o conflito nº 5 da §Integração do
# plano de tracking, e o motivo de este arquivo existir antes do parser.
#
# Escopo das chaves:
#   conversa (`last_*`)  — o que trouxe ESTA conversa
#   contato  (`first_*`) — write-once, o que trouxe a pessoa da PRIMEIRA vez
#
# Os click ids ficam de fora do contato de propósito: click id é da sessão, não da pessoa, e a
# regra do plano para ele no contato é "mais recente não vazio, com timestamp" (C9) — que é o
# oposto de write-once. Misturar as duas regras na mesma chave produziria dado que mente.
module Tracking::OriginAttributes
  UTM_KEYS = %w[utm_source utm_medium utm_campaign utm_term utm_content utm_id].freeze
  CLICK_ID_KEYS = %w[gclid gbraid wbraid fbclid msclkid ttclid].freeze
  DERIVED_KEYS = %w[referrer_host landing_path origin_kind].freeze

  CONVERSATION_PREFIX = 'last_'
  CONTACT_PREFIX = 'first_'

  # Base de cada escopo, sem prefixo.
  CONVERSATION_BASE_KEYS = (UTM_KEYS + CLICK_ID_KEYS + DERIVED_KEYS).freeze
  CONTACT_BASE_KEYS = (UTM_KEYS + DERIVED_KEYS).freeze

  # Valores de `origin_kind`. NÃO existe "direta": quando não há dado, o valor é
  # `nao_disponivel`. Chamar ausência de dado de "origem direta" é a mentira que o bloco 1.22
  # proíbe no relatório — e ela começaria aqui, no vocabulário.
  ORIGIN_KINDS = %w[busca_paga busca_organica social ia_generativa email referencia nao_disponivel].freeze

  # Valor máximo gravado por chave. Query string de campanha chega a ser gigante; truncar aqui
  # é o que impede uma URL de 8 KB de entrar inteira no painel e no prompt.
  MAX_VALUE_LENGTH = 255

  module_function

  def conversation_keys
    CONVERSATION_BASE_KEYS.map { |key| "#{CONVERSATION_PREFIX}#{key}" }
  end

  def contact_keys
    CONTACT_BASE_KEYS.map { |key| "#{CONTACT_PREFIX}#{key}" }
  end

  def all_keys
    conversation_keys + contact_keys
  end

  def conversation_key(base_key)
    "#{CONVERSATION_PREFIX}#{base_key}"
  end

  def contact_key(base_key)
    "#{CONTACT_PREFIX}#{base_key}"
  end

  def display_type_for(base_key)
    base_key == 'origin_kind' ? 'list' : 'text'
  end

  def values_for(base_key)
    base_key == 'origin_kind' ? ORIGIN_KINDS : []
  end
end
