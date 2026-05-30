# Coloca/move uma Conversation no estágio certo do funil de pré-venda Tozi.
#
# Acha o funil que cobre a inbox da conversa E tem um estágio com o
# automation_type pedido (assim só age sobre o funil "Pré-Venda Tozi", não
# os funis genéricos open/resolved). Idempotente: cria FunnelItem ou move o
# existente pro estágio alvo.
#
# Uso:
#   Spx::Tozi::FunnelPlacementService.new(
#     conversation: conv, automation_type: 'novo_lead'
#   ).perform
module Spx
  module Tozi
    class FunnelPlacementService
      # automation_types do funil "Pré-Venda Tozi" (ver lib/tasks/spx_tozi.rake).
      PREVENDA_AUTOMATION_TYPES = %w[novo_lead aguardando_1a em_conversa em_silencio agendado qualificado frio].freeze

      # Move o card pra `to`. Idempotente e seguro: no-op se a inbox não for
      # coberta pelo funil de pré-venda (FunnelPlacementService#perform filtra).
      # Os guards de "de onde mover" ficam no chamador (ex.: FunnelAutomationListener
      # gateia via current_type).
      def self.move(conversation:, to:)
        new(conversation: conversation, automation_type: to).perform
      end

      # automation_type atual da conversa no funil de pré-venda, ou nil.
      def self.current_type(conversation)
        funnel = prevenda_funnel(conversation)
        return if funnel.nil?

        conversation.funnel_items.find_by(funnel_id: funnel.id)&.funnel_stage&.automation_type
      end

      # Funil de pré-venda que cobre a inbox da conversa (casa por qualquer stage do funil).
      def self.prevenda_funnel(conversation)
        conversation.account.funnels
                    .for_inbox(conversation.inbox_id)
                    .joins(:funnel_stages)
                    .where(funnel_stages: { automation_type: PREVENDA_AUTOMATION_TYPES })
                    .distinct.first
      end

      def initialize(conversation:, automation_type:)
        @conversation = conversation
        @automation_type = automation_type.to_s
      end

      def perform
        funnel = find_funnel
        return if funnel.nil?

        stage = funnel.funnel_stages.with_automation(@automation_type).first
        return if stage.nil?

        item = FunnelItem.find_or_initialize_by(conversation_id: @conversation.id, funnel_id: funnel.id)
        return item if item.persisted? && item.funnel_stage_id == stage.id

        item.funnel_stage_id = stage.id
        item.save!
        item
      rescue StandardError => e
        Rails.logger.error("Spx::Tozi::FunnelPlacementService error conv=#{@conversation&.id} type=#{@automation_type}: #{e.message}")
        nil
      end

      private

      # Funil de pré-venda: cobre a inbox da conversa e possui o estágio alvo.
      # O filtro por automation_type garante que NÃO peguemos funis genéricos
      # (Geral/vendas/etc. só têm open/resolved).
      def find_funnel
        @conversation.account.funnels
                     .for_inbox(@conversation.inbox_id)
                     .joins(:funnel_stages)
                     .where(funnel_stages: { automation_type: @automation_type })
                     .first
      end
    end
  end
end
