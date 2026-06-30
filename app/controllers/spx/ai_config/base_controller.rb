# Base dos endpoints REST do receptor de change-sets de IA (control plane Almirante).
# Auth maquina-a-maquina: header `api_access_token` cujo owner e um PlatformApp
# (mesmo padrao do PlatformController). Mapeia os erros de dominio do applier pra HTTP.
module Spx
  module AiConfig
    class BaseController < ActionController::API
      before_action :authenticate_almiral!

      rescue_from Spx::AiConfig::ChangeSetApplier::InvalidChangeSet, with: :render_unprocessable
      rescue_from Spx::AiConfig::ChangeSetApplier::UnsupportedOperation, with: :render_unprocessable
      rescue_from Spx::AiConfig::ChangeSetApplier::TenantViolation, with: :render_forbidden
      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

      private

      def authenticate_almiral!
        token = request.headers['api_access_token'] || request.headers['HTTP_API_ACCESS_TOKEN']
        access_token = AccessToken.find_by(token: token) if token.present?
        @platform_app = access_token.owner if access_token && access_token.owner.is_a?(PlatformApp)
        return if @platform_app.present?

        render json: { error: 'Invalid access_token' }, status: :unauthorized
      end

      def render_unprocessable(error)
        render json: { error: error.message, type: error.class.name.demodulize }, status: :unprocessable_entity
      end

      def render_forbidden(error)
        render json: { error: error.message, type: error.class.name.demodulize }, status: :forbidden
      end

      def render_not_found(error)
        render json: { error: error.message, type: 'RecordNotFound' }, status: :not_found
      end
    end
  end
end
