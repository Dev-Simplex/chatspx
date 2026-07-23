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
    end
  end
end
