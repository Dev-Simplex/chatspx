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

      # Lista os agentes (Captain::Assistant) de uma conta — o Almirante usa pra
      # montar o seletor de agente (em vez de digitar o assistant_id na mão).
      def assistants
        list = Account.find(params[:account_id]).captain_assistants.order(:id)
        render json: { assistants: list.map { |a| { id: a.id, name: a.name } } }
      end
    end
  end
end
