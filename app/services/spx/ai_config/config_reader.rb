# Exporta a config viva de um Captain::Assistant num Hash versionavel/diffavel.
# Read-only — e a BASELINE que o Almirante (control plane) usa pra mostrar o diff
# ao pleno antes de aprovar. Nao toca em nada; so le o banco da VM.
#
# Uso:
#   Spx::AiConfig::ConfigReader.export(account_id: 1, assistant_id: 7)
module Spx
  module AiConfig
    class ConfigReader
      def self.export(account_id:, assistant_id:)
        assistant = Captain::Assistant.find_by!(id: assistant_id, account_id: account_id)
        new(assistant).export
      end

      def initialize(assistant)
        @assistant = assistant
      end

      def export
        {
          account_id: @assistant.account_id,
          assistant_id: @assistant.id,
          name: @assistant.name,
          description: @assistant.description,
          config: @assistant.config,
          behavior: @assistant.behavior,
          faqs: faqs,
          eligibility: eligibility
        }
      end

      private

      def faqs
        @assistant.responses.order(:id).map do |r|
          { id: r.id, question: r.question, answer: r.answer, status: r.status }
        end
      end

      # Inboxes em que o assistant e elegivel pra responder (CaptainInbox).
      def eligibility
        @assistant.captain_inboxes.pluck(:inbox_id)
      end
    end
  end
end
