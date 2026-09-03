# frozen_string_literal: true

# Bloco 4.15 — os tres estados de enforcement de identidade de uma inbox.
#
#   desativado   quem chega sem assinatura passa. E o comportamento de hoje de toda
#                inbox com `hmac_mandatory` desligado.
#   observado    passa exatamente igual ao desativado — NENHUMA sessao quebra — e o que
#                passaria a ser recusado fica CONTAVEL (Identity::EnforcementReport).
#   obrigatorio  identidade sem assinatura valida e recusada.
#
# `hmac_mandatory` (channel_web_widgets:849, channel_api:695) fica exatamente como esta.
# A resolucao abaixo apenas o LE, e o le como piso: inbox que hoje exige assinatura nao
# pode ser afrouxada por um valor gravado no jsonb. Assim este bloco nao muda o
# comportamento de nenhuma inbox da frota — ele so da nome aos estados e acrescenta o do
# meio.
#
# O estado do meio e a razao de o bloco existir. Sem ele, ligar enforcement numa frota
# com clientes ja integrados e aposta: nao se sabe quantas sessoes o 401 derruba. Com ele
# mede-se primeiro e recusa-se depois.
#
# Mora em `inbox.additional_attributes`, pela convencao do bloco 3.01: sem coluna nova e
# sem migration. Regra A4 vale aqui tambem — `nil` tem significado e backfill nao
# acontece. E nao ha segredo nenhum nestas chaves: `_inbox.json.jbuilder:27` serve o hash
# inteiro a qualquer agente da inbox.
module IdentityEnforceable
  extend ActiveSupport::Concern

  DISABLED = 'desativado'
  OBSERVED = 'observado'
  STRICT = 'obrigatorio'
  IDENTITY_ENFORCEMENT_STATES = [DISABLED, OBSERVED, STRICT].freeze

  included do
    store_accessor :additional_attributes, :identity_enforcement, :identity_enforcement_observed_since

    validate :ensure_valid_identity_enforcement
    before_save :stamp_identity_enforcement_observation
  end

  # Leitura derivada, nunca backfill (A4): inbox sem a chave se comporta como hoje.
  def resolved_identity_enforcement
    # `hmac_mandatory` so ENDURECE. Nao existe caminho por onde escrever no jsonb
    # afrouxe uma inbox que hoje exige assinatura.
    return STRICT if channel.try(:hmac_mandatory)

    stored = identity_enforcement.to_s
    IDENTITY_ENFORCEMENT_STATES.include?(stored) ? stored : DISABLED
  end

  def identity_enforcement_strict?
    resolved_identity_enforcement == STRICT
  end

  def identity_enforcement_observed?
    resolved_identity_enforcement == OBSERVED
  end

  # Verdadeiro nos dois estados que se importam com assinatura. `observado` entra aqui
  # porque ele precisa MEDIR o mesmo universo que `obrigatorio` recusaria — se medisse
  # outro universo, o numero nao serviria para decidir a virada.
  def identity_enforcement_watching?
    identity_enforcement_strict? || identity_enforcement_observed?
  end

  def identity_enforcement_observed_since_time
    parsed = identity_enforcement_observed_since
    return if parsed.blank?

    Time.zone.parse(parsed.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  private

  def ensure_valid_identity_enforcement
    return if identity_enforcement.blank?
    return if IDENTITY_ENFORCEMENT_STATES.include?(identity_enforcement.to_s)

    errors.add(:identity_enforcement,
               I18n.t('errors.inbox.identity_enforcement.invalid_state',
                      states: IDENTITY_ENFORCEMENT_STATES.join(', '),
                      default: "must be one of: #{IDENTITY_ENFORCEMENT_STATES.join(', ')}"))
  end

  # O relatorio precisa separar o que foi MEDIDO sob observacao do que e historico. E a
  # mesma regra do Tracking::OriginReport: apresentar historico como medido e mentira, e
  # zero seria pior ainda — leria-se "nao veio ninguem" onde veio gente sem ninguem
  # anotando. A marca nasce no instante em que a observacao comeca.
  def stamp_identity_enforcement_observation
    return unless additional_attributes_changed?
    return unless identity_enforcement.to_s == OBSERVED

    previous = additional_attributes_was.is_a?(Hash) ? additional_attributes_was['identity_enforcement'] : nil
    return if previous.to_s == OBSERVED

    self.identity_enforcement_observed_since = Time.zone.now.iso8601
  end
end
