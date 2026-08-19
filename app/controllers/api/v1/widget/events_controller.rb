class Api::V1::Widget::EventsController < Api::V1::Widget::BaseController
  include Events::Types

  # O nome do evento vinha do site do cliente e ia direto para o barramento:
  # qualquer string virava um publish para TODOS os listeners registrados, e o
  # EventDispatcherJob (fila `critical`, retry_on attempts: 3) ainda gastava 3
  # tentativas com cada nome que fizesse um listener explodir.
  #
  # O widget so emite dois nomes por este endpoint:
  #   webwidget.triggered  — sdk/IFrameHelper.js:253
  #   campaign.triggered   — widget/api/endPoints.js:105
  PERMITTED_EVENT_NAMES = [WEBWIDGET_TRIGGERED, CAMPAIGN_TRIGGERED].freeze

  # ── DOIS VOCABULARIOS, UM ENDPOINT (blocos 5.05 e 5.16) ────────────────────────────────────
  #
  # Nome sem prefixo `chatspx_` e evento do BARRAMENTO interno: continua indo ao dispatcher, como
  # sempre foi, e a lista fechada acima segue valendo.
  #
  # Nome com prefixo `chatspx_` e evento de TRACKING, emitido pelo site do cliente por
  # `window.$chatwoot.track()`. Ele NAO vai ao barramento — publicar um nome inventado pelo
  # integrador para todos os listeners do Rails e exatamente o buraco que a lista fechada acima
  # existe para tapar. Ele vira registro em `tracking_events`, e nada mais.
  #
  # A RESPOSTA MUDOU DE 204 PARA 200 (bloco 5.05, regra RC7): o `event_id` nasce no servidor e
  # volta ao widget. O corpo e aditivo — quem so olhava o status continua funcionando, e o
  # `pushEvent` do SDK nao mudou uma linha. Foi medido: `widget/api/events.js` faz `API.post` e
  # ignora o retorno; `2xx` com corpo e `2xx` sem corpo sao indistinguiveis para ele.
  def create
    return render_site_event if Tracking::WidgetEventRecorder.tracking_name?(permitted_params[:name])

    unless PERMITTED_EVENT_NAMES.include?(permitted_params[:name])
      render json: { error: "name must be one of: #{PERMITTED_EVENT_NAMES.join(', ')}" },
             status: :unprocessable_entity and return
    end

    info = permitted_params[:event_info].to_h.merge(event_info)
    Rails.configuration.dispatcher.dispatch(permitted_params[:name], Time.zone.now, contact_inbox: @contact_inbox,
                                                                                    event_info: info)

    render json: { event_id: legacy_event_id(info) }, status: :ok
  end

  private

  # `nil` quando o nome nao tem contrapartida no vocabulario de tracking (`campaign.triggered`) ou
  # quando o registro falhou — e o `nil` e honesto: ele diz "nao ha id", nunca inventa um que o
  # servidor nao gravou. Ver `Tracking::WidgetEventRecorder`.
  def legacy_event_id(info)
    Tracking::WidgetEventRecorder.record_legacy(
      contact_inbox: @contact_inbox,
      name: permitted_params[:name],
      event_info: info,
      occurred_at: Time.zone.now
    )&.event_id
  end

  # Bloco 5.16. As tres regras de nome do contrato (§1) e a recusa de PII em `properties` sao
  # validacoes do MODELO — deixa-las levantar e responder 422 com a mensagem delas e o que faz o
  # integrador ler a regra que violou, em vez de descobrir dias depois que o evento nunca chegou.
  def render_site_event
    evento = Tracking::WidgetEventRecorder.record_site_event!(
      contact_inbox: @contact_inbox,
      name: permitted_params[:name],
      properties: site_event_properties,
      occurred_at: Time.zone.now
    )

    render json: { event_id: evento.event_id }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  # `event_info` do site nao e mesclado com o `event_info` do widget (idioma, navegador) de
  # proposito: aquilo e diagnostico do nosso widget, e `properties` de evento de tracking viaja
  # para o `dataLayer` e para os params do `fbq`/`gtag`. Cada chave a mais ali e uma chave a mais
  # publicada na pagina do cliente.
  def site_event_properties
    permitted_params[:event_info].to_h
  end

  def event_info
    {
      widget_language: params[:locale],
      browser_language: browser.accept_language.first&.code,
      browser: browser_params
    }
  end

  def permitted_params
    params.permit(:name, :website_token, event_info: {})
  end
end
