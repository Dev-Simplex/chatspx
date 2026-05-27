# Recebe lead enriquecido + hook, cria Contact (ou reutiliza) na inbox alvo,
# abre Conversation em status pending (Captain dispara) e envia 1a mensagem
# outgoing renderizada a partir do template Liquid do hook.
#
# Flag de teste: `settings.skip_initial_message = true` cria a conversa mas
# NÃO envia a 1ª mensagem outgoing. Útil enquanto valida o fluxo sem
# incomodar leads reais.
module Meta
  module LeadAds
    class CreateConversationService
      DEFAULT_TEMPLATE = "Olá {{first_name}}! Vi seu interesse no anúncio \"{{ad_name}}\". Sou da equipe e estou aqui pra ajudar. Pode me contar um pouco mais sobre o que você procura?".freeze

      def initialize(hook:, lead:)
        @hook = hook
        @lead = lead
        @inbox = Inbox.find(hook.settings['target_inbox_id'])
      end

      def perform
        normalized_phone = @lead[:phone_number].present? ? normalize_phone(@lead[:phone_number]) : nil

        if normalized_phone.blank?
          Rails.logger.warn("Meta Lead Ads: lead sem phone_number hook=#{@hook.id} leadgen=#{@lead[:leadgen_id]} form=#{@lead[:form_id]} — criando conversa mesmo assim, sem envio de 1a mensagem")
        end

        contact_inbox = build_contact_inbox(normalized_phone)
        conversation = create_conversation(contact_inbox)

        if normalized_phone.blank?
          # Sem phone nao da pra mandar via WAHA — anota e pula 1a msg
          Rails.logger.info("Meta Lead Ads: hook=#{@hook.id} conversation=#{conversation.id} — sem phone, sem 1a mensagem (lead exige follow-up manual)")
        elsif skip_initial_message?
          Rails.logger.info("Meta Lead Ads: skip_initial_message=true hook=#{@hook.id} conversation=#{conversation.id} — conversa criada sem 1a mensagem")
        else
          create_initial_message(conversation)
        end

        conversation
      end

      private

      def skip_initial_message?
        ActiveModel::Type::Boolean.new.cast(@hook.settings['skip_initial_message'])
      end

      def normalize_phone(phone)
        digits = phone.to_s.gsub(/\D/, '')
        return nil if digits.blank?

        digits = "55#{digits}" if digits.length.between?(10, 11)
        formatted = "+#{digits}"
        Contacts::BrazilPhoneNormalizer.normalize(formatted) || formatted
      end

      def build_contact_inbox(normalized_phone)
        ContactInboxWithContactBuilder.new(
          inbox: @inbox,
          contact_attributes: {
            name: contact_name(normalized_phone),
            phone_number: normalized_phone,
            email: @lead[:email],
            additional_attributes: {
              source: 'meta_lead_ads',
              leadgen_id: @lead[:leadgen_id],
              ad_id: @lead[:ad_id],
              ad_name: @lead[:ad_name],
              adset_id: @lead[:adset_id],
              adset_name: @lead[:adset_name],
              campaign_id: @lead[:campaign_id],
              campaign_name: @lead[:campaign_name],
              form_id: @lead[:form_id],
              platform: @lead[:platform],
              city: @lead[:city]
            }.compact
          },
          source_id: source_id_for(normalized_phone)
        ).perform
      end

      def contact_name(normalized_phone)
        return @lead[:full_name] if @lead[:full_name].present?
        return "Lead Meta #{normalized_phone}" if normalized_phone.present?
        return "Lead Meta #{@lead[:email]}" if @lead[:email].present?

        "Lead Meta #{@lead[:leadgen_id]}"
      end

      def source_id_for(phone)
        # WAHA inbox usa JID `<digits>@c.us` como source_id (quando ha phone)
        if phone.present? && @inbox.channel_type == 'Channel::Api' && @inbox.respond_to?(:waha_session_name) && @inbox.waha_session_name.present?
          digits = phone.to_s.gsub(/\D/, '')
          return "#{digits}@c.us"
        end

        # Sem phone: fallback unico por leadgen_id (evita duplicidade e nao colide com outros contatos)
        return "meta_lead:#{@lead[:leadgen_id]}" if phone.blank?

        phone
      end

      def create_conversation(contact_inbox)
        Conversation.create!(
          account_id: @inbox.account_id,
          inbox_id: @inbox.id,
          contact_id: contact_inbox.contact_id,
          contact_inbox_id: contact_inbox.id,
          status: conversation_status,
          additional_attributes: {
            source: 'meta_lead_ads',
            lead: @lead.slice(:leadgen_id, :ad_name, :campaign_name, :form_id, :platform).compact
          }
        )
      end

      def conversation_status
        @inbox.pending_status_enabled? ? 'pending' : 'open'
      end

      def create_initial_message(conversation)
        rendered = render_template
        return if rendered.blank?

        Messages::MessageBuilder.new(
          nil,
          conversation,
          content: rendered,
          message_type: 'outgoing',
          private: false,
          content_attributes: { meta_lead_ads_initial: true }
        ).perform
      end

      def render_template
        template = @hook.settings['initial_message_template'].presence || DEFAULT_TEMPLATE

        Liquid::Template.parse(template).render(
          'full_name' => @lead[:full_name].to_s,
          'first_name' => @lead[:full_name].to_s.split.first.to_s,
          'ad_name' => @lead[:ad_name].to_s,
          'campaign_name' => @lead[:campaign_name].to_s,
          'city' => @lead[:city].to_s,
          'email' => @lead[:email].to_s,
          'phone' => @lead[:phone_number].to_s
        )
      end
    end
  end
end
