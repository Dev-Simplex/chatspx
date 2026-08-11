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

        ddd, subscriber = phones.split_number(raw)
        return entry.merge(reason: 'telefone_invalido') if ddd.nil?
        return entry.merge(reason: 'telefone_fixo') if phones.landline?(subscriber)
        return entry.merge(reason: 'numero_suspeito') if phones.suspicious?(ddd, subscriber)

        entry.merge(canonical: phones.canonical(ddd, subscriber), phone: phones.e164(ddd, subscriber))
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

      def dispatched_canonicals(canonicals)
        return Set.new if canonicals.empty?

        CampaignRecipient.where(account_id: campaign.account_id, status: DISPATCHED_STATUSES)
                         .where(canonical_phone: canonicals)
                         .where.not(campaign_id: campaign.id)
                         .distinct.pluck(:canonical_phone).to_set
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

      # Quem respondeu PARAR. A supressao ja era escrita pelo handler de opt-out e ja
      # era respeitada pelo motor de Flows; o disparo em massa nao a consultava e
      # continuava batendo em quem pediu pra sair. O scope `active` e quem decide o
      # que ainda vale (linha expirada fica na tabela por causa do indice unico).
      # Numero sem ficha na base nao tem supressao e passa — mesmo fail-open do
      # ContactFlowSuppression.suppressed?.
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
