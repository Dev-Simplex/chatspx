# Criar o pedido: pendurado no Conversations::BaseController de propósito — herda
# `authorize @conversation, :show?` E o authorize_team_access de graça.
class Api::V1::Accounts::Conversations::TakeoverRequestsController < Api::V1::Accounts::Conversations::BaseController
  before_action :check_authorization

  def create
    @takeover_request = Conversations::TakeoverRequestService.new(
      conversation: @conversation, actor: Current.user
    ).create!(reason: params[:reason])

    Conversations::TakeoverRequestNotifier.new(@takeover_request).notify_requested
    render 'api/v1/accounts/takeover_requests/show', formats: [:json]
  rescue Conversations::TakeoverRequestService::Error => e
    render json: { error: e.message, error_code: e.error_code }, status: :unprocessable_entity
  end

  private

  # Não existe model TakeoverRequest (o model é ConversationTakeoverRequest), e o
  # classify.constantize do Api::BaseController quebraria com NameError.
  def check_authorization
    authorize(ConversationTakeoverRequest.new(account_id: Current.account.id))
  end
end
