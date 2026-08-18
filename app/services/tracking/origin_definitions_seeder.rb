# frozen_string_literal: true

# Bloco 1.18 — provisiona as `CustomAttributeDefinition` de origem para uma conta.
#
# Por que ANTES do parser (1.19): sem definição, o valor grava em `custom_attributes` e **não
# aparece no painel nem vira filtrável** — o dado existe no banco e some da vista, que é a mesma
# experiência de não existir. É a nota [R19 §D.3] do plano de tracking.
#
# Idempotente por construção: cria só o que falta e **nunca** reescreve definição existente —
# se o cliente renomeou "Origem da campanha (última)" para "Fonte", a curadoria dele é dele.
class Tracking::OriginDefinitionsSeeder
  def initialize(account)
    @account = account
  end

  SCOPES = [
    ['conversation_attribute', Tracking::OriginAttributes::CONVERSATION_BASE_KEYS, Tracking::OriginAttributes::CONVERSATION_PREFIX],
    ['contact_attribute', Tracking::OriginAttributes::CONTACT_BASE_KEYS, Tracking::OriginAttributes::CONTACT_PREFIX]
  ].freeze

  def perform
    SCOPES.flat_map { |attribute_model, base_keys, prefix| seed_scope(attribute_model, base_keys, prefix) }
  end

  private

  attr_reader :account

  def seed_scope(attribute_model, base_keys, prefix)
    existing = existing_keys(attribute_model)

    base_keys.filter_map do |base_key|
      key = "#{prefix}#{base_key}"
      next if existing.include?(key)

      create_definition(attribute_model, key, base_key, prefix)
    end
  end

  def existing_keys(attribute_model)
    account.custom_attribute_definitions.where(attribute_model: attribute_model).pluck(:attribute_key).to_set
  end

  def create_definition(attribute_model, key, base_key, prefix)
    account.custom_attribute_definitions.create!(
      attribute_key: key,
      attribute_display_name: display_name(base_key, prefix),
      attribute_display_type: Tracking::OriginAttributes.display_type_for(base_key),
      attribute_values: Tracking::OriginAttributes.values_for(base_key),
      attribute_model: attribute_model
    )
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
    # Duas requisições podem chegar juntas na primeira conversa com origem. O índice único
    # (attribute_key, attribute_model, account_id) resolve a corrida no banco; aqui só
    # engolimos a segunda, porque o efeito desejado — a definição existe — já aconteceu.
    raise unless already_exists?(attribute_model, key)

    Rails.logger.debug { "[1.18] definição #{key} já existia (corrida): #{e.class}" }
    nil
  end

  def already_exists?(attribute_model, key)
    account.custom_attribute_definitions.exists?(attribute_model: attribute_model, attribute_key: key)
  end

  # O nome vem no idioma da conta — a definição é criada uma vez e fica visível para o cliente.
  def display_name(base_key, prefix)
    scope = prefix == Tracking::OriginAttributes::CONTACT_PREFIX ? 'first' : 'last'
    chave = "tracking.origin_attributes.#{scope}.#{base_key}"

    I18n.t(chave, locale: account_locale, default: I18n.t(chave, locale: :en))
  end

  def account_locale
    locale = account.locale.presence || I18n.default_locale
    I18n.available_locales.include?(locale.to_sym) ? locale.to_sym : I18n.default_locale
  end
end
