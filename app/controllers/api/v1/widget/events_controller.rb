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

  # ── Bloco 5.05 — o `event_id` nasce no backend e volta ao widget ──────────────────────────
  #
  # A resposta era `204 No Content`. Passa a ser `200 { event_id, name }` porque quem precisa do
  # id e o NAVEGADOR: a ponte de tags do 5.10 manda o mesmo id ao `fbq` como `eventID`, e o
  # caminho server-side do 5.11 manda como `event_id` no CAPI. Sem o mesmo id nos dois lados, a
  # Meta conta a mesma conversao duas vezes (contrato §4.1, regra RC7).
  #
  # SOMENTE os nomes antigos que TEM contraparte declarada no vocabulario `chatspx_` viram
  # registro. `campaign.triggered` NAO tem: o contrato (§2, linha "teaser/campanha exibida") e o
  # `SDK_EVENT_CONTRACT` do 5.04 declaram `tracking: null`. Inventar `chatspx_campaign_shown`
  # aqui criaria vocabulario que o documento nega — e vocabulario inventado numa ponta e
  # exatamente o defeito de juncao que esta onda existe para nao repetir. A chave sai presente e
  # NULA: ausencia declarada le-se diferente de omissao.
  TRACKING_NAME_FOR = { WEBWIDGET_TRIGGERED => 'chatspx_widget_opened' }.freeze

  # ── Bloco 5.16 — `track(name, properties)` do site do cliente ─────────────────────────────
  #
  # O site emite evento PROPRIO (`chatspx_orcamento_pedido`), e por isso nao ha lista fechada:
  # o contrato §1 e explicito em recusar uma, senao o 5.16 nao existiria. O que ha e o FORMATO,
  # validado por `TrackingEvent` — prefixo, snake_case e os 40 caracteres do GA4 — e ele nunca
  # chega ao barramento de eventos: um nome livre publicando para todos os listeners e a lesao
  # que a lista acima ja fechou.
  SITE_EVENT_PREFIX = TrackingEvent::NAME_PREFIX

  # `properties` e jsonb vindo do site do cliente. O teto existe porque um laco no script dele
  # escreveria megabytes numa coluna nossa sem nenhum limite natural pelo caminho.
  MAX_PROPERTIES_BYTES = 4_096

  def create
    return render_name_recusado unless bus_event? || site_event?
    return render_properties_grandes_demais if propriedades_grandes_demais?

    dispatch_to_bus if bus_event?
    registro = registrar_fato

    render json: { event_id: registro&.event_id, name: registro&.name }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  private

  def event_name
    @event_name ||= permitted_params[:name].to_s
  end

  def bus_event?
    PERMITTED_EVENT_NAMES.include?(event_name)
  end

  def site_event?
    event_name.start_with?(SITE_EVENT_PREFIX)
  end

  def dispatch_to_bus
    Rails.configuration.dispatcher.dispatch(
      event_name, Time.zone.now,
      contact_inbox: @contact_inbox,
      event_info: permitted_params[:event_info].to_h.merge(event_info)
    )
  end

  # Devolve `nil` quando o fato nao tem contraparte no vocabulario de tracking — ver
  # `TRACKING_NAME_FOR`. `nil` aqui NAO e falha: e a ausencia que o contrato declara.
  def registrar_fato
    nome = site_event? ? event_name : TRACKING_NAME_FOR[event_name]
    return nil if nome.blank?

    Tracking::EventRecorder.record!(
      name: nome,
      account: inbox.account,
      inbox: inbox,
      contact: @contact,
      properties: propriedades,
      source: site_event? ? :site : :widget,
      dedup_key: dedup_key
    )
  end

  # A CHAVE DE IDEMPOTENCIA, e por que ela e passada em vez de derivada.
  #
  # A derivacao padrao do contrato (§4.2) usa `occurred_at.to_i`. Ela resolve o retry de um JOB,
  # que reapresenta o mesmo instante — mas aqui a retentativa vem da REDE e do proprio visitante,
  # e cai noutro segundo. Sem chave explicita, um reenvio do POST viraria um segundo registro com
  # um segundo `event_id`, e nenhum indice de (evento, destino) tocaria nele: para o banco sao
  # eventos diferentes. Em CAPI isso e conversao contada duas vezes.
  #
  #   site      `site:<source_id da sessao>:<event_key>` — o `event_key` e gerado uma vez por
  #             chamada de `track()` no navegador (sdk/tracking/tags.js). Chamada nova, chave
  #             nova, evento novo; reenvio da MESMA chamada, mesma chave, um registro so.
  #             Sem `event_key` (cliente de versao anterior) cai na derivacao padrao — que ainda
  #             protege do reenvio dentro do mesmo segundo, e nao mais que isso.
  #   widget    `widget_opened:<source_id da sessao>` — o `pushEvent` do 5.05 NAO muda de
  #             assinatura (e aceite), entao nao ha de onde tirar uma chave por gesto. A
  #             consequencia esta declarada: abrir o painel tres vezes na mesma sessao registra
  #             UMA vez e devolve sempre o mesmo `event_id`. Como o evento nao propaga id para
  #             a Meta (contrato §4.1), contar de menos aqui nao desalinha destino nenhum.
  #
  # A sessao entra pela AUTENTICACAO (`@contact_inbox`), nunca pelo corpo: aceita-la do corpo
  # deixaria um cliente adulterado colidir com a chave de outro visitante e apagar o evento dele.
  def dedup_key
    return "widget_opened:#{@contact_inbox.source_id}" unless site_event?

    chave = permitted_params[:event_key].to_s
    return nil if chave.blank?

    "site:#{@contact_inbox.source_id}:#{chave}"
  end

  def propriedades
    site_event? ? permitted_params[:properties].to_h : {}
  end

  def propriedades_grandes_demais?
    site_event? && propriedades.to_json.bytesize > MAX_PROPERTIES_BYTES
  end

  def render_name_recusado
    render json: {
      error: "name must be one of: #{PERMITTED_EVENT_NAMES.join(', ')} — or start with #{SITE_EVENT_PREFIX} (track())"
    }, status: :unprocessable_entity
  end

  def render_properties_grandes_demais
    render json: { error: "properties passa do limite de #{MAX_PROPERTIES_BYTES} bytes" },
           status: :unprocessable_entity
  end

  def event_info
    {
      widget_language: params[:locale],
      browser_language: browser.accept_language.first&.code,
      browser: browser_params
    }
  end

  def permitted_params
    params.permit(:name, :website_token, :event_key, event_info: {}, properties: {})
  end
end
