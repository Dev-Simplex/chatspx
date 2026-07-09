module Campaigns
  module Whatsapp
    # Materializa a lista enviada (upload) como campaign_recipients pendentes.
    # Normaliza o telefone (BR) e deduplica por numero dentro da campanha
    # (idempotente: rodar de novo nao reinsere quem ja esta na lista).
    #
    # `rows` = enumeravel de hashes { name:, phone:, params: } (chaves string
    # tambem aceitas). Quando `params` vem vazio e ha nome, assume {"1" => nome}
    # (caso comum: corpo do template comeca com "Oi {{1}}").
    class ListLoaderService
      pattr_initialize [:campaign!, :rows!]

      def perform
        inserted = 0
        rows.each do |row|
          phone = normalize(value(row, :phone) || value(row, :telefone))
          next if phone.blank?

          recipient = campaign.campaign_recipients.find_or_initialize_by(phone_number: phone)
          next if recipient.persisted?

          name = value(row, :name).to_s.strip.presence || value(row, :nome).to_s.strip.presence
          recipient.assign_attributes(
            account_id: campaign.account_id, name: name,
            template_params: params_for(row, name), status: :pending
          )
          recipient.save!
          inserted += 1
        end
        inserted
      end

      private

      def params_for(row, name)
        explicit = value(row, :params)
        return explicit if explicit.present?

        name.present? ? { '1' => name } : {}
      end

      def value(row, key)
        row[key] || row[key.to_s]
      end

      def normalize(raw)
        digits = raw.to_s.gsub(/\D/, '')
        return nil if digits.blank?

        digits = "55#{digits}" if digits.length.between?(10, 11)
        formatted = "+#{digits}"
        Contacts::BrazilPhoneNormalizer.normalize(formatted) || formatted
      end
    end
  end
end
