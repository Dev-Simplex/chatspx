# frozen_string_literal: true

# Bloco 4.18 — as quatro decisoes de negocio do lead incompleto, com DEFAULT DECLARADO.
#
# Moram em `account.internal_attributes` pelo mesmo motivo que `flows_engine_enabled`
# (account.rb): o bitmask de `feature_flags` ja estourou o bigint no ChatSPX, e uma
# coluna nova por decisao de produto e desperdicio. A tela por inbox do mockup 22 §3 e
# do bloco de configuracao — ela CONSOME estes nomes, nao os redefine.
#
# O default de `enabled` e FALSE, e isso e a leitura de LGPD, nao timidez: o registro
# parcial e dado pessoal de quem NAO concluiu nada e, portanto, nao consentiu com nada.
# Guardar por padrao seria decidir pelo cliente uma coisa que e dele decidir. Com a chave
# ausente, o comportamento e exatamente o de hoje: nada e gravado.
class Widget::PartialLeads::Settings
  DEFAULTS = {
    'partial_lead_capture_enabled' => false,
    # Minutos sem nova resposta ate considerar abandonado. 5 e o default do mockup 22 §3
    # ("Tempo ate considerar abandonado": 2 / 5 / 15).
    'partial_lead_abandon_after_minutes' => 5,
    # Retencao do REGISTRO PARCIAL, em dias. 30 e conservador de proposito: e o dado de
    # quem desistiu, e o valor comercial dele decai em dias, nao em anos.
    'partial_lead_retention_days' => 30,
    # Etiqueta aplicada ao contato materializado (mockup 22 §3). Vazio desliga a etiqueta
    # sem desligar a captura.
    'partial_lead_label' => 'lead-incompleto'
  }.freeze

  MIN_ABANDON_MINUTES = 1
  MAX_ABANDON_MINUTES = 24 * 60
  MIN_RETENTION_DAYS = 1
  MAX_RETENTION_DAYS = 365

  def initialize(account)
    @account = account
  end

  def enabled?
    ActiveModel::Type::Boolean.new.cast(stored('partial_lead_capture_enabled')) || false
  end

  def abandon_after_minutes
    clamp(stored('partial_lead_abandon_after_minutes'), MIN_ABANDON_MINUTES, MAX_ABANDON_MINUTES,
          DEFAULTS['partial_lead_abandon_after_minutes'])
  end

  def retention_days
    clamp(stored('partial_lead_retention_days'), MIN_RETENTION_DAYS, MAX_RETENTION_DAYS,
          DEFAULTS['partial_lead_retention_days'])
  end

  def label
    value = stored('partial_lead_label')
    return DEFAULTS['partial_lead_label'] if value.nil?

    value.to_s.strip
  end

  private

  def stored(key)
    attributes = @account&.internal_attributes
    attributes.is_a?(Hash) ? attributes[key] : nil
  end

  # Valor torto (String, negativo, absurdo) NAO pode virar retencao infinita nem varredura
  # a cada segundo: cai no default declarado, que e o comportamento previsivel.
  def clamp(value, minimum, maximum, fallback)
    number = Integer(value, exception: false)
    return fallback if number.nil?

    number.clamp(minimum, maximum)
  end
end
