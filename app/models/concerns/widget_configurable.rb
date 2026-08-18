# O lar da configuracao do widget (bloco 3.01, arbitragem A1 do PLANO-MESTRE).
#
# As quatro chaves de topo vivem em `inbox.additional_attributes` — sem coluna nova e sem migration:
#
#   widget_profile     escalar: "support" | "marketing" (nil e lido como "support", regra A4: sem backfill)
#   widget_triggers    jsonb: gatilhos e abordagem      (schema em 3.02 + 3.20)
#   widget_tracking    jsonb: identificadores PUBLICOS  (a projecao entregue ao widget e feita em 3.04)
#   widget_appearance  jsonb: tema, posicao, lancador   (schema em 3.18)
#
# Sao chaves de TOPO separadas, e nao um sub-hash unico, porque o merge do `#update` e raso
# (`inboxes_controller.rb:52-56`): com um `widget_config` unico, um PATCH parcial apagaria as outras tres.
#
# Regra dura herdada da A1: NENHUM segredo aqui. `additional_attributes` e servido inteiro por
# `_inbox.json.jbuilder:27` a qualquer agente com a inbox atribuida, e vai para o HTML de toda pagina
# do site do cliente. A lista negativa abaixo e o mecanismo — o bloco 5.01 apenas a amplia.
module WidgetConfigurable
  extend ActiveSupport::Concern

  WIDGET_PROFILES = %w[support marketing].freeze

  # As tres chaves que carregam objeto. `widget_profile` e escalar e valida por inclusao.
  WIDGET_OBJECT_KEYS = %i[widget_triggers widget_tracking widget_appearance].freeze

  # `*_token`, `*_secret`, `api_secret` — e as chaves nuas `token` e `secret`, que passariam
  # por uma leitura literal da lista do plano e sao o disfarce mais obvio.
  SECRET_KEY_PATTERN = /(\A|_)(token|secret)\z/i

  included do
    store_accessor :additional_attributes, :widget_profile, :widget_triggers, :widget_tracking, :widget_appearance

    validate :ensure_valid_widget_profile
    validate :ensure_widget_config_objects
    validate :ensure_no_secret_in_widget_config
  end

  # Leitura derivada, nunca backfill (A4): inbox sem a chave se comporta como "support",
  # que e literalmente o comportamento de hoje.
  def resolved_widget_profile
    widget_profile.presence || 'support'
  end

  private

  def ensure_valid_widget_profile
    return if widget_profile.blank?
    return if WIDGET_PROFILES.include?(widget_profile)

    errors.add(:widget_profile, I18n.t('errors.inbox.widget_config.invalid_profile', profiles: WIDGET_PROFILES.join(', ')))
  end

  def ensure_widget_config_objects
    WIDGET_OBJECT_KEYS.each do |key|
      value = public_send(key)
      next if value.nil? || value.is_a?(Hash)

      errors.add(key, I18n.t('errors.inbox.widget_config.must_be_object'))
    end
  end

  def ensure_no_secret_in_widget_config
    WIDGET_OBJECT_KEYS.each do |key|
      value = public_send(key)
      next unless value.is_a?(Hash)

      offender = find_secret_key(value)
      next if offender.nil?

      errors.add(key, I18n.t('errors.inbox.widget_config.secret_not_allowed', key: offender))
    end
  end

  # Varre em profundidade: um segredo escondido dentro de um objeto aninhado ou de um array
  # de objetos vaza exatamente como um de topo.
  def find_secret_key(node)
    return find_secret_key_in_hash(node) if node.is_a?(Hash)
    return find_secret_key_in_array(node) if node.is_a?(Array)

    nil
  end

  def find_secret_key_in_hash(hash)
    hash.each do |key, value|
      return key.to_s if key.to_s.match?(SECRET_KEY_PATTERN)

      nested = find_secret_key(value)
      return nested if nested
    end

    nil
  end

  def find_secret_key_in_array(array)
    array.each do |item|
      nested = find_secret_key(item)
      return nested if nested
    end

    nil
  end
end
