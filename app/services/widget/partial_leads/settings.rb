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
  MAX_LABEL_LENGTH = 100

  # As unicas chaves que a tela pode escrever. E lista fechada e nao adorno: `internal_attributes`
  # guarda coisas de outros assuntos (`flows_engine_enabled`, por exemplo), e um `merge` do corpo
  # cru deixaria a tela de lead incompleto ligar o motor de flows da conta.
  WRITABLE_KEYS = DEFAULTS.keys.freeze

  # A etiqueta vira TAG no contato (`Labelable#add_labels`). O conjunto de caracteres e o mesmo
  # que o modelo `Label` aceita (letra, numero, hifen, sublinhado, ponto) — escrever aqui um
  # valor que o painel nao consegue representar como etiqueta e gravar uma configuracao que nao
  # tem efeito visivel.
  LABEL_ALLOWED = /[^\p{L}\p{N}\-_.]/

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

  # Os valores RESOLVIDOS — nunca o hash cru. E o que a tela desenha, e a razao e o contrato
  # deste arquivo: quem consome nao redefine o padrao. Com a chave ausente, a tela mostra 5
  # minutos e 30 dias porque e isso que o servidor vai fazer; mostrar campo vazio faria o
  # administrador achar que nao ha retencao nenhuma.
  def to_h
    {
      'partial_lead_capture_enabled' => enabled?,
      'partial_lead_abandon_after_minutes' => abandon_after_minutes,
      'partial_lead_retention_days' => retention_days,
      'partial_lead_label' => label
    }
  end

  # Grava as chaves conhecidas JA NORMALIZADAS e devolve os valores resolvidos.
  #
  # Normalizar na escrita (e nao so no `clamp` da leitura) e o que impede a tela de mentir: se
  # o banco guardasse `"para sempre"` e a leitura caisse no default, o administrador continuaria
  # vendo o texto que digitou e acreditando numa retencao que nao existe.
  def update(attributes)
    incoming = attributes.to_h.stringify_keys.slice(*WRITABLE_KEYS)
    return to_h if incoming.blank?

    @account.update!(internal_attributes: stored_attributes.merge(normalize(incoming)))
    to_h
  end

  private

  def stored_attributes
    attributes = @account.internal_attributes
    attributes.is_a?(Hash) ? attributes : {}
  end

  def normalize(incoming)
    incoming.each_with_object({}) do |(key, value), result|
      result[key] = case key
                    when 'partial_lead_capture_enabled'
                      ActiveModel::Type::Boolean.new.cast(value) || false
                    when 'partial_lead_abandon_after_minutes'
                      clamp(value, MIN_ABANDON_MINUTES, MAX_ABANDON_MINUTES, DEFAULTS[key])
                    when 'partial_lead_retention_days'
                      clamp(value, MIN_RETENTION_DAYS, MAX_RETENTION_DAYS, DEFAULTS[key])
                    else
                      normalized_label(value)
                    end
    end
  end

  # Vazio continua valendo "sem etiqueta" (o mockup 22 §3 tem um botao proprio para isso), entao
  # o branco NAO cai no padrao — cair no padrao religaria a etiqueta que o administrador desligou.
  def normalized_label(value)
    value.to_s.strip.downcase.gsub(/\s+/, '-').gsub(LABEL_ALLOWED, '').slice(0, MAX_LABEL_LENGTH).to_s
  end

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
