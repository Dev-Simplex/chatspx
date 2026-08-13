# Recebe lead enriquecido + hook, cria Contact (ou reutiliza) na inbox alvo,
# abre Conversation em status pending (Captain dispara) e envia 1a mensagem
# outgoing renderizada a partir do template Liquid do hook.
#
# ⚠️ O NAMESPACE MENTE, de propósito. Este serviço não é mais só do Meta: ele é a engine
# de "lead de formulário" e atende também os leads do site (Webhooks::SiteLeadJob). Ele
# sempre foi genérico — recebe `hook:` e `lead:`, e tudo que é específico de uma origem
# vive no job que chama, não aqui. Renomear para algo como LeadIntake::* seria mais
# honesto, mas move código que processa ~1.652 conversas/mês: risco sem retorno.
# Ao mexer aqui, lembre que há mais de uma origem chamando.
#
# Flag de teste: `settings.skip_initial_message = true` cria a conversa mas
# NÃO envia a 1ª mensagem outgoing. Útil enquanto valida o fluxo sem
# incomodar leads reais.
module Meta
  module LeadAds
    class CreateConversationService
      DEFAULT_TEMPLATE = "Olá {{first_name}}! Vi seu interesse no anúncio \"{{ad_name}}\". Sou da equipe e estou aqui pra ajudar. Pode me contar um pouco mais sobre o que você procura?".freeze
      # Mesmo formato que o Contact exige em `phone_number` (app/models/contact.rb).
      # Espelhado aqui porque quem grava é este serviço: telefone reprovado tem que
      # virar nil ANTES do Contact, senão o RecordInvalid mata o job e o lead se perde.
      CONTACT_E164_FORMAT = /\+[1-9]\d{1,14}\z/
      # Teto da jornada de navegação — ela entra no contexto do LLM a cada turno.
      JORNADA_MAX_CHARS = 600
      # `whatsapp_template_body_fields = none` declara template SEM variável no corpo.
      NO_BODY_FIELDS = 'none'.freeze
      # Campos do lead que podem preencher {{1}}, {{2}}, ... no corpo do HSM: exatamente as
      # chaves de `template_render_context`, e nada além delas — campo fora desta lista
      # renderiza string vazia e a Meta recusa a mensagem. Quem valida a configuração antes
      # de salvar lê daqui (`LeadCampaigns::RoutingUpdater`); um spec trava a lista contra
      # o contexto real, para os dois não se separarem em silêncio.
      BODY_FIELDS = %w[first_name full_name ad_name campaign_name city email phone empreendimento].freeze
      # Idioma assumido quando o hook não declara: a Meta casa o template por (nome, idioma),
      # então quem valida a configuração tem que assumir o MESMO default que o envio.
      DEFAULT_TEMPLATE_LOCALE = 'pt_BR'.freeze
      # Código do imóvel escondido no NOME DO ANÚNCIO. Campanha de catálogo entrega o código
      # no `retailer_item_id`; campanha de FORMULÁRIO não tem catálogo, e aí o único lugar onde
      # o código existe é o nome que o anunciante deu à peça ("IMÓVEL 9817 - TELHADO APARENTE").
      #
      # As duas formas exigem âncora, nunca "algum número no meio do texto": ou vem precedido de
      # um marcador explícito, ou o nome inteiro É o código. É o que separa "IMÓVEL 9817" de
      # "RMKT VENDAS 2026" e "CASAS 300-900K" — nome de anúncio é cheio de número que não é imóvel.
      # Casa contra o nome já normalizado (minúsculo, sem acento) por `normalized_ad_name`.
      AD_NAME_CODE_MARKER = /\b(?:imove(?:l|is)|cod(?:igo)?)\b\W{0,3}(\d{3,6})\b/
      AD_NAME_CODE_ONLY = /\A(\d{3,6})\z/

      def initialize(hook:, lead:)
        @hook = hook
        @lead = lead
        @inbox = Inbox.find(hook.settings['target_inbox_id'])
      end

      def perform
        unless campaign_allowed?
          Rails.logger.info("Meta Lead Ads: campanha #{@lead[:campaign_id].inspect} (#{@lead[:campaign_name]}) fora do allowlist do hook=#{@hook.id} — lead ignorado (leadgen=#{@lead[:leadgen_id]})")
          return nil
        end

        normalized_phone = @lead[:phone_number].present? ? normalize_phone(@lead[:phone_number]) : nil

        if normalized_phone.blank?
          # Loga o telefone CRU e o e-mail: este log é o único rastro de um lead pago que não
          # vira conversa. Sem ele, recuperar exige garimpar o Lead Center da Meta.
          Rails.logger.warn(
            "Meta Lead Ads: lead sem phone_number utilizavel hook=#{@hook.id} leadgen=#{@lead[:leadgen_id]} " \
            "form=#{@lead[:form_id]} telefone_cru=#{@lead[:phone_number].inspect} email=#{@lead[:email].inspect}"
          )
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
        # Atribui time + IA do hook JA na criacao (antes do template). Com o time setado na
        # criacao, a triagem geral (automation #55, so p/ conversa SEM time) pula este lead —
        # entao a atribuicao a Sofia gruda em vez de ser sobrescrita pela triagem.
        route_lead(conversation)
        # Espelha a origem (campanha/anuncio/publico/plataforma) em custom_attributes + label,
        # pra ficar VISIVEL pro time no painel (additional_attributes nao renderiza na UI).
        stamp_campaign_visibility(conversation)

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

      # Filtro dinamico por campanha: o operador define allowed_campaign_ids no hook (Array
      # ou CSV de campaign_ids). Vazio = aceita todas. So leads das campanhas listadas entram.
      def campaign_allowed?
        allowed = allowed_campaign_ids
        return true if allowed.empty?

        allowed.include?(@lead[:campaign_id].to_s)
      end

      def allowed_campaign_ids
        raw = @hook.settings['allowed_campaign_ids']
        list = raw.is_a?(Array) ? raw : raw.to_s.split(',')
        list.map { |x| x.to_s.strip }.reject(&:blank?)
      end

      # Resolve uma config do hook honrando OVERRIDE POR CAMPANHA. O operador pode definir
      # settings['campaign_overrides'] = { "<campaign_id>" => { "whatsapp_template_name" => "...",
      # "assign_agent_bot_id" => "...", ... } } pra dar opener/time/IA distintos por campanha
      # (ex.: remarketing com abertura calorosa). Sem override, cai no valor global do hook.
      def hook_setting(key)
        overrides = @hook.settings['campaign_overrides']
        if overrides.is_a?(Hash)
          ov = overrides[@lead[:campaign_id].to_s]
          return ov[key] if ov.is_a?(Hash) && ov[key].to_s.strip.present?
        end
        @hook.settings[key]
      end

      def assign_team_id
        hook_setting('assign_team_id').presence
      end

      # Roteia o lead pro time + IA (espelho AgentBot) do hook, JA na criacao. Setar o time
      # na criacao faz a triagem geral (automation #55, so p/ conversa sem time) pular o lead.
      def route_lead(conversation)
        set_team(conversation)
        assign_agent_bot(conversation)
      end

      def set_team(conversation)
        return if assign_team_id.blank?
        return if conversation.team_id.to_s == assign_team_id.to_s

        conversation.update!(team_id: assign_team_id)
      rescue StandardError => e
        Rails.logger.warn("Meta Lead Ads: falha ao setar team=#{assign_team_id} conv=#{conversation.id}: #{e.class}: #{e.message}")
      end

      # Atribui o lead ao espelho AgentBot do hook (a IA daquele funil). Nao rouba conversa
      # que um HUMANO ja atende (assignee_id presente). A eligibilidade e validada pelo
      # proprio AssignmentService (o bot precisa estar elegivel a inbox). No-op silencioso.
      def assign_agent_bot(conversation)
        bot_id = hook_setting('assign_agent_bot_id').presence
        return if bot_id.blank?
        return if conversation.assignee_id.present?

        Conversations::AssignmentService.new(
          conversation: conversation, assignee_id: bot_id, assignee_type: 'AgentBot'
        ).perform
      rescue StandardError => e
        Rails.logger.warn("Meta Lead Ads: falha ao atribuir agent_bot=#{bot_id} conv=#{conversation.id}: #{e.class}: #{e.message}")
      end

      # Espelha a origem do lead (campanha/anúncio/público/plataforma) nos custom_attributes da
      # conversa + uma label da campanha. O time NÃO vê additional_attributes na UI (o Chatwoot
      # só renderiza custom_attributes definidos); isto torna a origem visível e filtrável.
      # Idempotente. Genérico — serve qualquer conta que use Meta Lead Ads (no-op se sem dados).
      def stamp_campaign_visibility(conversation)
        im = imovel_info
        attrs = {
          'meta_campanha' => @lead[:campaign_name].to_s.strip.presence,
          'meta_anuncio' => @lead[:ad_name].to_s.strip.presence,
          'meta_publico' => @lead[:adset_name].to_s.strip.presence,
          'meta_origem' => platform_label,
          'meta_tipo' => lead_tipo_label,
          'meta_imovel_codigo' => im && im[:codigo],
          'meta_imovel' => im && im[:descricao],
          'jornada' => jornada
        }.compact
        return if attrs.empty?

        conversation.update!(custom_attributes: (conversation.custom_attributes || {}).merge(attrs))

        slug = campaign_slug(@lead[:campaign_name])
        return if slug.blank?

        ensure_label(slug)
        conversation.add_labels((conversation.label_list + [slug]).uniq)
      rescue StandardError => e
        Rails.logger.warn("Meta Lead Ads: falha ao carimbar visibilidade conv=#{conversation.id}: #{e.class}: #{e.message}")
      end

      # O que a pessoa viu e curtiu antes de preencher o formulário (leads de site).
      # É ESTADO — o caminho que ela percorreu — e por isso pode ir ao agente junto do
      # resto dos custom_attributes, que chegam inteiros ao LLM a cada turno.
      #
      # ⚠️ NUNCA colocar aqui identidade de pessoa (nome de corretor/atendente) nem
      # marcador de espera: a IA repassa ao cliente. Regra vinda de incidente — ver o
      # vault, `aprendizados/captain-custom-attributes-chegam-ao-llm.md`.
      #
      # Truncado porque entra no contexto do modelo em TODA mensagem, não só na primeira.
      def jornada
        @lead[:jornada].to_s.strip.presence&.truncate(JORNADA_MAX_CHARS)
      end

      def platform_label
        case @lead[:platform].to_s.downcase
        when 'fb', 'facebook' then 'Facebook'
        when 'ig', 'instagram' then 'Instagram'
        else @lead[:platform].to_s.strip.presence
        end
      end

      # Imóvel específico do lead: busca descrição curta + foto de destaque no Vista. Memoizado.
      # No-op (nil) se não houver código, credencial Vista, ou se o código não resolver — aí o
      # lead segue sem imóvel (fluxo normal, opener genérico).
      def imovel_info
        return @imovel_info if defined?(@imovel_info)

        @imovel_info = fetch_imovel(imovel_codigo)
      end

      # Duas origens para o mesmo código. Catálogo (dynamic ads) entrega no `retailer_item_id` —
      # é a fonte confiável e tem precedência. Campanha de formulário não tem catálogo e o campo
      # vem vazio; aí o código só existe no nome do anúncio, e ler dali é opt-in por hook/campanha
      # (`imovel_codigo_from_ad_name`), porque depende de como o anunciante nomeia as peças.
      def imovel_codigo
        @lead[:retailer_item_id].to_s.strip.presence || codigo_from_ad_name
      end

      def codigo_from_ad_name
        return nil unless read_codigo_from_ad_name?

        name = normalized_ad_name
        return nil if name.blank?

        match = name.match(AD_NAME_CODE_ONLY) || name.match(AD_NAME_CODE_MARKER)
        match && match[1]
      end

      def read_codigo_from_ad_name?
        ActiveModel::Type::Boolean.new.cast(hook_setting('imovel_codigo_from_ad_name'))
      end

      # Minúsculo e sem acento: o marcador é escrito "IMÓVEL", "Imovel", "imóvel" conforme quem
      # cadastrou o anúncio, e a regex casa uma forma só.
      def normalized_ad_name
        @lead[:ad_name].to_s.downcase.tr('áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc').strip
      end

      def fetch_imovel(codigo)
        codigo = codigo.to_s.strip
        key = ENV['TOZI_VISTA_API_KEY'].to_s
        return nil if codigo.blank? || key.blank?

        base = ENV['TOZI_VISTA_BASE_URL'].presence || 'toz19328-rest.vistahost.com.br'
        info = vista_get(base, key, '/imoveis/listar',
                         fields: %w[Codigo TipoImovel Categoria Dormitorios Bairro Cidade ValorVenda TituloSite Status],
                         filter: { 'Codigo' => codigo }, paginacao: { pagina: 1, quantidade: 1 })
        im = info.is_a?(Hash) ? info.values.find { |v| v.is_a?(Hash) && v['Codigo'] } : nil
        return nil unless im

        { codigo: codigo, descricao: imovel_descricao(im), foto_url: imovel_foto(base, key, codigo) }
      rescue StandardError => e
        Rails.logger.warn("Meta Lead Ads: falha buscando imóvel #{codigo} no Vista: #{e.class}: #{e.message}")
        nil
      end

      def imovel_descricao(imovel)
        dorm = imovel['Dormitorios'].to_s.strip
        partes = [imovel['Categoria'].to_s.strip.presence,
                  (dorm.present? && dorm != '0' ? "#{dorm} dorm" : nil),
                  imovel['Bairro'].to_s.strip.presence].compact
        partes.join(' — ').presence || "imóvel #{imovel['Codigo']}"
      end

      # URL da FOTO DE DESTAQUE (a capa do imóvel) — pública no CDN do Vista, serve pro header do
      # template. Usa o campo dedicado FotoDestaque; fallback: a marcada Destaque no array, senão a 1ª.
      def imovel_foto(base, key, codigo)
        det = vista_get(base, key, '/imoveis/detalhes',
                        { fields: ['Codigo', 'FotoDestaque', { 'Foto' => %w[Foto Destaque] }] }, imovel: codigo)
        return nil unless det.is_a?(Hash)
        return det['FotoDestaque'] if det['FotoDestaque'].to_s.strip.present?

        fotos = det['Foto']
        return nil unless fotos.is_a?(Hash)

        destaque = fotos.values.find { |f| f.is_a?(Hash) && f['Destaque'].to_s.casecmp('sim').zero? }
        ((destaque || fotos.values.first) || {})['Foto']
      end

      def vista_get(base, key, path, pesquisa, extra = {})
        res = HTTParty.get("https://#{base}#{path}",
                           query: { key: key, pesquisa: pesquisa.to_json }.merge(extra),
                           headers: { 'Accept' => 'application/json' })
        res.success? ? res.parsed_response : nil
      rescue StandardError
        nil
      end

      # Classifica o lead como Remarketing (já teve contato com a Tozi) vs Lead novo (frio), a
      # partir do override da campanha (campaign_overrides[cid]['lead_tipo'] == 'remarketing').
      # Alimenta a conduta da Sofia (retomada calorosa vs apresentação) e aparece no painel.
      def lead_tipo_label
        hook_setting('lead_tipo').to_s.downcase.strip == 'remarketing' ? 'Remarketing' : 'Lead novo'
      end

      # "[FORMS] - PACAEMBU" -> "pacaembu"; "[FORMS] - RMKT VENDAS - 2026" -> "rmkt-vendas-2026".
      # Tira o prefixo entre colchetes, normaliza acento e vira slug com hifens (formato de label).
      def campaign_slug(name)
        s = name.to_s.downcase.tr('áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc')
        s = s.gsub(/\[.*?\]/, ' ').gsub(/[^a-z0-9]+/, '-').gsub(/\A-+|-+\z/, '')
        s.presence
      end

      # Garante o registro Label na conta (pra renderizar com cor + entrar no filtro). find_or_create.
      def ensure_label(slug)
        @inbox.account.labels.find_or_create_by!(title: slug)
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
        nil
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

        # Zero de tronco da discagem nacional ("066 99963-6866"): não existe em e164 e é o
        # que mais aparece no formulário. Sem tirar, o número vira "+066..." e o lead se perde
        # — sendo que o telefone é perfeitamente válido.
        digits = digits.sub(/\A0+/, '')
        # Número sem DDD (só o celular de 8-9 dígitos, ex.: "996926393"): prefixa o DDD padrão
        # do hook (ex.: 66 = Sinop). Muita gente digita o número sem o DDD no formulário do Meta.
        ddd = default_ddd
        digits = "#{ddd}#{digits}" if ddd.present? && digits.length.between?(8, 9)
        # Com DDD mas sem o código do país (10-11 dígitos): prefixa 55.
        digits = "55#{digits}" if digits.length.between?(10, 11)
        formatted = "+#{digits}"
        candidate = Contacts::BrazilPhoneNormalizer.normalize(formatted) || formatted
        # O BrazilPhoneNormalizer NÃO valida — ele só acrescenta o 9º dígito e devolve a
        # entrada intacta quando não reconhece o padrão. Quem valida é o Contact, e lá o
        # estouro MATA o job e o LEAD SOME. O campo telefone do formulário recebe de tudo
        # ("2 mil de entrada", "6......"), então a validação tem que acontecer aqui: telefone
        # impossível vira nil e o lead segue pelo caminho de "sem telefone".
        candidate.match?(CONTACT_E164_FORMAT) ? candidate : nil
      end

      # DDD padrão do hook (dinâmico, por conta/campanha) pra completar número sem DDD.
      def default_ddd
        @hook.settings['default_ddd'].to_s.gsub(/\D/, '').presence
      end

      def build_contact_inbox(normalized_phone)
        ContactInboxWithContactBuilder.new(
          inbox: @inbox,
          contact_attributes: {
            name: contact_name,
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
              retailer_item_id: @lead[:retailer_item_id],
              city: @lead[:city]
            }.compact
          },
          source_id: source_id_for(normalized_phone)
        ).perform
      end

      # Sem nome confiável, o contato fica SEM NOME — o painel identifica pelo telefone e
      # quem descobre o nome é a conversa (a IA ou o atendente pergunta e confirma).
      #
      # Nada de marcador fabricado ("Lead Meta <telefone>", que era o que estava aqui):
      # `contact.name` é área de trabalho do time humano — eles anotam ali de que se trata
      # o contato ("Fulano / Casa do Beltrano"). Escrever qualquer coisa nossa nesse campo
      # apaga a referência que o corretor usa. Mesma regra do disparo.
      #
      # String VAZIA, nunca nil: o builder faz `name || Haikunator.haikunate`, e SÓ o nil
      # cai no apelido aleatório — '' é truthy em Ruby e passa intacto.
      def contact_name
        @lead[:full_name].to_s.strip
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
          team_id: assign_team_id,
          additional_attributes: { source: 'meta_lead_ads', lead: lead_attributes }
        )
        [conversation, true]
      end

      def lead_attributes
        @lead.slice(:leadgen_id, :ad_name, :campaign_name, :form_id, :platform, :retailer_item_id).compact
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
      #
      # ⚠️ `content_attributes` é jsonb NA TABELA mas `store ... coder: JSON` NO MODELO: o Rails
      # serializa o Hash e o banco guarda uma STRING JSON, não um objeto. Contra uma string,
      # `@>` e `->>` nunca casam — a checagem devolvia false sempre e 26 leads receberam a
      # abertura duas vezes em 90 dias. `#>> '{}'` desembrulha a string e o `::jsonb` reparseia;
      # é o mesmo padrão do `EPISODE_ANCHOR_SQL` (enterprise/app/models/captain/conversation_episode.rb),
      # e funciona tanto pra linha duplo-serializada quanto pra objeto jsonb de verdade.
      INITIAL_MESSAGE_SQL = "(content_attributes #>> '{}')::jsonb ->> 'meta_lead_ads_initial' = 'true'".freeze

      def initial_message_already_sent?(conversation)
        conversation.messages.where(INITIAL_MESSAGE_SQL).exists?
      end

      # Cloud API (WhatsApp oficial) fora da janela 24h só aceita HSM aprovado — texto
      # livre é BLOQUEADO pela Meta. Como o lead de formulário nunca abriu conversa antes,
      # a 1ª mensagem cai fora da janela → tem que ser template. WAHA (Channel::Api) não
      # tem essa restrição → segue texto livre.
      def create_initial_message(conversation)
        return create_imovel_opener(conversation) if cloud_whatsapp_inbox? && imovel_opener_ready?
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

      # Opener com FOTO do imóvel do anúncio (remarketing de catálogo). Só entra quando o hook
      # tem imovel_template_name configurado E o lead traz um imóvel com foto. Sem isso, cai no
      # opener normal (fica inativo até o template ser aprovado e configurado no override).
      def imovel_opener_ready?
        hook_setting('imovel_template_name').to_s.strip.present? &&
          imovel_info.present? && imovel_info[:foto_url].present?
      end

      def create_imovel_opener(conversation)
        d = imovel_info
        first = first_name
        # {{2}} carrega a descrição + o código do imóvel, pra o lead/corretor referenciar o imóvel exato.
        imovel_txt = "#{d[:descricao]} (cód #{d[:codigo]})"
        Messages::MessageBuilder.new(
          nil, conversation,
          {
            content: "Oi #{first}! Aqui é da Tozi Imóveis. Vi que você se interessou neste imóvel: #{imovel_txt}. " \
                     'Quer que eu te mande as fotos e os detalhes?',
            content_type: :text, message_type: 'outgoing', private: false,
            content_attributes: { meta_lead_ads_initial: true },
            template_params: {
              'name' => hook_setting('imovel_template_name'),
              'language' => (hook_setting('whatsapp_template_locale').presence || DEFAULT_TEMPLATE_LOCALE),
              'processed_params' => {
                'header' => { 'media_url' => d[:foto_url], 'media_type' => 'image' },
                'body' => { '1' => first, '2' => imovel_txt }
              }
            }
          }.with_indifferent_access
        ).perform
      end

      def cloud_whatsapp_inbox?
        @inbox.channel_type == 'Channel::Whatsapp'
      end

      # Envia o HSM configurado no hook (whatsapp_template_name). Sem template configurado,
      # NÃO envia nada — melhor o lead entrar sem abertura (e o time trabalhar) do que a
      # mensagem morrer no bloqueio da Meta sem ninguém saber.
      def create_initial_template_message(conversation)
        name = hook_setting('whatsapp_template_name').to_s.strip
        if name.blank?
          Rails.logger.warn(
            "Meta Lead Ads: inbox #{@inbox.id} é Cloud API mas hook=#{@hook.id} sem whatsapp_template_name — " \
            '1ª mensagem NÃO enviada (texto livre seria bloqueado na janela 24h). Configure um HSM aprovado.'
          )
          return
        end

        locale = hook_setting('whatsapp_template_locale').presence || DEFAULT_TEMPLATE_LOCALE
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
      # default first_name).
      #
      # `none` declara explicitamente um template SEM variável no corpo — o opener
      # genérico, que só abre a porta. Precisa ser explícito porque o default é
      # 'first_name': deixar o campo em branco mandaria {{1}} para um template que não
      # tem variável, e a Meta responde #132000.
      def template_body_params
        configured = hook_setting('whatsapp_template_body_fields').to_s.strip
        return {} if configured.casecmp?(NO_BODY_FIELDS)

        fields = (configured.presence || 'first_name').split(',').map(&:strip).reject(&:blank?)
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
        template = hook_setting('initial_message_template').presence || DEFAULT_TEMPLATE
        Liquid::Template.parse(template).render(template_render_context)
      end

      # Saudação neutra quando o lead não trouxe nome confiável (o FetchLeadService
      # devolve nil quando o campo veio com algo que não é nome). Sem isso a abertura
      # renderizaria "Oi !" — e usar um nome errado é pior ainda: o lead lê como
      # sistema quebrado. Mesmo fallback do opener de imóvel e do motor de disparo.
      NEUTRAL_GREETING = 'tudo bem'.freeze

      def first_name
        @lead[:full_name].to_s.split.first.presence || NEUTRAL_GREETING
      end

      def template_render_context
        {
          'full_name' => @lead[:full_name].to_s,
          'first_name' => first_name,
          'ad_name' => @lead[:ad_name].to_s,
          'campaign_name' => @lead[:campaign_name].to_s,
          'city' => @lead[:city].to_s,
          'email' => @lead[:email].to_s,
          'phone' => @lead[:phone_number].to_s,
          # nome do empreendimento p/ o opener ancorado (ex.: "ETNA BY SPL"), setado por override de campanha
          'empreendimento' => hook_setting('empreendimento').to_s
        }
      end
    end
  end
end
