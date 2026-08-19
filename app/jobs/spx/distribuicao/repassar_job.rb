# Repassa UMA designação vencida. Um job por linha, e não um laço dentro do varredor, para que
# uma conversa problemática (Vista fora do ar, atribuição que falha) não derrube o repasse das
# outras — e para que o retry do Sidekiq seja por lead, não por lote.
module Spx
  module Distribuicao
    class RepassarJob < ApplicationJob
      queue_as :low

      def perform(log_id)
        log = Log.find_by(id: log_id)
        return if log.nil?

        resultado = RepasseService.new(log).call
        return unless resultado.repassou

        Rails.logger.info(
          "[Distribuicao::Repasse] log=#{log.id} conv=#{log.conversation_id} " \
          "motivo=#{resultado.motivo} destino=#{resultado.destino}"
        )
      end
    end
  end
end
