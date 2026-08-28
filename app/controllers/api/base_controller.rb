class Api::BaseController < ApplicationController
  include AccessTokenAuthHelper
  respond_to :json
  before_action :authenticate_access_token!, if: :authenticate_by_access_token?
  before_action :validate_bot_access_token!, if: :authenticate_by_access_token?
  before_action :authenticate_user!, unless: :authenticate_by_access_token?

  private

  def authenticate_by_access_token?
    request.headers[:api_access_token].present? || request.headers[:HTTP_API_ACCESS_TOKEN].present?
  end

  def check_authorization(model = nil)
    model ||= controller_name.classify.constantize

    authorize(model)
  end

  def check_admin_authorization?
    raise Pundit::NotAuthorizedError unless Current.account_user.administrator?
  end

  # Nega ao SUPERVISOR de time as configurações de plataforma (SupervisorSettingsScope).
  # Para controllers que não passam por policy nenhuma — `check_admin_authorization?`
  # não consulta Pundit, então a negação tem que morar aqui, e não numa policy que
  # ninguém chama. Onde existe policy, use `supervisor_settings_blocked?` lá.
  def check_platform_settings_authorization?
    raise Pundit::NotAuthorizedError if SupervisorSettingsScope.blocked?(Current.user, Current.account)
  end

  # Mesma negação, mas para os pontos que já exigiam administrador.
  def check_platform_settings_admin_authorization?
    check_admin_authorization?
    check_platform_settings_authorization?
  end
end
