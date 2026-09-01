# frozen_string_literal: true

# Bloco 5.09 (T-C7.4/T-C7.6) — o consentimento do lado do SERVIDOR.
#
# Este arquivo e o ESPELHO de `app/javascript/sdk/tracking/consent.js`, e o espelho e literal de
# proposito: os quatro propositos, os dois valores e os tres modos tem aqui exatamente os nomes e as
# grafias que o navegador escreve. Vocabulario traduzido na travessia e o jeito conhecido de o gate
# existir nas duas pontas e nao gatear nada em nenhuma — o lado que recebe `'granted'` comparando com
# `'GRANTED'` nega tudo, para sempre, em silencio.
#
# A GRAFIA. O Consent Mode do navegador usa minusculas (`granted`); o Measurement Protocol do GA4 usa
# MAIUSCULAS (`GRANTED`). As duas estao certas nas suas casas, e a conversao acontece num lugar so —
# `ga4_value` — em vez de espalhada por cada destino.
#
# O MODO MANDA, e e isto que torna o bloco instalavel numa frota que ja roda:
#
#   disabled  (o default por ausencia) o comportamento de HOJE — sem gate, e o `consent_block` sai
#             concedido, como saia antes deste bloco existir. Ligar o gate para quem nao pediu
#             desligaria a medicao de toda conta que nunca ouviu falar de Consent Mode.
#   basic     gate ligado: o que nao foi concedido nao sai.
#   advanced  idem.
#
# A DIRECAO DA DUVIDA e sempre a mesma: com o modo ativo, o que nao se sabe le-se como NEGADO. Um
# evento a menos e um numero errado no painel do cliente; um evento a mais e tratamento de dado
# pessoal sem base legal.
module Tracking::ConsentState
  # Os quatro sinais do Consent Mode v2, na ordem e com os nomes do Google.
  PURPOSES = %w[ad_storage ad_user_data ad_personalization analytics_storage].freeze

  GRANTED = 'granted'
  DENIED = 'denied'
  VALUES = [GRANTED, DENIED].freeze

  # Os modos validados pelo schema de `widget_tracking` (5.01). Repetidos aqui como leitura, nunca
  # como segunda fonte: `WidgetTrackingSchema::CONSENT_MODES` continua sendo quem valida a escrita.
  DISABLED_MODE = 'disabled'

  # O prefixo das chaves em `custom_attributes` — mesma convencao de `Tracking::OriginAttributes`,
  # que ja usa `first_`/`last_`. Chave plana, e nao um objeto aninhado, porque `custom_attributes` e
  # lido por tela de agente e por filtro de conversa: um hash dentro de uma chave nao filtra.
  ATTRIBUTE_PREFIX = 'consent_'

  module_function

  def attribute_key(purpose)
    "#{ATTRIBUTE_PREFIX}#{purpose}"
  end

  # So os quatro propositos conhecidos, so os dois valores conhecidos. Chave estranha e valor
  # estranho somem — o payload do GA4 nao e lugar de ecoar o que um site desconhecido mandou.
  def normalize(raw)
    return {} unless raw.respond_to?(:each_pair)

    PURPOSES.each_with_object({}) do |purpose, acc|
      value = raw[purpose] || raw[purpose.to_sym]
      acc[purpose] = value.to_s if VALUES.include?(value.to_s)
    end
  end

  # Le as chaves `consent_*` de um `custom_attributes` (conversa ou contato).
  def from_attributes(attributes)
    return {} unless attributes.is_a?(Hash)

    bag = attributes.with_indifferent_access
    PURPOSES.each_with_object({}) do |purpose, acc|
      value = bag[attribute_key(purpose)]
      acc[purpose] = value.to_s if VALUES.include?(value.to_s)
    end
  end

  # O estado vigente para um fato que esta NASCENDO: a conversa primeiro (ela e desta visita), o
  # contato como reserva (a pessoa ja tinha respondido a CMP numa visita anterior).
  def current_for(conversation: nil, contact: nil)
    from_attributes(conversation&.custom_attributes).presence ||
      from_attributes(contact&.custom_attributes).presence ||
      {}
  end

  def mode_for(inbox)
    tracking = inbox&.additional_attributes.to_h['widget_tracking']
    mode = tracking.is_a?(Hash) ? tracking['consent_mode'].to_s : ''

    WidgetTrackingSchema::CONSENT_MODES.include?(mode) ? mode : DISABLED_MODE
  end

  def active_for?(inbox)
    mode_for(inbox) != DISABLED_MODE
  end

  # A decisao para um evento JA GRAVADO. Prefere o retrato do proprio evento — que e o que valia
  # quando o fato aconteceu, e portanto a base legal daquele envio — e so cai no estado atual da
  # conversa quando o evento nao tem retrato (linha anterior a esta coluna existir).
  def for_event(event)
    snapshot = normalize(event.consent)
    snapshot = current_for(conversation: event.conversation, contact: event.contact) if snapshot.blank?

    Decision.new(state: snapshot, active: active_for?(event.inbox))
  end

  # O retrato a gravar junto do fato. Vazio quando o modo esta `disabled`: ausencia com significado
  # (regra A4) e melhor que quatro `granted` inventados que ninguem concedeu.
  def snapshot_for(inbox:, conversation: nil, contact: nil, explicit: nil)
    return {} unless active_for?(inbox)

    explicit = normalize(explicit)
    return explicit if explicit.present?

    current_for(conversation: conversation, contact: contact)
  end

  # A resposta ao destino. Nao guarda o evento nem o inbox: so o que foi decidido e se o gate vale.
  class Decision
    def initialize(state:, active:)
      @state = state
      @active = active
    end

    attr_reader :state

    def active?
      @active
    end

    # Com o modo `disabled` tudo passa — e o comportamento anterior a este bloco, preservado de
    # proposito. Com o modo ativo, so passa o que foi concedido de verdade.
    def granted?(purpose)
      return true unless active?

      @state[purpose] == GRANTED
    end

    # A grafia do Measurement Protocol.
    def ga4_value(purpose)
      granted?(purpose) ? GRANTED.upcase : DENIED.upcase
    end
  end
end
