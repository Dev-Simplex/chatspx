class Api::V1::Accounts::WebhooksController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_webhook, only: [:update, :destroy]

  def index
    @webhooks = Current.account.webhooks
  end

  def create
    @webhook = Current.account.webhooks.new(webhook_params)
    @webhook.save!
  end

  def update
    @webhook.update!(webhook_params)
  end

  def destroy
    @webhook.destroy!
    head :ok
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
