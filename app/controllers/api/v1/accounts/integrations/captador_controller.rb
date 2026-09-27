# Proxy do painel "Captador" na lateral da conversa (22 §1.3). O navegador só fala com o próprio
# ChatSPX, com a sessão normal: sem iframe, sem CORS e sem cookie de terceiro (o Safari do iPhone
# bloqueia cookie de terceiro por padrão). Quem responde é o Captador, chamado daqui assinado e em
# nome de Current.user (Spx::Captador::Client).
#
# A conversa passa pelas mesmas guardas da API de conversa: policy, time e isolamento por agente.
# O lead vem SEMPRE do que está gravado na conversa ou no contato, nunca do navegador: ninguém move
# um lead que não é o daquela conversa.
class Api::V1::Accounts::Integrations::CaptadorController < Api::V1::Accounts::BaseController
  include ConversationTeamAccessConcern
  include AgentConversationAccessConcern

  before_action :fetch_hook
  before_action :fetch_conversation
  before_action :authorize_team_access
  before_action :authorize_agent_conversation_access

  def lead
    # Conversa comum não gera chamada nenhuma ao Captador.
    return render json: { lead: nil, etapas: [] } if lead_id.blank?

    relay { client.lead(conversation_id: @conversation.display_id, contact_id: @conversation.contact_id) }
  end

  def mover
    return render json: { error_code: 'not_captador_lead' }, status: :unprocessable_entity if lead_id.blank?

    relay { client.move(lead_id, params.require(:etapa_id)) }
  end

  private

  def fetch_hook
    @hook = Current.account.hooks.find_by(app_id: Spx::Captador::BaseController::APP_ID, status: 'enabled')
    render json: { error_code: 'captador_disabled' }, status: :not_found unless @hook && Current.account.captador_integration_enabled?
  end

  def fetch_conversation
    @conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize @conversation, :show?
  end

  def lead_id
    @conversation.custom_attributes&.dig('captador_lead_id').presence ||
      @conversation.contact&.custom_attributes&.dig('captador_lead_id').presence
  end

  def client
    Spx::Captador::Client.new(@hook, Current.user)
  end

  # O que o Captador responde passa como veio, inclusive os 4xx de negócio (403 acesso_pendente,
  # 404, 409, 422), que o painel sabe mostrar. 401 dele é segredo trocado de um lado só: para o
  # atendente é o mesmo que o Captador fora do ar, e vira 502 como queda, timeout e 5xx.
  def relay
    response = yield
    return render_unavailable if response.status == 401 || response.status >= 500

    render json: response.body, status: response.status
  rescue Spx::Captador::Client::Unavailable => e
    Rails.logger.warn("[Captador] painel sem resposta conta=#{Current.account.id}: #{e.message}")
    render_unavailable
  end

  def render_unavailable
    render json: { error_code: 'captador_unavailable' }, status: :bad_gateway
  end
end
