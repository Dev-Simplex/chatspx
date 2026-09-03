class Api::V1::Accounts::WebhooksController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_webhook, only: [:update, :destroy, :rotate_secret, :deliveries, :replay]

  def index
    @webhooks = Current.account.webhooks
  end

  def create
    @webhook = Current.account.webhooks.new(webhook_params)
    @webhook.save!
    # Bloco 4.14: o ping sai no cadastro para que a primeira entrega real nao seja a
    # descoberta de que a URL esta errada. Falha dele nao derruba a criacao — o registro
    # existe, e o resultado do ping aparece na tela de entregas como qualquer outro.
    @webhook.send_validation_ping!
  end

  def update
    @webhook.update!(webhook_params)
  end

  def destroy
    @webhook.destroy!
    head :ok
  end

  # Bloco 4.14 — rotacao. O segredo novo volta UMA vez, aqui, porque este e o unico
  # momento em que o cliente pode copia-lo: o index nao o devolve mais.
  def rotate_secret
    @webhook.reset_secret!
    render 'api/v1/accounts/webhooks/create'
  end

  # A tela de entregas: e ela que mostra a entrega falhada.
  def deliveries
    @deliveries = @webhook.webhook_deliveries.recent_first.limit(100)
  end

  # Reenvio. O delivery_id NAO e regerado — e ele que permite ao destino deduplicar.
  def replay
    delivery = @webhook.webhook_deliveries.find(params[:delivery_id])
    delivery.replay!
    render json: { delivery_id: delivery.delivery_id, attempts: delivery.attempts }
  end

  private

  def webhook_params
    # `:inbox_id` ja era permitido; o que faltava era ele SIGNIFICAR alguma coisa na
    # entrega (bloco 4.13). `:webhook_type` segue de fora de proposito: o tipo passou a ser
    # irrelevante para a entrega, e deixar a tela grava-lo so recriaria o modo de falha em
    # que um webhook some da entrega sem ninguem entender por que.
    params.require(:webhook).permit(:inbox_id, :name, :url, subscriptions: [])
  end

  def fetch_webhook
    @webhook = Current.account.webhooks.find(params[:id])
  end
end
