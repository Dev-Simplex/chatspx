class SwaggerController < ApplicationController
  before_action :authenticate_docs!

  def respond
    render inline: Rails.root.join('swagger', derived_path).read
  end

  private

  # Doc da API (ReDoc) protegida por HTTP Basic Auth em producao.
  # Habilita apenas quando SWAGGER_DOCS_PASSWORD esta definida; sem ela, 404 (padrao seguro upstream).
  def authenticate_docs!
    return if Rails.env.development? || Rails.env.test?

    expected_pass = ENV.fetch('SWAGGER_DOCS_PASSWORD', nil)
    return head(:not_found) if expected_pass.blank?

    expected_user = ENV.fetch('SWAGGER_DOCS_USER', 'spxdocs')
    authenticate_or_request_with_http_basic('ChatSPX API Docs') do |user, pass|
      next false if user.blank? || pass.blank?

      ActiveSupport::SecurityUtils.secure_compare(user, expected_user) &
        ActiveSupport::SecurityUtils.secure_compare(pass, expected_pass)
    end
  end

  def derived_path
    params[:path] ||= 'index.html'
    path = Rack::Utils.clean_path_info(params[:path])
    path << ".#{Rack::Utils.clean_path_info(params[:format])}" unless path.ends_with?(params[:format].to_s)
    path
  end
end
