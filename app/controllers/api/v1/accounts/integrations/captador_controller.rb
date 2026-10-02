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

  LEAD_KEYS = %w[lead empresa etapas url pode_mover].freeze
  PROBLEM_KEYS = %w[codigo title detail].freeze
  BUSINESS_ERRORS = [400, 403, 404, 409, 422].freeze

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

  # Do Captador só passa JSON, e só os campos que o painel usa: o 200 com o lead e os 4xx de negócio
  # (403 acesso_pendente, 404, 409, 422), que o painel sabe mostrar. O resto vira o mesmo 502 de
  # queda e timeout: 401 (segredo trocado de um lado só), 3xx, 5xx e corpo que não é JSON.
  def relay
    response = yield
    body = response.body.is_a?(Hash) ? response.body : nil
    if response.status == 200 && body
      render json: lead_payload(body)
    elsif BUSINESS_ERRORS.include?(response.status)
      render json: body.to_h.slice(*PROBLEM_KEYS), status: response.status
    else
      render_unavailable
    end
  rescue Spx::Captador::Client::Unavailable => e
    Rails.logger.warn("[Captador] painel sem resposta conta=#{Current.account.id}: #{e.message}")
    render_unavailable
  end

  # O "Abrir no Captador" vira href no painel: só https.
  def lead_payload(body)
    payload = body.slice(*LEAD_KEYS)
    payload['url'] = nil if payload.key?('url') && !payload['url'].to_s.start_with?('https://')
    payload
  end

  def render_unavailable
    render json: { error_code: 'captador_unavailable' }, status: :bad_gateway
  end
end
