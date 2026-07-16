# State machine do funil de pré-venda Tozi (Bloco 3): move cards por evento.
# No-op pra contas sem o funil de pré-venda (FunnelPlacementService.current_type
# retorna nil), então não afeta outros tenants.
#
# IMPORTANTE: os handlers rodam pra TODA conta da instância via AsyncDispatcher.
# Qualquer exceção aqui propagaria pro EventDispatcherJob (fila :critical) e
# derrubaria listeners seguintes + retries. Por isso cada handler é rescue-wrapped.
#
# Transições cobertas aqui (event-driven):
#   incoming do lead em espera/frio -> "Em Conversa" (+ cancela cadência HSM)
#   handoff pra humano               -> "Qualificado" (+ cancela cadência HSM)
# As transições "Em Silêncio"/"Frio"/"Qualificado(status)" são disparadas pelas
# tools do Captain (programar_followup / followup_job / salvar_info_lead).
module Spx
  module Tozi
    class FunnelAutomationListener < BaseListener
      # Estágios onde o lead está "parado" e um incoming dele deve reativar a conversa.
      WAITING_STAGES = %w[novo_lead aguardando_1a em_silencio frio].freeze
      # Estágios de pré-venda ativa de onde um handoff pra humano vira "qualificado".
      PRE_QUALIFIED_STAGES = %w[novo_lead aguardando_1a em_conversa em_silencio agendado frio].freeze
      # Cloud API: "número não tem WhatsApp" — a abertura HSM nunca chega. NÃO dá pra
      # pré-validar (o endpoint /contacts da API on-premise foi desligado pela Meta), então
      # reagimos ao status failed: marca e joga pro humano do time como lista de LIGAÇÃO.
      NO_WHATSAPP_ERROR_CODES = %w[131026 131030].freeze
      NO_WHATSAPP_LABEL = 'sem-whatsapp'.freeze
      # Meta não entregou a abertura mas o número está OK: 131049 (segurou por qualidade/engajamento)
      # e 130472 (número em experimento da Meta que bloqueia MARKETING). Vira follow-up humano.
      DELIVERY_BLOCKED_CODES = %w[131049 130472].freeze
      DELIVERY_BLOCKED_LABEL = 'entrega-segurada'.freeze
      # Erros de CONTA (não do lead): conta bloqueada, pagamento, spam-pause — pedem atenção de ops.
      ACCOUNT_CRITICAL_CODES = %w[131031 131042 131048].freeze

      # Lead respondeu: cancela a cadência de reativação pendente e traz o card de
      # volta pra "Em Conversa" (só se estava num estágio de espera/frio).
      def message_created(event)
        message, _account = extract_message_and_account(event)
        return if message.activity?
        return unless message.incoming?

        conversation = message.conversation
        return if conversation.nil?
        return unless WAITING_STAGES.include?(Spx::Tozi::FunnelPlacementService.current_type(conversation))

        Spx::Tozi::ReactivationCadenceService.cancel_pending(conversation)
        Spx::Tozi::FunnelPlacementService.move(conversation: conversation, to: 'em_conversa')
      rescue StandardError => e
        Rails.logger.error("[Spx::Tozi::FunnelAutomationListener] message_created conv=#{conversation&.id}: #{e.message}")
      end

      # Handoff pra humano (atribuído a um User real, sem agent_bot dono): "Qualificado".
      # Só promove se ainda estava em pré-venda ativa, pra não sobrescrever card movido
      # à mão nem re-afirmar em reatribuição agente->agente.
      def assignee_changed(event)
        conversation, _account = extract_conversation_and_account(event)
        return if conversation.nil?
        return unless conversation.assignee_id.present? && conversation.assignee_agent_bot_id.blank?
        return unless PRE_QUALIFIED_STAGES.include?(Spx::Tozi::FunnelPlacementService.current_type(conversation))

        Spx::Tozi::ReactivationCadenceService.cancel_pending(conversation)
        Spx::Tozi::FunnelPlacementService.move(conversation: conversation, to: 'qualificado')
      rescue StandardError => e
        Rails.logger.error("[Spx::Tozi::FunnelAutomationListener] assignee_changed conv=#{conversation&.id}: #{e.message}")
      end

      # Abertura HSM de lead Meta falhou: trata a família de erros da Meta. Só age em conversa
      # de lead Meta. Sem WhatsApp (131026/131030) e Meta-segurou (131049) tiram o lead do fluxo
      # da IA e jogam pro humano do time como follow-up; erros de CONTA (bloqueio/pagamento/spam)
      # só logam crítico (não são problema do lead). Idempotente por label.
      def message_updated(event)
        message, _account = extract_message_and_account(event)
        return if message.nil? || message.status != 'failed'

        conversation = message.conversation
        return if conversation.nil?
        return unless conversation.additional_attributes.is_a?(Hash) && conversation.additional_attributes['source'] == 'meta_lead_ads'

        error = message.external_error.to_s
        if NO_WHATSAPP_ERROR_CODES.any? { |c| error.include?(c) }
          flag_for_human(conversation, error, NO_WHATSAPP_LABEL, 'Número provavelmente sem WhatsApp — fazer follow-up por ligação.')
        elsif DELIVERY_BLOCKED_CODES.any? { |c| error.include?(c) }
          flag_for_human(conversation, error, DELIVERY_BLOCKED_LABEL, 'A Meta não entregou a abertura (número em experimento/qualidade da Meta). O número está OK — fazer follow-up por ligação.')
        elsif ACCOUNT_CRITICAL_CODES.any? { |c| error.include?(c) }
          Rails.logger.error("[Spx::Tozi] META LEAD ADS ERRO CRITICO DE CONTA (#{error}) conv=#{conversation.id} — verificar Business Manager (bloqueio/pagamento/spam).")
        end
      rescue StandardError => e
        Rails.logger.error("[Spx::Tozi::FunnelAutomationListener] message_updated conv=#{message&.conversation_id}: #{e.message}")
      end

      private

      # Tira o lead do fluxo da IA (que não tem como mandar nada), marca com a label e joga pro
      # humano do time (Cibele) como follow-up. Idempotente por label.
      def flag_for_human(conversation, error, label, note)
        return if conversation.label_list.include?(label)

        conversation.add_labels((conversation.label_list + [label]).uniq)
        human = meta_team_assignee(conversation)
        Conversations::AssignmentService.new(conversation: conversation, assignee_id: human.id).perform if human
        begin
          conversation.messages.create!(
            account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :activity,
            content: "Abertura não entregue (#{error}). #{note}"
          )
        rescue StandardError => e
          Rails.logger.warn("[Spx::Tozi::FunnelAutomationListener] nota #{label} conv=#{conversation.id}: #{e.message}")
        end
      end

      # Humano do time do lead (ex.: Cibele no time "Leads Meta"). Assignee humano remove o bot.
      def meta_team_assignee(conversation)
        team = conversation.team || Team.where(account_id: conversation.account_id).find_by('LOWER(name) = ?', 'leads meta')
        team&.team_members&.first&.user
      end
    end
  end
end
