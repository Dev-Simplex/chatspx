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

    # Regime 1 de A3: o perfil semeia o que nasce agora, e so na CRIACAO. Antes do INSERT, para que
    # o valor semeado passe pelas mesmas validacoes de todo o resto.
    before_create { WidgetProfile.seed_defaults(self) }

    validate :ensure_valid_widget_profile
    validate :ensure_widget_config_objects
    validate :ensure_no_secret_in_widget_config
    validate :ensure_widget_triggers_match_schema
    validate :ensure_widget_appearance_matches_schema
    validate :ensure_home_intents_are_a_real_choice
    validate :ensure_additional_attributes_fit_the_ceiling
  end

  # Leitura derivada, nunca backfill (A4): inbox sem a chave se comporta como "support",
  # que e literalmente o comportamento de hoje.
  def resolved_widget_profile
    widget_profile.presence || 'support'
  end

  # Bloco 3.20 (D1): a abordagem lida de forma derivada. Inbox sem a chave e `bold` com degradacao
  # ligada — que e a decisao de produto, nao o comportamento de hoje; nao ha migration nem backfill
  # (A4), e o SDK recebe os tres campos porque a avaliacao e dele (A5).
  # `approach_mobile` NUNCA herda `aggressive` do desktop: em celular o painel cobre a tela inteira.
  def resolved_widget_approach
    stored = widget_triggers.is_a?(Hash) ? widget_triggers : {}
    desktop = stored['approach'].presence || WidgetTriggersSchema::DEFAULT_APPROACH
    mobile = stored['approach_mobile'].presence || desktop
    mobile = WidgetTriggersSchema::DEFAULT_APPROACH unless WidgetTriggersSchema::MOBILE_APPROACHES.include?(mobile)
    degrade = stored.fetch('degrade_on_return', WidgetTriggersSchema::DEFAULT_DEGRADE_ON_RETURN)

    { 'approach' => desktop, 'approach_mobile' => mobile, 'degrade_on_return' => degrade }
  end

  # Bloco 3.04: os gatilhos entregues ao widget, com a abordagem JA RESOLVIDA por dentro. A abordagem
  # nao ganha chave propria no payload de proposito (A15): dois lugares para o mesmo fato obrigariam o
  # SDK a ler dois caminhos para tomar uma decisao so, e e assim que as duas pontas divergem.
  def resolved_widget_triggers
    stored = widget_triggers.is_a?(Hash) ? widget_triggers : {}

    stored.merge(resolved_widget_approach)
  end

  # Bloco 3.04: o que o widget recebe de tracking e uma projecao por lista branca, nunca o hash cru.
  def public_widget_tracking
    WidgetTrackingProjection.public_view(widget_tracking)
  end

  # A aparencia entregue ao widget e sempre COMPLETA: o banco e o padrao, e o padrao tem de existir
  # mesmo na inbox que nunca abriu a tela (regra A4 — sem migration e sem backfill).
  # Chave fora do schema e descartada aqui: o que sobrou de uma versao anterior nao vaza para o site.
  def resolved_widget_appearance
    stored = widget_appearance.is_a?(Hash) ? widget_appearance : {}

    WidgetAppearanceSchema::DEFAULTS.merge(stored.slice(*WidgetAppearanceSchema::DEFAULTS.keys))
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

  # Bloco 3.02: o schema dos gatilhos. A validacao fina mora aqui, e nao no strong params, porque e
  # aqui que ela consegue dizer QUAL campo esta errado.
  def ensure_widget_triggers_match_schema
    validate_against_schema(:widget_triggers, WidgetTriggersSchema::SCHEMA)
  end

  def ensure_widget_appearance_matches_schema
    validate_against_schema(:widget_appearance, WidgetAppearanceSchema::SCHEMA)
  end

  def ensure_home_intents_are_a_real_choice
    intents = widget_appearance.is_a?(Hash) ? widget_appearance['home_intents'] : nil

    WidgetAppearanceSchema.home_intents_violations(intents).each { |message| errors.add(:widget_appearance, message) }
  end

  # O teto do jsonb (3.18). `additional_attributes` inteiro vai para o HTML de toda pagina do site do
  # cliente e e servido a qualquer agente com a inbox atribuida — um hash aberto sem teto e o oposto
  # do orcamento de bytes que este plano defende em outros seis lugares.
  def ensure_additional_attributes_fit_the_ceiling
    size = (additional_attributes || {}).to_json.bytesize
    return if size <= Inbox::MAX_ADDITIONAL_ATTRIBUTES_BYTES

    errors.add(:additional_attributes,
               I18n.t('errors.inbox.widget_config.over_size_limit', limit: Inbox::MAX_ADDITIONAL_ATTRIBUTES_BYTES))
  end

  def validate_against_schema(key, schema)
    value = public_send(key)
    return unless value.is_a?(Hash)

    JSONSchemer.schema(schema).validate(value).each do |error|
      errors.add(key, WidgetSchemaErrorMessage.for(error))
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
