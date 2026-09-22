# Criar o pedido: pendurado no Conversations::BaseController de propósito — herda
# `authorize @conversation, :show?` E o authorize_team_access de graça.
class Api::V1::Accounts::Conversations::TakeoverRequestsController < Api::V1::Accounts::Conversations::BaseController
  # O pedido é justamente COMO se ganha acesso a uma conversa isolada de outro
  # agente — aplicar o guard de isolamento aqui seria galinha-e-ovo (não dá pra
  # pedir o que não se pode acessar). O guard de time + a policy show? continuam
  # valendo (só peço conversa que alcanço pelo time/inbox).
  skip_before_action :authorize_agent_conversation_access
  # Mesmo argumento para o TIME: pedir é como se ganha acesso à conversa do colega, e exigir ser do
  # time da conversa para poder pedi-la fecha a porta e joga a chave dentro. A aba "Em atendimento"
  # mostra a conta inteira de propósito; sem este skip, "Solicitar" numa conversa de outro time
  # respondia 403. A ConversationPolicy#show? continua valendo (só peço o que alcanço pela caixa
  # ou pelo time), e quem decide continua sendo o dono, ao aprovar.
  skip_before_action :authorize_team_access
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
