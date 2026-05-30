# Cadência de REATIVAÇÃO de lead frio, fora da janela de 24h, via templates HSM
# (WhatsApp Cloud API). É o complemento do follow-up dirigido pelo agente
# (Captain::Conversation::FollowupJob), que cuida das cutucadas DENTRO da janela:
#
#   dentro de 24h  -> agente decide e compõe a cutucada (texto livre)
#   fora de 24h    -> só HSM aprovado reabre a conversa (esta cadência)
#
# Disparada quando o lead esfria (followup_job atinge MAX, ou salvar_info_lead
# marca esfriado/perdido). Só age em inbox Cloud API — em WAHA (PAULAO) é no-op,
# pois WAHA não tem HSM. Idempotente: não reagenda se já houver cadência pendente.
# Cancelada quando o lead responde (FunnelAutomationListener#message_created).
module Spx
  module Tozi
    class ReactivationCadenceService
      LANGUAGE = 'pt_BR'.freeze

      # offset após esfriar | template HSM aprovado no WABA | preview salvo na transcrição.
      # Os nomes/variáveis precisam casar com os templates aprovados (reconciliar via
      # `rake spx:tozi:create_templates` / Graph API antes de habilitar em prod).
      CADENCE = [
        { offset: 1.day,  template: 'tozi_lead_followup',
          preview: 'Oi %<nome>s, ainda procurando imóvel? Quando quiser retomar, estou por aqui pra ajudar. 🏡' },
        { offset: 3.days, template: 'tozi_lead_reativacao',
          preview: 'Oi %<nome>s! Apareceram novos imóveis em %<ref>s que podem combinar com o que você procurava. Quer que eu te mande?' },
        { offset: 7.days, template: 'tozi_lead_reativacao',
          preview: 'Oi %<nome>s! Ainda dá tempo de achar o imóvel certo. Posso te mostrar as novidades de %<ref>s?' }
      ].freeze

      DEFAULT_REFERENCE = 'Sinop'.freeze

      # Cancela a cadência HSM pendente de uma conversa (lead respondeu).
      def self.cancel_pending(conversation)
        return unless ScheduledMessage.column_names.include?('template_params')

        ScheduledMessage.pending
                        .where(conversation_id: conversation.id)
                        .where.not(template_params: nil)
                        .update_all(status: ScheduledMessage.statuses[:cancelled], updated_at: Time.current)
      end

      def initialize(conversation:)
        @conversation = conversation
        @inbox = conversation.inbox
      end

      def perform
        # Feature inerte até a migration 20260529120000 rodar: sem a coluna não há
        # como carregar template_params nem deduplicar/cancelar -> no-op limpo.
        return unless ScheduledMessage.column_names.include?('template_params')
        return unless cloud_api_inbox?
        return if cadence_already_scheduled?

        user = system_user
        return if user.nil?

        CADENCE.each { |step| schedule_step(step, user) }
      rescue StandardError => e
        Rails.logger.error("Spx::Tozi::ReactivationCadenceService conv=#{@conversation&.id}: #{e.message}")
        nil
      end

      private

      # Só Cloud API oficial tem HSM. WAHA (Channel::Api) não — vira no-op.
      def cloud_api_inbox?
        @inbox.channel_type == 'Channel::Whatsapp' &&
          @inbox.channel&.provider_config&.dig('business_account_id').present?
      end

      def cadence_already_scheduled?
        return false unless ScheduledMessage.column_names.include?('template_params')

        ScheduledMessage.pending
                        .where(conversation_id: @conversation.id)
                        .where.not(template_params: nil)
                        .exists?
      end

      def schedule_step(step, user)
        ScheduledMessages::CreateService.new(
          conversation: @conversation,
          inbox: @inbox,
          message: format(step[:preview], nome: first_name, ref: product_reference),
          scheduled_at: step[:offset].from_now,
          user: user,
          template_params: template_params(step)
        ).perform
      end

      # Shape lido por Whatsapp::TemplateProcessorService: name + language + processed_params.body.
      # {{1}}=nome em todos; {{2}}=referência apenas no tozi_lead_reativacao.
      def template_params(step)
        body = { '1' => first_name }
        body['2'] = product_reference if step[:template] == 'tozi_lead_reativacao'
        { 'name' => step[:template], 'language' => LANGUAGE, 'processed_params' => { 'body' => body } }
      end

      def first_name
        (@conversation.contact&.name.presence || 'tudo bem').to_s.split.first
      end

      def product_reference
        @conversation.contact&.additional_attributes&.dig('city').presence || DEFAULT_REFERENCE
      end

      def system_user
        @conversation.account.administrators.first
      end
    end
  end
end
