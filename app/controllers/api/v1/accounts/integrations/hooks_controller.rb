class Api::V1::Accounts::Integrations::HooksController < Api::V1::Accounts::BaseController
  before_action :fetch_hook, except: [:create]
  before_action :check_authorization

  def create
    @hook = Current.account.hooks.create!(permitted_params)
  end

  def update
    attributes = permitted_params.slice(:status, :settings)
    @hook.with_lock do
      preserve_captador_secret(attributes)
      @hook.update!(attributes)
    end
  end

  def process_event
    return captador_health if @hook.app_id == 'captador' && params[:event] == 'health'

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

  def captador_health
    authorize(:hook, :update?)
    state = @hook.captador_inbox_state.merge(account_id: Current.account.id)
    return render json: state.merge(status: 'disabled') unless @hook.enabled? && Current.account.captador_integration_enabled?

    response = Spx::Captador::Client.new(@hook, Current.user).health
    render json: state.merge(status: captador_health_status(response, state))
  rescue Spx::Captador::Client::Unavailable
    render json: state.merge(status: 'unavailable')
  end

  def captador_health_status(response, state)
    if response.status == 200 && captador_health_identity?(response.body)
      state[:unavailable_inbox_ids].any? || state[:effective_inboxes].empty? ? 'degraded' : 'ok'
    elsif response.status == 401
      'authentication_failed'
    elsif response.status == 404
      'onboarding_required'
    else
      'unavailable'
    end
  end

  def captador_health_identity?(body)
    body.is_a?(Hash) && body['account_id'] == Current.account.id && body['instance_key'] == @hook.settings['instance_key']
  end

  def fetch_hook
    @hook = Current.account.hooks.find(params[:id])
  end

  def check_authorization
    authorize(:hook)
  end

  def permitted_params
    attributes = params.require(:hook).permit(:app_id, :inbox_id, :status, settings: {})
    if (@hook&.app_id || attributes[:app_id]) == 'captador' &&
       attributes.dig(:settings, :shared_secret).to_s.start_with?(Integrations::Hook::CAPTADOR_SECRET_PREFIX)
      raise ActionController::BadRequest
    end

    attributes
  end

  def preserve_captador_secret(attributes)
    submitted = attributes[:settings]
    return unless @hook.app_id == 'captador' && submitted

    submitted = submitted.to_h.except('shared_secret_configured')
    submitted.delete('shared_secret') if submitted['shared_secret'].blank?
    attributes[:settings] = @hook.settings.merge(submitted)
  end
end
