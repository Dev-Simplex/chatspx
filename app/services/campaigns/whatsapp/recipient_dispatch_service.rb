module Campaigns
  module Whatsapp
    # Engine de disparo de UM destinatario (generica, multi-conta). Espelha o
    # comportamento provado do Spx::Tozi::DisparoLeadJob, mas dirigido pela
    # Campaign em vez de constantes hardcoded:
    #
    #   * cria/reusa o contato + a conversa (reconcilia o 9o digito da ficha),
    #   * envia o HSM aprovado com os params do destinatario,
    #   * seta o TIME da campanha e DEIXA A CONVERSA FECHADA E SEM AGENTE.
    #
    # O reply do lead reabre a conversa; a atribuicao (IA do time, ou regras
    # normais de atribuicao ao abrir) acontece na camada de orquestracao — fora
    # do escopo desta engine.
    #
    # Best-effort: qualquer falha marca o recipient como :failed e nao derruba o
    # lote (o scheduler segue com os proximos).
    class RecipientDispatchService
      pattr_initialize [:recipient!]

      def perform
        # So despacha quem foi reivindicado pelo scheduler (guarda anti-duplicata).
        return false unless recipient.processing?

        inbox = campaign.inbox
        contact_inbox = build_contact_inbox(inbox)

        # Decisao do Paulo: o disparo NAO atropela atendimento ativo. Contato com
        # conversa nao-resolvida (aberta/pending/snoozed) e PULADO (marca skipped).
        if active_conversation?(inbox, contact_inbox.contact_id)
          recipient.update!(status: :skipped, contact_id: contact_inbox.contact_id,
                            external_error: 'contato em atendimento ativo')
          return false
        end

        conversation = find_or_create_conversation(inbox, contact_inbox)
        send_hsm(conversation)
        close_with_team(conversation)

        recipient.update!(
          status: :sent, conversation_id: conversation.id, contact_id: contact_inbox.contact_id,
          sent_at: Time.current, external_error: nil
        )
        true
      rescue StandardError => e
        recipient.update(status: :failed, external_error: "#{e.class}: #{e.message}".first(250))
        Rails.logger.error("[CampaignDispatch] campaign=#{campaign.id} phone=#{recipient.phone_number} #{e.class}: #{e.message}")
        false
      end

      private

      delegate :campaign, to: :recipient

      def build_contact_inbox(inbox)
        ContactInboxWithContactBuilder.new(
          inbox: inbox,
          contact_attributes: {
            # Sem nome na lista, o contato fica SEM NOME — o painel identifica pelo telefone
            # e quem descobre o nome é a conversa (a IA ou o atendente pergunta e confirma).
            # Nada de fallback aqui: `contact.name` é área de trabalho do time humano (eles
            # anotam "Fulano / Casa do Beltrano"), então fabricar um nome escreve lixo num
            # campo de trabalho. Foi assim que 110 contatos viraram "tudo bem".
            # String VAZIA, nunca nil: o builder faz `name || Haikunator.haikunate`, então
            # nil viraria um apelido aleatório.
            name: recipient.name.to_s.strip,
            phone_number: recipient.phone_number,
            additional_attributes: { source: "campaign_#{campaign.id}" }
          },
          # Reusa a ficha que o WhatsApp ja usa pros replies (variantes 12d/13d do
          # 9o digito) -> nao cria ficha duplicada.
          source_id: resolved_source_id(inbox)
        ).perform
      end

      def resolved_source_id(inbox)
        waid = recipient.phone_number.delete('+')
        ::Whatsapp::PhoneNumberNormalizationService.new(inbox)
                                                   .normalize_and_find_contact_by_provider(waid, :cloud)
      end

      # Atendimento ativo = qualquer conversa nao-resolvida do contato nesta inbox.
      def active_conversation?(inbox, contact_id)
        Conversation.where(inbox_id: inbox.id, contact_id: contact_id)
                    .where.not(status: :resolved).exists?
      end

      # Honra lock_to_single: reusa a conversa do contato (qualquer ficha); cria
      # nova so quando o contato nunca teve uma.
      def find_or_create_conversation(inbox, contact_inbox)
        base = Conversation.where(inbox_id: inbox.id, contact_id: contact_inbox.contact_id)
        conversation = base.where.not(status: :resolved).order(created_at: :desc).first ||
                       base.order(created_at: :desc).first
        return conversation if conversation

        Conversation.create!(
          account_id: inbox.account_id, inbox_id: inbox.id,
          contact_id: contact_inbox.contact_id, contact_inbox_id: contact_inbox.id,
          status: 'open', team_id: campaign.target_team_id, campaign_id: campaign.id,
          additional_attributes: { source: "campaign_#{campaign.id}" }
        )
      end

      def send_hsm(conversation)
        ::Whatsapp::SendTemplateService.new(
          conversation: conversation,
          name: campaign.template_name,
          language: campaign.template_language,
          body_params: default_params.merge(stringify(recipient.template_params)),
          header: campaign.dispatch_config['header']
        ).perform
      end

      # Modelo de atribuicao (decisao do Paulo): seta o TIME e FECHA, sem agente.
      # O reply reabre e a atribuicao (IA do time / regras normais) decide depois.
      def close_with_team(conversation)
        attrs = { status: :resolved }
        attrs[:team_id] = campaign.target_team_id if campaign.target_team_id.present?
        attrs[:campaign_id] = campaign.id if conversation.campaign_id.nil?
        conversation.update!(attrs)
        # Limpa o agente num update SEPARADO: com team_id ja setado (nao muda agora),
        # o callback ensure_assignee_is_from_team nao re-atribui do time — vale mesmo
        # quando o time tem allow_auto_assign=true.
        conversation.update!(assignee_id: nil) if conversation.assignee_id.present?
      end

      def default_params
        stringify(campaign.dispatch_config['default_params'])
      end

      def stringify(hash)
        (hash || {}).to_h { |k, v| [k.to_s, v.to_s] }
      end
    end
  end
end
