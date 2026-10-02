module Campaigns
  module Whatsapp
    # Mantém o `campaign_recipient` em dia com o que acontece DEPOIS do envio. Sem isto o
    # destinatário parava em `sent` e o analítico tinha de adivinhar pela conversa — que guarda
    # a campanha de ORIGEM, então quem recebeu duas campanhas sumia da segunda.
    #
    #   * status da mensagem do template (`delivered`/`read`/`failed`) → o destinatário dela;
    #   * primeira mensagem recebida do contato DEPOIS do `sent_at` → `replied`, atribuída só
    #     ao disparo mais recente antes dela (a resposta é ao último template, não ao primeiro);
    #   * `pricing` do webhook de status da Meta → gravado como veio.
    #
    # O destinatário só avança no funil: webhooks chegam fora de ordem (o `read` pode chegar
    # antes do `delivered`, e o `read` chega depois da resposta), e um evento atrasado não pode
    # desfazer um mais avançado. Os carimbos de tempo, esses, sempre gravam a primeira vez.
    # Escritas por `update_all` condicional: dois jobs do mesmo destinatário não se atropelam.
    # rubocop:disable Rails/SkipsModelValidations
    module RecipientTracker
      FUNNEL = %w[sent delivered read replied].freeze
      STEP_COLUMNS = { 'delivered' => :delivered_at, 'read' => :read_at, 'failed' => :failed_at }.freeze
      PRICING_KEYS = %w[category billable pricing_model type].freeze

      module_function

      def message_status(message, at: Time.current)
        column = STEP_COLUMNS[message.status]
        return if column.nil?

        scope = CampaignRecipient.where(message_id: message.id)
        scope.where(column => nil).update_all(column => at, 'updated_at' => Time.current)
        return advance(scope, message.status) unless message.failed?

        # Falha só vale para quem ainda não andou: a Meta não falha mensagem já entregue.
        scope.where(status: :sent).update_all(status: CampaignRecipient.statuses[:failed], external_error: message.external_error,
                                              updated_at: Time.current)
      end

      def reply(message)
        return unless message.incoming? && !message.private?

        recipient = last_dispatch_before(message)
        return if recipient.nil? || recipient.replied_at.present?

        CampaignRecipient.where(id: recipient.id, replied_at: nil, status: FUNNEL)
                         .update_all(replied_at: message.created_at, status: CampaignRecipient.statuses[:replied],
                                     updated_at: Time.current)
      end

      # `pricing` vem em cada status (`sent`, `delivered`...) com os mesmos campos; o último vence.
      # Ponto de extensão do custo em dinheiro: categoria × tabela de preço por país, que este
      # módulo não tem — não se inventa preço aqui.
      def pricing(message, pricing)
        data = pricing.to_h.stringify_keys.slice(*PRICING_KEYS)
        return if data.empty?

        CampaignRecipient.where(message_id: message.id).update_all(pricing: data, updated_at: Time.current)
      end

      # Disparo mais recente desta caixa para o contato, anterior à mensagem. Pelo CONTATO e não
      # pela conversa: com `lock_to_single_conversation` desligado, a resposta abre conversa nova.
      def last_dispatch_before(message)
        contact_id = message.conversation&.contact_id
        return if contact_id.nil?

        CampaignRecipient.joins(:campaign)
                         .where(contact_id: contact_id, campaigns: { inbox_id: message.inbox_id })
                         .where(sent_at: ...message.created_at)
                         .order(sent_at: :desc).first
      end

      # Destinatário enviado antes deste rastreio existir: acha a mensagem do template na conversa
      # (criada logo antes do `sent_at`) e reaplica o que ela e a conversa já sabem. Idempotente.
      # O carimbo de entregue/lido é o `updated_at` da mensagem, o da última mudança de status.
      def backfill(recipient)
        message = template_message_for(recipient)
        return if message.nil?

        recipient.update_columns(message_id: message.id) if recipient.message_id.nil?
        message_status(message, at: message.updated_at)
        first_reply = Message.joins(:conversation).reorder(:created_at)
                             .where(inbox_id: recipient.campaign.inbox_id, message_type: :incoming, private: false,
                                    conversations: { contact_id: recipient.contact_id })
                             .find_by('messages.created_at > ?', recipient.sent_at)
        reply(first_reply) if first_reply
      end

      def template_message_for(recipient)
        return Message.find_by(id: recipient.message_id) if recipient.message_id
        return if recipient.conversation_id.nil? || recipient.sent_at.nil?

        Message.where(conversation_id: recipient.conversation_id, message_type: :outgoing,
                      created_at: (recipient.sent_at - 5.minutes)..recipient.sent_at)
               .where("additional_attributes -> 'template_params' ->> 'name' = ?", recipient.campaign.template_name)
               .reorder(id: :desc).first
      end

      def advance(scope, status)
        behind = FUNNEL.take(FUNNEL.index(status))
        scope.where(status: behind).update_all(status: CampaignRecipient.statuses[status], updated_at: Time.current)
      end
    end
    # rubocop:enable Rails/SkipsModelValidations
  end
end
