class Api::V1::Accounts::CannedResponsesController < Api::V1::Accounts::BaseController
  before_action :fetch_canned_response, only: [:update, :destroy]
  before_action :check_authorization, only: [:update, :destroy]
  before_action :validate_team_membership, only: [:create, :update]
  before_action :validate_visibility_change, only: [:update]

  def index
    render json: canned_responses.map { |cr| serialize(cr) }
  end

  def create
    @canned_response = Current.account.canned_responses.new(canned_response_params.merge(created_by: current_user))
    @canned_response.save!
    render json: serialize(@canned_response)
  end

  def update
    # Anexos: se vierem no payload, substituem os atuais; senao preserva os existentes.
    @canned_response.attachments.purge if params.dig(:canned_response, :attachments).present?
    @canned_response.update!(canned_response_params)
    render json: serialize(@canned_response)
  end

  def destroy
    @canned_response.destroy!
    head :ok
  end

  private

  def fetch_canned_response
    @canned_response = Current.account.canned_responses.find(params[:id])
  end

  # Instância, NÃO a classe — senão a policy quebra ao ler @record.created_by_id.
  def check_authorization
    authorize(@canned_response)
  end

  # Só membros do time (ou admin) criam/editam resposta de-time. Lê o valor EFETIVO
  # (params têm prioridade; update parcial cai no valor atual do @canned_response).
  def validate_team_membership
    return unless effective_visibility.to_s == 'team'
    return if Current.account_user.administrator?

    head :forbidden unless Current.user.teams.exists?(id: effective_team_id)
  end

  # Modelo permissivo deixa QUALQUER gestor editar o CONTEÚDO de uma resposta compartilhada
  # (pública p/ qualquer agente; de-time p/ qualquer membro). Mas ESTREITAR a audiência dela —
  # tirar do everyone, ou puxar uma de-time para privada — só autor/admin pode. Senão um não-autor
  # "sequestraria" a resposta compartilhada, sumindo com ela do catálogo dos outros. Alargar a
  # audiência (de-time → pública) segue livre. Legada órfã (sem autor) → só admin re-escopa.
  def validate_visibility_change
    return if Current.account_user.administrator?
    return unless narrowing_shared_response?

    head :forbidden unless @canned_response.created_by_id == Current.user.id
  end

  def narrowing_shared_response?
    new_visibility = params.dig(:canned_response, :visibility)
    return false if new_visibility.blank?

    new_visibility = new_visibility.to_s
    if @canned_response.visibility_everyone?
      new_visibility != 'everyone'   # sair do catálogo global (→ privada ou de-time)
    elsif @canned_response.visibility_team?
      new_visibility == 'personal'   # sair do time para uma resposta privada
    else
      false                          # privada já é gerenciável só pelo autor (via manage?)
    end
  end

  def effective_visibility
    params.dig(:canned_response, :visibility) || @canned_response&.visibility
  end

  def effective_team_id
    params.dig(:canned_response, :team_id) || @canned_response&.team_id
  end

  def canned_response_params
    params.require(:canned_response).permit(:short_code, :content, :visibility, :team_id, attachments: [])
  end

  def serialize(canned)
    canned.as_json(only: %i[id short_code content account_id visibility team_id created_at updated_at]).merge(
      'created_by' => (canned.created_by && { 'id' => canned.created_by.id, 'name' => canned.created_by.name }),
      'attachments' => canned.attachments.map do |att|
        {
          'id' => att.id,
          'filename' => att.filename.to_s,
          'file_type' => att.content_type,
          'file_url' => url_for(att)
        }
      end
    )
  end

  def canned_responses
    scope = if params[:search]
              Current.account.canned_responses
                     .where('short_code ILIKE :search OR content ILIKE :search', search: "%#{params[:search]}%")
                     .order_by_search(params[:search])
            else
              Current.account.canned_responses
            end
    # Este index também alimenta o picker "/" (a cada tecla), então evita N+1 de autor/anexos.
    CannedResponse.with_visibility(current_user, scope).with_attached_attachments.includes(:created_by)
  end
end
