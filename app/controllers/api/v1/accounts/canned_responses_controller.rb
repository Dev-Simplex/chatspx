class Api::V1::Accounts::CannedResponsesController < Api::V1::Accounts::BaseController
  before_action :fetch_canned_response, only: [:update, :destroy]

  def index
    render json: canned_responses.map { |cr| serialize(cr) }
  end

  def create
    @canned_response = Current.account.canned_responses.new(canned_response_params)
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

  def canned_response_params
    params.require(:canned_response).permit(:short_code, :content, attachments: [])
  end

  def serialize(canned)
    canned.as_json(only: %i[id short_code content account_id created_at updated_at]).merge(
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
    if params[:search]
      Current.account.canned_responses
             .where('short_code ILIKE :search OR content ILIKE :search', search: "%#{params[:search]}%")
             .order_by_search(params[:search])

    else
      Current.account.canned_responses
    end
  end
end
