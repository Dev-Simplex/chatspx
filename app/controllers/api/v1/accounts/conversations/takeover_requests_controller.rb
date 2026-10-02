# Criar o pedido: pendurado no Conversations::BaseController de propósito — herda a busca da
# conversa e o check de autorização; os guards de acesso é que são afrouxados aqui.
class Api::V1::Accounts::Conversations::TakeoverRequestsController < Api::V1::Accounts::Conversations::BaseController
  # O pedido é justamente COMO se ganha acesso a uma conversa isolada de outro
  # agente — aplicar o guard de isolamento aqui seria galinha-e-ovo (não dá pra
  # pedir o que não se pode acessar).
  skip_before_action :authorize_agent_conversation_access
  # Mesmo argumento para o TIME: pedir é como se ganha acesso à conversa do colega, e exigir ser do
  # time da conversa para poder pedi-la fecha a porta e joga a chave dentro. A aba "Em atendimento"
  # mostra a conta inteira de propósito; sem este skip, "Solicitar" numa conversa de outro time
  # respondia 403.
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

  # EA-01: a busca sai daqui em vez de vir do Conversations::BaseController porque lá ela chama
  # `authorize @conversation, :show?`, que aprova por CAIXA. Com o skip do time mas com o show?
  # de pé, o agente que não participa da caixa via o botão "Solicitar" e levava 403 no clique —
  # justamente o caso que a aba precisa resolver. O escopo continua sendo a conta atual: fora
  # dela, 404. Quem libera o conteúdo continua sendo o dono, ao aprovar; pedir não lê mensagem.
  def conversation
    @conversation ||= Current.account.conversations.find_by!(display_id: params[:conversation_id])
  end

  # Não existe model TakeoverRequest (o model é ConversationTakeoverRequest), e o
  # classify.constantize do Api::BaseController quebraria com NameError.
  def check_authorization
    authorize(ConversationTakeoverRequest.new(account_id: Current.account.id))
  end
end
