module Campaigns
  module Whatsapp
    # Materializa a lista enviada (upload) como campaign_recipients pendentes,
    # aplicando as MESMAS regras de higiene do preview (AudienceBuilderService) —
    # a tela nunca mostra uma audiencia e carrega outra.
    #
    # `rows` = enumeravel de hashes { name:, phone:, params: } (chaves string
    # tambem aceitas). Quando `params` vem vazio e ha nome, assume {"1" => nome}
    # (caso comum: corpo do template comeca com "Oi {{1}}").
    #
    # Idempotente: rodar de novo nao reinsere quem ja esta na campanha (o proprio
    # builder descarta como `ja_na_campanha`).
    class ListLoaderService
      pattr_initialize [:campaign!, :rows!, :blocklist_phones]

      # Devolve o Result do builder com `inserted` preenchido — quem chama ve tanto
      # quantos entraram quanto POR QUE os outros ficaram de fora.
      def perform
        result = AudienceBuilderService.new(
          campaign: campaign, rows: rows, blocklist_phones: blocklist_phones
        ).perform

        inserted = result.accepted.count { |entry| insert(entry) }
        result.stats[:inseridos] = inserted
        result
      end

      private

      def insert(entry)
        recipient = campaign.campaign_recipients.find_or_initialize_by(canonical_phone: entry[:canonical])
        return false if recipient.persisted?

        recipient.assign_attributes(
          account_id: campaign.account_id, phone_number: entry[:phone], name: entry[:name],
          template_params: params_for(entry), status: :pending
        )
        recipient.save!
        true
      end

      def params_for(entry)
        explicit = entry[:params]
        return explicit if explicit.present?

        entry[:name].present? ? { '1' => entry[:name] } : {}
      end
    end
  end
end
