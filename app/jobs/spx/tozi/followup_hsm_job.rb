# Follow-up de re-engajamento (1 lead). Envia o HSM tozi_followup_lanc DENTRO da
# conversa que ja existe (nao cria nova), reabrindo se estiver resolvida, mantendo
# o corretor ja atribuido. {{1}} = primeiro nome. Best-effort: rescue + log.
module Spx
  module Tozi
    class FollowupHsmJob < ApplicationJob
      queue_as :low

      INBOX_ID = 91
      LANGUAGE = 'pt_BR'.freeze
      TEMPLATE = 'tozi_followup_lanc'.freeze
      PREVIEW = 'Oi %<n>s, mandei uma mensagem essa semana e ainda não tive retorno seu. ' \
                'Tenho um lançamento de até 3 suítes saindo no fim do mês. ' \
                'Oportunidade boa pra moradia ou locação, tem interesse? Se sim, explico em 2 minutos.'

      def perform(conversation_id:, first:, dry_run: false)
        conversation = Conversation.find_by(id: conversation_id, inbox_id: INBOX_ID)
        return Rails.logger.warn("[Followup] conversa #{conversation_id} nao encontrada") if conversation.nil?
        return if dry_run

        conversation.open! unless conversation.open?

        # PREVIEW so entra se o template nao estiver sincronizado no canal; com ele
        # sincronizado, o espelho sai do corpo aprovado (nao pode divergir).
        ::Whatsapp::SendTemplateService.new(
          conversation: conversation, name: TEMPLATE, language: LANGUAGE,
          body_params: { '1' => first }, mirror: format(PREVIEW, n: first)
        ).perform
      rescue StandardError => e
        Rails.logger.error("[Followup] conv=#{conversation_id}: #{e.class}: #{e.message}")
      end
    end
  end
end
