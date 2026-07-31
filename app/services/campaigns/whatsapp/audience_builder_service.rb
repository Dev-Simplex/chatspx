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
    # CHAVE CANONICA = DDD + ultimos 8 digitos. E o que colapsa as variantes do 9o
    # digito e do DDI: `+5566992927211`, `+556692927211` e `66 9929-2721` sao a
    # MESMA pessoa. Deduplicar pela string e164 (como era antes) deixaria os tres
    # passarem como tres destinatarios e o lead levaria o disparo em triplicata.
    class AudienceBuilderService
      # Motivos de descarte, na ordem em que sao avaliados. Chaves estaveis: viram
      # rotulo na tela e coluna no CSV de revisao.
      REASONS = %w[
        telefone_invalido telefone_fixo numero_suspeito bloqueado
        ja_disparado ja_na_campanha atendimento_ativo duplicado_na_lista
      ].freeze

      DDDS = %w[
        11 12 13 14 15 16 17 18 19 21 22 24 27 28 31 32 33 34 35 37 38
        41 42 43 44 45 46 47 48 49 51 53 54 55 61 62 63 64 65 66 67 68
        69 71 73 74 75 77 79 81 82 83 84 85 86 87 88 89 91 92 93 94 95
        96 97 98 99
      ].freeze

      # Assinante de 8 digitos comecando em 2-5 e telefone FIXO: nao recebe
      # WhatsApp, e acrescentar o 9o digito produz um celular que nao existe.
      LANDLINE_PREFIXES = %w[2 3 4 5].freeze

      # Mesmo digito 7+ vezes seguidas ("66999999999"): preenchimento de formulario
      # pra escapar de campo obrigatorio, nunca um numero real.
      SUSPICIOUS = /(\d)\1{6,}/

      # Conversa nao-resolvida = atendimento em andamento. Disparo nao atropela.
      ACTIVE_STATUSES = %i[open pending snoozed].freeze

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

        ddd, subscriber = split_number(raw)
        return entry.merge(reason: 'telefone_invalido') if ddd.nil?
        return entry.merge(reason: 'telefone_fixo') if landline?(subscriber)
        return entry.merge(reason: 'numero_suspeito') if "#{ddd}#{subscriber}".match?(SUSPICIOUS)

        entry.merge(canonical: "#{ddd}#{subscriber[-8..]}", phone: e164(ddd, subscriber))
      end

      # Devolve [ddd, assinante] do numero brasileiro, ou nil quando irrecuperavel.
      def split_number(raw)
        digits = recover(raw.to_s.gsub(/\D/, ''))
        return nil unless digits.length.between?(10, 11)

        ddd = digits[0, 2]
        DDDS.include?(ddd) ? [ddd, digits[2..]] : nil
      end

      # As tres formas erradas que as listas reais trazem (ver ingestao_*.py), na
      # ordem em que precisam ser desfeitas.
      def recover(digits)
        prefix_default_ddd(strip_country_code(strip_trunk_zero(digits)))
      end

      # Zero de tronco da discagem nacional: "066 9929-2721".
      def strip_trunk_zero(digits)
        digits.start_with?('0') && digits.length.between?(11, 12) ? digits[1..] : digits
      end

      # DDI colado no numero: "5566992927211".
      def strip_country_code(digits)
        digits.start_with?('55') && digits.length >= 12 ? digits[2..] : digits
      end

      # Numero sem DDD ("99292721"): so da pra recuperar quando a campanha declara
      # a regiao — sem isso nao ha como adivinhar de onde e o numero.
      def prefix_default_ddd(digits)
        return digits if default_ddd.blank? || !digits.length.between?(8, 9)

        "#{default_ddd}#{digits}"
      end

      def landline?(subscriber)
        subscriber.length == 8 && LANDLINE_PREFIXES.include?(subscriber[0])
      end

      # Assinante de 8 digitos e celular legado: ganha o 9o digito. Sem isso a
      # maioria das listas (que chegam em 8 digitos) falha como inexistente.
      def e164(ddd, subscriber)
        subscriber = "9#{subscriber}" if subscriber.length == 8
        "+55#{ddd}#{subscriber}"
      end

      def default_ddd
        @default_ddd ||= campaign.dispatch_config['default_ddd'].to_s.gsub(/\D/, '')
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
        blocked = Set.new(Array(blocklist_phones).filter_map { |raw| canonical_of(raw) })
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

      # canonical => [contact_ids]. Busca os contatos pelas DUAS variantes e164 do
      # numero (com e sem o 9o digito) — a ficha pode ter nascido em qualquer uma.
      def contact_ids_by_canonical(canonicals)
        @contact_ids_by_canonical ||= begin
          variants = canonicals.flat_map { |canonical| e164_variants(canonical) }
          contacts_by_phone(variants).each_with_object({}) do |(id, phone), acc|
            canonical = canonical_of(phone)
            (acc[canonical] ||= []) << id if canonical
          end
        end
      end

      def contacts_by_phone(variants)
        return [] if variants.empty?

        Contact.where(account_id: campaign.account_id, phone_number: variants).pluck(:id, :phone_number)
      end

      def e164_variants(canonical)
        ddd = canonical[0, 2]
        subscriber = canonical[2..]
        ["+55#{ddd}#{subscriber}", "+55#{ddd}9#{subscriber}"]
      end

      def canonical_of(raw)
        ddd, subscriber = split_number(raw)
        ddd && "#{ddd}#{subscriber[-8..]}"
      end

      def value(row, key)
        row[key] || row[key.to_s]
      end
    end
  end
end
