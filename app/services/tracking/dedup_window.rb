# frozen_string_literal: true

# Bloco 5.13 — a guarda da janela de 48 h (T-C6.3), que e o que impede a conversao contada em dobro.
#
# O mecanismo que o par navegador+servidor usa: os dois lados mandam o MESMO `event_id` e a Meta
# descarta o segundo — mas so dentro de 48 h. Passada a janela, a Meta ja esqueceu o primeiro, e o
# segundo entra como evento novo. O cliente decide midia com o numero dobrado (risco R11), e nada
# no log denuncia, porque as duas entregas responderam 200.
#
# A regra, entao, tem dois ramos, e a frase do plano cobre os dois:
#
#   evento COM par no navegador, fora da janela  -> NAO entrega. Contar de novo o que o navegador ja
#                                                   contou e exatamente a dobra. Fica `skipped`, com
#                                                   o motivo gravado e visivel no painel de 5.14.
#   evento SEM par (server-only, ex.: negocio ganho no funil, que o navegador nunca viu)
#                                                -> entrega normalmente. Nao ha o que dobrar; a
#                                                   janela nao se aplica a quem nunca teve par.
#
# "Tem par" nao e sobre o nome do evento apenas: e sobre uma entrega client-side REALMENTE enviada.
# Evento que propaga `event_id` mas cujo navegador nunca chegou a mandar (bloqueador ligado — o caso
# que motiva o server-side inteiro) precisa da entrega server-side, senao a guarda destruiria
# justamente os 20–40% que o bloco existe para recuperar.
module Tracking::DedupWindow
  WINDOW = 48.hours

  # Os seis eventos que propagam `event_id` ao navegador — §4.1 do contrato (itens 3, 4, 5, 6, 9, 11
  # da tabela de doze). Os outros nunca formam par.
  PAIRED_EVENTS = %w[
    chatspx_conversation_started
    chatspx_prechat_submitted
    chatspx_lead
    chatspx_lead_qualified
    chatspx_meeting_scheduled
    chatspx_deal_won
  ].freeze

  CLIENT_DESTINATIONS = %w[data_layer meta_pixel ga4_gtag].freeze

  EXPIRED_REASON = 'dedup_window_expired'

  module_function

  def expired?(event, now: Time.current)
    now - event.occurred_at > WINDOW
  end

  # O navegador JA contou este fato? Nao basta o nome estar na lista: exige entrega client-side com
  # status `sent`.
  def paired?(event)
    return false unless PAIRED_EVENTS.include?(event.name)

    event.tracking_deliveries.exists?(destination: CLIENT_DESTINATIONS, status: :sent)
  end

  # `nil` quando pode entregar; o motivo, quando nao pode. O motivo vai para `error_code`, e e o que
  # o suporte le no painel em vez de "sumiu".
  def skip_reason(event, now: Time.current)
    return nil unless expired?(event, now: now)
    return nil unless paired?(event)

    EXPIRED_REASON
  end
end
