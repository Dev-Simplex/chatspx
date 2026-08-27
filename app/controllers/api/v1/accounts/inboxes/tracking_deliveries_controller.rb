# frozen_string_literal: true

# O log de entregas de rastreio de uma inbox (bloco 5.14, o painel de diagnostico).
#
# POR QUE ELE E SEPARADO DO LOG DE WEBHOOK, que tem nome parecido e faz outra coisa: o de
# webhook conta o que saiu para a URL do CLIENTE; este conta o que saiu para os destinos de
# ANUNCIO (Meta CAPI, GA4 MP, Google Ads). Confundir os dois foi o que deixou este endpoint
# sem existir enquanto o outro estava pronto — o painel chamava daqui e levava 404.
#
# CONTRATO DA RESPOSTA: SEM envelope `payload`. O front le `data.deliveries` e
# `data.retention_days` na RAIZ (`trackingDiagnosticsApi.js:17`, `useTrackingDiagnostics.js`).
# Embrulhar em `payload`, que e o costume dos outros controllers de conta, nao daria erro
# nenhum: daria uma lista VAZIA e SILENCIOSA, e o agente de suporte concluiria "nao saiu
# evento" quando a verdade seria "ninguem consegue ver".
#
# O QUE NUNCA SAI DAQUI E VALOR. A serializacao e uma lista fechada de colunas
# (`_tracking_delivery.json.jbuilder`): `properties` do evento, que e onde os valores moram,
# nao tem por onde sair, e a credencial da inbox nao chega a ser consultada.
class Api::V1::Accounts::Inboxes::TrackingDeliveriesController < Api::V1::Accounts::BaseController
  # 25 e o que o painel pede por default. O teto existe para que um `?limit=100000` digitado
  # na barra de enderecos nao vire varredura da tabela inteira.
  DEFAULT_LIMIT = 25
  MAX_LIMIT = 100

  # A janela que o painel ANUNCIA na tela. Mora aqui e nao no modelo de proposito: e o
  # contrato desta API, e `TrackingDelivery` pertence a trilha do 5.03, que hoje nao declara
  # retencao nenhuma. Quando houver job de expurgo, esta constante passa a ler de la.
  RETENTION_DAYS = 90

  # O nome obedece ao contrato de eventos (prefixo `chatspx_`, snake_case, 40 caracteres do
  # GA4) — nome invalido so falharia la no destino do cliente, longe de quem apertou o botao.
  TEST_EVENT_NAME = 'chatspx_diagnostic_test'

  before_action :fetch_inbox
  before_action -> { check_authorization(TrackingDelivery) }

  def index
    @deliveries = deliveries_scope.limit(limit)
    @retention_days = RETENTION_DAYS
    @kill_switch = kill_switch?
  end

  # O botao "enviar evento de teste" (T-C8.3 / T4.7).
  #
  # O evento passa pelo MESMO caminho de um evento de verdade — `EventRecorder` e, por
  # dentro dele, `DeliveryDispatcher`. Um atalho que falasse direto com o destino provaria
  # so que o nosso lado nao explodiu; o valor do botao e justamente exercitar a juncao que
  # costuma estar quebrada (credencial ausente, destino nao configurado, fila parada).
  def test
    event = record_test_event
    @delivery = event.tracking_deliveries.order(:id).last || no_destination_delivery(event)
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
  end

  # `account_id` e redundante — `@inbox` ja saiu de `Current.account.inboxes` — e fica assim
  # de proposito: isolamento entre contas escrito na propria consulta nao depende de ninguem
  # lembrar de como a inbox foi buscada la em cima.
  #
  # O desempate por `id` existe porque duas entregas do mesmo evento nascem no mesmo
  # `created_at`: sem ele a ordem entre elas seria a que o Postgres quisesse, e o "mais
  # recente primeiro" da tela seria mentira de vez em quando.
  def deliveries_scope
    TrackingDelivery
      .includes(:tracking_event)
      .joins(:tracking_event)
      .where(tracking_events: { inbox_id: @inbox.id, account_id: Current.account.id })
      .order(created_at: :desc, id: :desc)
  end

  def limit
    pedido = params[:limit].to_i
    return DEFAULT_LIMIT if pedido <= 0

    [pedido, MAX_LIMIT].min
  end

  def kill_switch?
    @inbox.additional_attributes.is_a?(Hash) && @inbox.additional_attributes['tracking_kill_switch'].present?
  end

  # `dedup_key` explicito e aleatorio porque a chave derivada usa `occurred_at.to_i`: dois
  # cliques no MESMO segundo produziriam a mesma chave, o registro seria deduplicado (que e
  # o comportamento certo para um fato real) e o segundo clique devolveria a entrega do
  # primeiro, sem nada ter sido enviado. Um teste que nao dispara nao testa.
  def record_test_event
    Tracking::EventRecorder.record!(
      name: TEST_EVENT_NAME,
      account: Current.account,
      inbox: @inbox,
      source: :server,
      properties: { 'diagnostic' => true },
      dedup_key: "diagnostic:#{@inbox.id}:#{SecureRandom.uuid}"
    )
  end

  # Sem credencial gravada o dispatcher nao reserva entrega nenhuma — e correto, nao ha
  # destino com quem falar. Mas devolver `{}` faria a tela dizer "falhou" sem motivo.
  # Este registro NAO PERSISTIDO carrega o motivo: `skipped` com `no_destination_configured`,
  # que e a diferenca entre "tentou e nao deu" e "nao havia para onde tentar".
  #
  # `destination` fica nulo de proposito: nomear um destino qualquer aqui seria inventar um
  # fato — nenhum destino foi escolhido, porque nenhum estava configurado.
  def no_destination_delivery(event)
    TrackingDelivery.new(tracking_event: event, status: :skipped,
                         error_code: 'no_destination_configured', field_names: [])
  end
end
