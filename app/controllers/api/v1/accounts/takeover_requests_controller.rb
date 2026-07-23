# Responder/acompanhar pedidos. Nível de CONTA: o dono responde a partir de uma
# lista ("Pedidos"), não de dentro da conversa.
class Api::V1::Accounts::TakeoverRequestsController < Api::V1::Accounts::BaseController
  before_action :fetch_request, only: [:approve, :deny, :cancel]
  before_action :check_authorization

  def index
    @takeover_requests = scoped_requests
                         .includes(:requester, :owner, conversation: [:contact, :inbox])
                         .order(created_at: :desc)
                         .limit(50)
  end

  def approve
    resolve! { |service| service.approve!(note: params[:response_note]) }
  end

  def deny
    resolve! { |service| service.deny!(note: params[:response_note]) }
  end

  def cancel
    resolve!(&:cancel!)
  end

  private

  def resolve!
    service = Conversations::TakeoverRequestService.new(request: @takeover_request, actor: Current.user)
    yield(service)
    Conversations::TakeoverRequestNotifier.new(@takeover_request).notify_responded
    render 'api/v1/accounts/takeover_requests/show', formats: [:json]
  rescue Conversations::TakeoverRequestService::Error => e
    render json: { error: e.message, error_code: e.error_code }, status: :unprocessable_entity
  end

  # Seguro por CONSTRUÇÃO: o agente só enxerga pedido em que ele é dono ou
  # solicitante. Admin vê a conta toda.
  def scoped_requests
    base = Current.account.conversation_takeover_requests
    base = base.where(status: params[:status]) if params[:status].present?
    return base if Current.account_user&.administrator?

    case params[:scope]
    when 'incoming' then base.incoming_for(Current.user)
    when 'outgoing' then base.outgoing_for(Current.user)
    else base.where(owner_id: Current.user.id).or(base.where(requester_id: Current.user.id))
    end
  end

  def fetch_request
    @takeover_request = Current.account.conversation_takeover_requests.find(params[:id])
  end

  def check_authorization
    authorize(@takeover_request || ConversationTakeoverRequest.new(account_id: Current.account.id))
  end
end
