module Campaigns
  module Whatsapp
    # Higiene da audiencia de um disparo — e o "importador" que hoje e feito a mao
    # (scripts/spx/tozi/ingestao_*.py) a cada campanha.
    #
    # Recebe as linhas cruas da lista e devolve QUEM ENTRA, QUEM SAI e POR QUE.
    # O motivo de cada descarte e a razao de existir deste servico: o nome do
    # arquivo mente (listas "200" e "380" tinham 100 e 81 linhas), entao ninguem
    # consegue planejar um disparo sem ver a audiencia limpa ANTES de disparar.
    #
    # Nao persiste nada — quem grava e o ListLoaderService, que roda exatamente
    # estas regras. Assim o preview e o carregamento nunca divergem.
    #
    # A gramatica do numero em si (chave canonica, 9o digito, DDI, DDD default)
    # vive no CanonicalPhone — aqui so se decide quem entra e por que.
    class AudienceBuilderService
      # Motivos de descarte, na ordem em que sao avaliados. Chaves estaveis: viram
      # rotulo na tela e coluna no CSV de revisao.
      REASONS = %w[
        telefone_invalido telefone_fixo numero_suspeito bloqueado optou_por_sair
        ja_disparado ja_na_campanha atendimento_ativo duplicado_na_lista
      ].freeze

      # Conversa nao-resolvida = atendimento em andamento. Disparo nao atropela.
      ACTIVE_STATUSES = %i[open pending snoozed].freeze

      # Baldes de supressao que barram o disparo. O handler do "PARAR"
      # (AutomationRuleListener) so escreve `marketing`, e `all` e o catch-all que
      # vale pra qualquer balde — os mesmos dois que ContactFlowSuppression.suppressed?
      # casa. Disparo utility pra quem suprimiu marketing tambem para: num opt-out,
      # nao enviar e o lado seguro de errar.
      SUPPRESSION_CATEGORIES = %w[marketing all].freeze

      # Status que provam que o numero JA levou um disparo (nao bater de novo).
      DISPATCHED_STATUSES = %i[sent delivered read replied].freeze

      # Os dois lugares onde "ja disparou" pode estar gravado. Ver `dedup_config`.
      DEDUP_SOURCES = %w[recipients conversations].freeze

      Result = Struct.new(:accepted, :rejected, :stats, keyword_init: true) do
        def total
          accepted.size + rejected.size
        end
      end

      # rows: enumeravel de hashes { name/nome, phone/telefone, params }
      # blocklist_phones: telefones crus a excluir (ex.: CSV de corretores), opcional.
      def initialize(campaign:, rows:, blocklist_phones: nil)
        @campaign = campaign
        @rows = rows
        @blocklist_phones = blocklist_phones
      end

      def perform
        parsed = rows.map { |row| parse(row) }
        canonicals = parsed.filter_map { |entry| entry[:canonical] }.uniq

        load_lookups(canonicals)
        classify(parsed)
      end

      private

      attr_reader :campaign, :rows, :blocklist_phones

      # ---------------------------------------------------------------- parsing

      def parse(row)
        raw = value(row, :phone) || value(row, :telefone)
        name = value(row, :name).to_s.strip.presence || value(row, :nome).to_s.strip.presence
        entry = { name: name, raw: raw.to_s.strip, params: value(row, :params) }
        parser = phones

        ddd, subscriber = parser.split_number(raw)
        return entry.merge(reason: 'telefone_invalido') if ddd.nil?
        return entry.merge(reason: 'telefone_fixo') if parser.landline?(subscriber)
        return entry.merge(reason: 'numero_suspeito') if parser.suspicious?(ddd, subscriber)

        entry.merge(canonical: parser.canonical(ddd, subscriber), phone: parser.e164(ddd, subscriber))
      end

      def phones
        @phones ||= CanonicalPhone.new(default_ddd: campaign.dispatch_config['default_ddd'])
      end

      # ------------------------------------------------------------ classificacao

      def classify(parsed)
        accepted = []
        rejected = []
        seen = Set.new

        parsed.each do |entry|
          reason = entry[:reason] || rejection_for(entry[:canonical], seen)
          if reason
            rejected << { name: entry[:name], phone: entry[:raw], reason: reason }
          else
            seen << entry[:canonical]
            accepted << entry.slice(:name, :phone, :canonical, :params)
          end
        end

        Result.new(accepted: accepted, rejected: rejected, stats: stats_for(accepted, rejected))
      end

      def rejection_for(canonical, seen)
        return 'bloqueado' if @blocked.include?(canonical)
        # Antes de ja_disparado de proposito: quem pediu PARAR depois de ter levado um
        # disparo sairia contado como ja_disparado, e o numero de compliance da tela
        # sairia menor do que e. A posicao aqui E a medicao.
        return 'optou_por_sair' if @suppressed.include?(canonical)
        return 'ja_disparado' if @dispatched.include?(canonical)
        return 'ja_na_campanha' if @in_campaign.include?(canonical)
        return 'atendimento_ativo' if @active.include?(canonical)
        return 'duplicado_na_lista' if seen.include?(canonical)

        nil
      end

      def stats_for(accepted, rejected)
        counts = rejected.each_with_object(Hash.new(0)) { |r, acc| acc[r[:reason]] += 1 }
        {
          total: accepted.size + rejected.size,
          aceitos: accepted.size,
          descartados: rejected.size,
          por_motivo: REASONS.index_with { |reason| counts[reason] }.select { |_, n| n.positive? }
        }
      end

      # ----------------------------------------------------------------- lookups
      #
      # Todas as consultas sao limitadas aos numeros DA LISTA (nao varrem a inbox),
      # entao o custo acompanha o tamanho do arquivo, nao o tamanho da base.

      def load_lookups(canonicals)
        @blocked = blocked_canonicals(canonicals)
        @suppressed = suppressed_canonicals(canonicals)
        @dispatched = dispatched_canonicals(canonicals)
        @in_campaign = in_campaign_canonicals(canonicals)
        @active = active_canonicals(canonicals)
      end

      # Quem JA levou disparo — lido por DOIS motores, porque eles gravam em lugares
      # diferentes. O motor novo cria `campaign_recipients`; o antigo
      # (Spx::Tozi::DisparoLeadJob, campanhas 1 e 2, ~6.100 pessoas em junho/2026)
      # carimba `campaign_id` na CONVERSA e nao cria linha nenhuma na tabela nova.
      # Ler so a tabela nova deixou 294 pessoas levarem o Urban depois de ja terem
      # levado o disparo de junho.
      def dispatched_canonicals(canonicals)
        return Set.new if canonicals.empty?

        dispatched_by_recipients(canonicals) | dispatched_by_conversations(canonicals)
      end

      def dispatched_by_recipients(canonicals)
        return Set.new unless dedup_source?('recipients')

        scope = CampaignRecipient.where(account_id: campaign.account_id, status: DISPATCHED_STATUSES)
                                 .where(canonical_phone: canonicals)
                                 .where.not(campaign_id: campaign.id)
        scope = scope.where(campaign_id: dedup_campaign_ids) if dedup_campaign_ids
        # COALESCE porque `sent_at` so e gravado no envio: linha que chegou a delivered/read
        # por webhook sem ter passado por ali ficaria FORA da janela — e o numero levaria
        # disparo em dobro, que e exatamente o erro que esta consulta existe pra evitar.
        scope = scope.where('COALESCE(campaign_recipients.sent_at, campaign_recipients.created_at) >= ?', dedup_since) if dedup_since
        scope.distinct.pluck(:canonical_phone).to_set
      end

      # A data do disparo vem da CAMPANHA, nao da conversa: o motor antigo REUSA a conversa
      # que ja existe e so carimba o `campaign_id` (disparo_lead_job.rb), entao
      # `conversations.created_at` pode ser meses ANTERIOR ao envio. Datar por ele encolheria
      # a janela em silencio e liberaria quem nao devia sair.
      def dispatched_by_conversations(canonicals)
        return Set.new unless dedup_source?('conversations')

        ids_by_canonical = contact_ids_by_canonical(canonicals)
        return Set.new if ids_by_canonical.empty?

        hit = conversations_dispatched_scope(ids_by_canonical.values.flatten).distinct.pluck(:contact_id).to_set
        ids_by_canonical.select { |_, ids| ids.any? { |id| hit.include?(id) } }.keys.to_set
      end

      def conversations_dispatched_scope(contact_ids)
        scope = Conversation.joins(:campaign)
                            .where(contact_id: contact_ids)
                            .where.not(conversations: { campaign_id: campaign.id })
        scope = scope.where(conversations: { campaign_id: dedup_campaign_ids }) if dedup_campaign_ids
        return scope unless dedup_since

        scope.where('COALESCE(campaigns.scheduled_at, campaigns.created_at) >= ?', dedup_since)
      end

      # --------------------------------------------------------- corte da dedup
      #
      # `dispatch_config['dedup']` escolhe COMO cortar. Tudo e opcional e a ausencia
      # significa o corte mais largo — "ja disparou alguma vez, por qualquer motor, sai":
      #
      #   window_days  => so conta disparo dos ultimos N dias. Ausente = historico inteiro.
      #   campaign_ids => so conta disparo DESTAS campanhas. Ausente = todas.
      #   sources      => quais motores entram ('recipients' / 'conversations'). Ausente = os dois.
      #
      # Sem isto o corte e "pra sempre", e as ~10.600 pessoas que so receberam disparo em
      # junho ficariam inelegiveis para sempre — o que nao e decisao de codigo, e de campanha.
      def dedup_config
        @dedup_config ||= campaign.dispatch_config['dedup'].presence || {}
      end

      def dedup_source?(name)
        configured = Array(dedup_config['sources']).map(&:to_s) & DEDUP_SOURCES
        configured.empty? || configured.include?(name)
      end

      def dedup_campaign_ids
        Array(dedup_config['campaign_ids']).map(&:to_i).reject(&:zero?).presence
      end

      def dedup_since
        days = dedup_config['window_days'].to_i
        days.positive? ? days.days.ago : nil
      end

      def in_campaign_canonicals(canonicals)
        return Set.new if canonicals.empty?

        campaign.campaign_recipients.where(canonical_phone: canonicals).distinct.pluck(:canonical_phone).to_set
      end

      def active_canonicals(canonicals)
        ids_by_canonical = contact_ids_by_canonical(canonicals)
        return Set.new if ids_by_canonical.empty?

        with_active = Conversation.where(inbox_id: campaign.inbox_id, status: ACTIVE_STATUSES)
                                  .where(contact_id: ids_by_canonical.values.flatten)
                                  .distinct.pluck(:contact_id).to_set
        ids_by_canonical.select { |_, ids| ids.any? { |id| with_active.include?(id) } }.keys.to_set
      end

      def blocked_canonicals(canonicals)
        blocked = Set.new(Array(blocklist_phones).filter_map { |raw| phones.canonical_of(raw) })
        return blocked if blocklist_labels.empty?

        ids_by_canonical = contact_ids_by_canonical(canonicals)
        return blocked if ids_by_canonical.empty?

        tagged = Contact.where(id: ids_by_canonical.values.flatten)
                        .tagged_with(blocklist_labels, any: true).pluck(:id).to_set
        blocked + ids_by_canonical.select { |_, ids| ids.any? { |id| tagged.include?(id) } }.keys
      end

      def blocklist_labels
        @blocklist_labels ||= Array(campaign.dispatch_config['blocklist_labels']).map(&:to_s).reject(&:blank?)
      end

      # Quem respondeu PARAR. Ate aqui a supressao so era lida pelo motor de Flows
      # (Flows::Compliance) — o disparo em massa nao a consultava.
      #
      # NAO CONCLUA DAQUI QUE OPT-OUT ESTA RESOLVIDO. Medido na Tozi (conta 6) em
      # 11/08/2026: a tabela tem ZERO linhas na instancia INTEIRA, porque o gravador
      # (AutomationRuleListener#handle_incoming_opt_out) so e alcancado por dentro do
      # run_flows, que exige account.flows_engine_enabled? — falso naquela conta. Ou
      # seja: esta consulta nasce INERTE la, e nao por culpa deste arquivo. A metade
      # que falta e ESCREVER a linha, nao le-la — opt-out e compliance e nao deveria
      # depender de o cliente ter o motor de Flows ligado.
      #
      # Segundo furo, tambem fora daqui: o matcher exige match exato da mensagem
      # inteira contra parar/sair/stop/cancelar. Na inbox 99, das 23 recusas reais
      # ("Nao tenho interesse") nenhuma casou — 10% de quem respondeu recusou, 0% foi
      # capturado.
      #
      # O scope `active` e quem decide o que ainda vale (linha expirada fica na tabela
      # por causa do indice unico). Numero sem ficha na base nao tem supressao e passa
      # — mesmo fail-open do ContactFlowSuppression.suppressed?.
      def suppressed_canonicals(canonicals)
        ids_by_canonical = contact_ids_by_canonical(canonicals)
        return Set.new if ids_by_canonical.empty?

        opted_out = ContactFlowSuppression.active
                                          .where(contact_id: ids_by_canonical.values.flatten,
                                                 category: SUPPRESSION_CATEGORIES)
                                          .distinct.pluck(:contact_id).to_set
        ids_by_canonical.select { |_, ids| ids.any? { |id| opted_out.include?(id) } }.keys.to_set
      end

      # canonical => [contact_ids]. Busca os contatos pelas DUAS variantes e164 do
      # numero (com e sem o 9o digito) — a ficha pode ter nascido em qualquer uma.
      def contact_ids_by_canonical(canonicals)
        @contact_ids_by_canonical ||= begin
          variants = canonicals.flat_map { |canonical| phones.e164_variants(canonical) }
          contacts_by_phone(variants).each_with_object({}) do |(id, phone), acc|
            canonical = phones.canonical_of(phone)
            (acc[canonical] ||= []) << id if canonical
          end
        end
      end

      def contacts_by_phone(variants)
        return [] if variants.empty?

        Contact.where(account_id: campaign.account_id, phone_number: variants).pluck(:id, :phone_number)
      end

      def value(row, key)
        row[key] || row[key.to_s]
      end
    end
  end
end
