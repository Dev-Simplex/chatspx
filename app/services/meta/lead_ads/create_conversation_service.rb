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
          Rails.logger.warn("Meta Lead Ads: lead sem phone_number hook=#{@hook.id} leadgen=#{@lead[:leadgen_id]} form=#{@lead[:form_id]}")
          # Inbox Cloud API (Channel::Whatsapp) valida o source_id como wa_id so-digitos.
          # Sem telefone nao ha ContactInbox valido nem como enviar — pula limpo (o job nao
          # estoura). Os dados do form ficam na Meta pra follow-up manual. Leads de teste
          # (dummy sem phone) e forms sem campo de telefone caem aqui.
          if cloud_whatsapp_inbox?
            Rails.logger.info("Meta Lead Ads: sem telefone em inbox Cloud API hook=#{@hook.id} leadgen=#{@lead[:leadgen_id]} — pulando (sem contato WhatsApp possivel)")
            return nil
          end
        end

        contact_inbox = build_contact_inbox(normalized_phone)
        conversation, created = find_or_create_conversation(contact_inbox)
        # So coloca no "Novo Lead" quando a conversa nasceu agora — nao regride pro
        # inicio um lead que ja avancou no funil (redelivery do webhook / contato existente).
        place_in_funnel(conversation) if created
        assign_agent_bot(conversation) if created

        if normalized_phone.blank?
          # Sem phone nao da pra mandar via WAHA — anota e pula 1a msg
          Rails.logger.info("Meta Lead Ads: hook=#{@hook.id} conversation=#{conversation.id} — sem phone, sem 1a mensagem (lead exige follow-up manual)")
        elsif skip_initial_message?
          Rails.logger.info("Meta Lead Ads: skip_initial_message=true hook=#{@hook.id} conversation=#{conversation.id} — conversa criada sem 1a mensagem")
        elsif initial_message_already_sent?(conversation)
          # Idempotencia: redelivery/retry do webhook nao reenvia a abertura.
          Rails.logger.info("Meta Lead Ads: hook=#{@hook.id} conversation=#{conversation.id} — 1a mensagem ja enviada, pulando (idempotencia)")
        else
          create_initial_message(conversation)
        end

        conversation
      end

      private

      def skip_initial_message?
        ActiveModel::Type::Boolean.new.cast(@hook.settings['skip_initial_message'])
      end

      # Roteamento por campanha: atribui o lead ao espelho AgentBot configurado no hook
      # (cada hook = uma campanha/formulário = a IA daquele funil). Só em conversa nova,
      # pra não roubar conversa de contato já em atendimento por outro time. A eligibilidade
      # é validada pelo próprio AssignmentService (agent bot precisa estar elegível à inbox).
      # No-op silencioso se não configurado ou se a atribuição falhar.
      def assign_agent_bot(conversation)
        bot_id = @hook.settings['assign_agent_bot_id'].presence
        return if bot_id.blank?

        Conversations::AssignmentService.new(
          conversation: conversation, assignee_id: bot_id, assignee_type: 'AgentBot'
        ).perform
      rescue StandardError => e
        Rails.logger.warn("Meta Lead Ads: falha ao atribuir agent_bot=#{bot_id} conv=#{conversation.id}: #{e.class}: #{e.message}")
      end

      # Coloca o lead no estágio "Novo Lead" do funil de pré-venda Tozi (Kanban).
      # No-op se o funil não existir na inbox (não quebra a criação da conversa).
      def place_in_funnel(conversation)
        Spx::Tozi::FunnelPlacementService.new(
          conversation: conversation, automation_type: 'novo_lead'
        ).perform
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
        # Sem phone: fallback unico por leadgen_id (evita duplicidade e nao colide com outros contatos)
        return "meta_lead:#{@lead[:leadgen_id]}" if phone.blank?

        # WAHA inbox usa JID `<digits>@c.us` como source_id
        if @inbox.channel_type == 'Channel::Api' && @inbox.respond_to?(:waha_session_name) && @inbox.waha_session_name.present?
          return "#{phone.to_s.gsub(/\D/, '')}@c.us"
        end

        # Cloud API (Channel::Whatsapp): o inbound cria/busca a ficha por wa_id so-digitos
        # (via PhoneNumberNormalizationService, reconciliando o 9o digito — variantes 12d/13d).
        # Espelhamos isso pra reusar a ficha que o cliente ja usa nos replies; do contrario a
        # ficha nasce com "+" e o reply cai em ficha/conversa nova (reply orfao + duplicata).
        # Mesmo fix aplicado no DisparoLeadJob#resolved_source_id.
        if @inbox.channel_type == 'Channel::Whatsapp'
          waid = phone.to_s.gsub(/\D/, '')
          return Whatsapp::PhoneNumberNormalizationService.new(@inbox)
                                                          .normalize_and_find_contact_by_provider(waid, :cloud)
        end

        phone
      end

      # Honra o lock_to_single da inbox: reusa a conversa unica do contato (em qualquer
      # ficha), reabrindo se resolvida e atualizando o contexto do lead. Cria conversa nova
      # so quando o contato nunca teve uma. Devolve [conversation, created?]. Idempotente
      # contra redelivery do webhook e retry do Sidekiq (o job re-raise em erro).
      def find_or_create_conversation(contact_inbox)
        base = Conversation.where(inbox_id: @inbox.id, contact_id: contact_inbox.contact_id)
        conversation = base.where.not(status: :resolved).order(created_at: :desc).first ||
                       base.order(created_at: :desc).first

        if conversation
          merge_lead_attributes(conversation)
          conversation.open! unless conversation.open?
          return [conversation, false]
        end

        conversation = Conversation.create!(
          account_id: @inbox.account_id,
          inbox_id: @inbox.id,
          contact_id: contact_inbox.contact_id,
          contact_inbox_id: contact_inbox.id,
          status: conversation_status,
          additional_attributes: { source: 'meta_lead_ads', lead: lead_attributes }
        )
        [conversation, true]
      end

      def lead_attributes
        @lead.slice(:leadgen_id, :ad_name, :campaign_name, :form_id, :platform).compact
      end

      # Reuso: registra o contexto do NOVO form (o lead pode ter entrado por outra campanha
      # antes) sem apagar o source original. A campanha/anuncio atual e o que roteia agora.
      def merge_lead_attributes(conversation)
        attrs = conversation.additional_attributes || {}
        attrs['source'] ||= 'meta_lead_ads'
        attrs['lead'] = lead_attributes
        conversation.update!(additional_attributes: attrs)
      end

      def conversation_status
        @inbox.pending_status_enabled? ? 'pending' : 'open'
      end

      # A abertura automatica carrega content_attributes.meta_lead_ads_initial=true —
      # se ja existe nessa conversa, um redelivery/retry nao deve reenviar.
      def initial_message_already_sent?(conversation)
        conversation.messages.where('content_attributes @> ?', { meta_lead_ads_initial: true }.to_json).exists?
      end

      # Cloud API (WhatsApp oficial) fora da janela 24h só aceita HSM aprovado — texto
      # livre é BLOQUEADO pela Meta. Como o lead de formulário nunca abriu conversa antes,
      # a 1ª mensagem cai fora da janela → tem que ser template. WAHA (Channel::Api) não
      # tem essa restrição → segue texto livre.
      def create_initial_message(conversation)
        return create_initial_template_message(conversation) if cloud_whatsapp_inbox?

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

      def cloud_whatsapp_inbox?
        @inbox.channel_type == 'Channel::Whatsapp'
      end

      # Envia o HSM configurado no hook (whatsapp_template_name). Sem template configurado,
      # NÃO envia nada — melhor o lead entrar sem abertura (e o time trabalhar) do que a
      # mensagem morrer no bloqueio da Meta sem ninguém saber.
      def create_initial_template_message(conversation)
        name = @hook.settings['whatsapp_template_name'].to_s.strip
        if name.blank?
          Rails.logger.warn(
            "Meta Lead Ads: inbox #{@inbox.id} é Cloud API mas hook=#{@hook.id} sem whatsapp_template_name — " \
            '1ª mensagem NÃO enviada (texto livre seria bloqueado na janela 24h). Configure um HSM aprovado.'
          )
          return
        end

        locale = @hook.settings['whatsapp_template_locale'].presence || 'pt_BR'
        body = template_body_params

        Messages::MessageBuilder.new(
          nil,
          conversation,
          {
            content: initial_template_preview,
            content_type: :text,
            message_type: 'outgoing',
            private: false,
            content_attributes: { meta_lead_ads_initial: true },
            template_params: {
              'name' => name, 'language' => locale,
              'processed_params' => (body.present? ? { 'body' => body } : {})
            }
          }.with_indifferent_access
        ).perform
      end

      # {{1}}, {{2}}, ... vêm de whatsapp_template_body_fields (campos do lead, em ordem;
      # default first_name). Vazio → template sem variáveis de corpo.
      def template_body_params
        fields = (@hook.settings['whatsapp_template_body_fields'].presence || 'first_name')
                 .to_s.split(',').map(&:strip).reject(&:blank?)
        return {} if fields.empty?

        ctx = template_render_context
        fields.each_with_index.each_with_object({}) do |(field, i), acc|
          acc[(i + 1).to_s] = ctx[field].to_s
        end
      end

      # Espelho na transcrição (o que o time vê). O LEAD recebe o HSM aprovado, não este texto.
      def initial_template_preview
        render_template.presence || "Olá #{template_render_context['first_name']}!"
      end

      def render_template
        template = @hook.settings['initial_message_template'].presence || DEFAULT_TEMPLATE
        Liquid::Template.parse(template).render(template_render_context)
      end

      def template_render_context
        {
          'full_name' => @lead[:full_name].to_s,
          'first_name' => @lead[:full_name].to_s.split.first.to_s,
          'ad_name' => @lead[:ad_name].to_s,
          'campaign_name' => @lead[:campaign_name].to_s,
          'city' => @lead[:city].to_s,
          'email' => @lead[:email].to_s,
          'phone' => @lead[:phone_number].to_s
        }
      end
    end
  end
end
