class Api::V1::Accounts::Integrations::HooksController < Api::V1::Accounts::BaseController
  before_action :fetch_hook, except: [:create]
  before_action :check_authorization

  def create
    @hook = Current.account.hooks.create!(permitted_params)
  end

  def update
    attributes = permitted_params.slice(:status, :settings)
    preserve_captador_secret(attributes)
    @hook.update!(attributes)
  end

  def process_event
    response = @hook.process_event(params[:event])

    # for cases like an invalid event, or when conversation does not have enough messages
    # for a label suggestion, the response is nil
    if response.nil?
      render json: { message: nil }
    elsif response[:error]
      render json: { error: response[:error] }, status: :unprocessable_entity
    else
      render json: { message: response[:message] }
    end
  end

  def destroy
    @hook.destroy!
    head :ok
  end

  private

  def fetch_hook
    @hook = Current.account.hooks.find(params[:id])
  end

  def check_authorization
    authorize(:hook)
  end

  def permitted_params
    params.require(:hook).permit(:app_id, :inbox_id, :status, settings: {})
  end

  def preserve_captador_secret(attributes)
    submitted = attributes[:settings]
    return unless @hook.app_id == 'captador' && submitted && submitted[:shared_secret].blank?

    attributes[:settings] = @hook.settings.merge(submitted.to_h.except('shared_secret', 'shared_secret_configured'))
  end
end
