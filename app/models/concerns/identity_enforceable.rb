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
    validate :ensure_identity_enforcement_write_is_not_ignored
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

  # §12 do ESTADO-BLOCOS-DEFINITIVO, item 7 — "se for teto, a API precisa parar de devolver
  # 200 para uma escrita que sera ignorada".
  #
  # A PRECEDENCIA continua escalada: quem decide se `hmac_mandatory` e piso (o valor
  # gravado vence) ou teto (o que a arvore faz) e o dono, e nada aqui decide por ele —
  # `resolved_identity_enforcement` acima nao mudou uma linha, e nenhuma inbox da frota
  # muda de comportamento por causa desta validacao.
  #
  # O que ela conserta e o unico lado que nao depende da decisao: hoje o PATCH grava
  # `observado` numa inbox com `hmac_mandatory`, responde 200, e a leitura seguinte devolve
  # `obrigatorio`. Quem apertou o botao sai da tela convencido de que ligou a observacao e
  # vai abrir depois um relatorio de um estado que nunca entrou em vigor. Sob "teto" a
  # escrita e que e mentira; sob "piso" a leitura e que esta errada — e o 200 de hoje
  # esconde qual dos dois.
  #
  # Duas condicoes de saida existem por motivos diferentes, e nenhuma e decorativa:
  #
  #   · `STRICT` passa porque nao esta sendo ignorado: e exatamente o que a inbox ja faz.
  #     Recusar tambem ele viraria "esta inbox nao aceita mais estado nenhum", que e outro
  #     comportamento.
  #   · so a ESCRITA e barrada, nunca o valor ja gravado. Uma inbox que carregava
  #     `observado` de antes de o canal virar mandatory tem de continuar salvavel — do
  #     contrario trocar o NOME dela levantaria RecordInvalid num campo que o formulario
  #     nem toca.
  def ensure_identity_enforcement_write_is_not_ignored
    return unless channel.try(:hmac_mandatory)
    return unless IDENTITY_ENFORCEMENT_STATES.include?(identity_enforcement.to_s)
    return if identity_enforcement.to_s == STRICT
    return unless identity_enforcement_being_written?

    errors.add(:identity_enforcement,
               I18n.t('errors.inbox.identity_enforcement.ignored_by_hmac_mandatory',
                      state: STRICT,
                      # Fallback DIFERENTE do texto traduzido de proposito: se ele fosse igual, o
                      # spec passaria tambem com a chave ausente do `en.yml` e nao mediria a
                      # traducao nenhuma.
                      default: 'cannot be set while the channel requires a signature'))
  end

  def identity_enforcement_being_written?
    return false unless additional_attributes_changed?

    previous = additional_attributes_was.is_a?(Hash) ? additional_attributes_was['identity_enforcement'] : nil
    previous.to_s != identity_enforcement.to_s
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
