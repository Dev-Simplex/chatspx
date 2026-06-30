# Leitura da baseline viva de um assistant (Spx::AiConfig::ConfigReader.export).
# E o estado que o Almirante usa pra montar/renderizar o diff antes de aprovar.
module Spx
  module AiConfig
    class ConfigController < BaseController
      def baseline
        export = Spx::AiConfig::ConfigReader.export(
          account_id: params[:account_id],
          assistant_id: params[:assistant_id]
        )
        render json: export
      end
    end
  end
end
