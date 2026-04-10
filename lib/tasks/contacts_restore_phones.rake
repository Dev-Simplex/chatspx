namespace :contacts do # rubocop:disable Metrics/BlockLength
  desc 'Restaura phone_number apagado pelo bug do ContactForm (sidebar de conversa). ' \
       'Fontes: journal do systemd + contact_inboxes.source_id. DRY_RUN=true por padrao.'
  task restore_phones: :environment do # rubocop:disable Metrics/BlockLength
    dry_run    = ENV['DRY_RUN'] != 'false'
    account_id = ENV['ACCOUNT_ID']&.to_i
    journal_file = ENV['JOURNAL_TSV'] || '/tmp/recoverable_from_journal.tsv'

    puts '=' * 60
    puts "[#{dry_run ? 'DRY-RUN' : 'EXECUTANDO'}] Restore phone_number"
    puts "  account_id filter: #{account_id || 'todas'}"
    puts "  journal file:      #{journal_file}"
    puts '=' * 60

    # --- Monta o mapa {contact_id => phone_number_original} ---
    resolved = {}

    # Fonte A: journal do systemd (TSV: "contact_id\tphone_number")
    if File.exist?(journal_file)
      File.foreach(journal_file) do |line|
        next if line.start_with?('contact_id')

        cid, phone = line.strip.split("\t", 2)
        next if cid.nil? || phone.to_s.empty?

        resolved[cid.to_i] ||= { phone: phone, source: 'journal' }
      end
      puts "Fonte journal: #{resolved.size} contatos"
    else
      puts "Fonte journal: arquivo nao encontrado, pulando (#{journal_file})"
    end

    # Fonte B: contact_inboxes de canais Whatsapp oficial (source_id = telefone)
    whatsapp_scope = Contact.joins(contact_inboxes: :inbox)
                            .where(phone_number: [nil, ''])
                            .where(inboxes: { channel_type: 'Channel::Whatsapp' })
                            .where.not(contact_inboxes: { source_id: [nil, ''] })
                            .distinct
    whatsapp_scope = whatsapp_scope.where(account_id: account_id) if account_id

    added_wa = 0
    whatsapp_scope.find_each do |contact|
      next if resolved.key?(contact.id)

      ci = contact.contact_inboxes.joins(:inbox)
                  .where(inboxes: { channel_type: 'Channel::Whatsapp' })
                  .where.not(source_id: [nil, '']).first
      next unless ci

      raw = ci.source_id.to_s.gsub(/\D/, '')
      next if raw.empty?

      resolved[contact.id] = { phone: "+#{raw}", source: 'whatsapp_source_id' }
      added_wa += 1
    end
    puts "Fonte whatsapp_source_id: +#{added_wa} contatos"

    # Fonte C: WAHA JID em custom_attributes
    jid_scope = Contact.where(phone_number: [nil, ''])
                       .where("custom_attributes->>'waha_whatsapp_jid' LIKE ?", '%@c.us')
    jid_scope = jid_scope.where(account_id: account_id) if account_id

    added_jid = 0
    jid_scope.find_each do |contact|
      next if resolved.key?(contact.id)

      jid = contact.custom_attributes['waha_whatsapp_jid']
      raw = jid.to_s.split('@').first.to_s.gsub(/\D/, '')
      next if raw.empty?

      resolved[contact.id] = { phone: "+#{raw}", source: 'waha_jid' }
      added_jid += 1
    end
    puts "Fonte waha_jid: +#{added_jid} contatos"
    puts "Total candidatos: #{resolved.size}"
    puts

    # --- Aplica no banco ---
    stats = Hash.new(0)
    resolved.each do |cid, data| # rubocop:disable Metrics/BlockLength
      stats[:total] += 1
      contact = Contact.find_by(id: cid)
      unless contact
        stats[:skipped_not_found] += 1
        next
      end

      if account_id && contact.account_id != account_id
        stats[:skipped_account_filter] += 1
        next
      end

      unless contact.phone_number.to_s.empty?
        stats[:skipped_already_has_phone] += 1
        next
      end

      phone = Contacts::BrazilPhoneNormalizer.normalize(data[:phone].to_s)
      unless phone&.match?(/\A\+[1-9]\d{1,14}\z/)
        stats[:skipped_invalid_format] += 1
        puts "INVALIDO id=#{cid} phone=#{data[:phone].inspect} normalized=#{phone.inspect}"
        next
      end

      if Contact.where(account_id: contact.account_id, phone_number: phone)
                .where.not(id: contact.id).exists?
        stats[:skipped_conflict] += 1
        puts "CONFLITO id=#{cid} phone=#{phone} (outro contato ja usa)"
        next
      end

      if dry_run
        puts "[DRY] id=#{cid} account=#{contact.account_id} name=#{contact.name.to_s.truncate(40)} " \
             "-> #{phone} (fonte=#{data[:source]})"
      else
        # Intencional: pula callbacks/validacoes para nao re-normalizar nem disparar
        # eventos de contact.updated em massa durante o backfill.
        contact.update_columns(phone_number: phone, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        puts "OK    id=#{cid} account=#{contact.account_id} -> #{phone} (fonte=#{data[:source]})"
      end
      stats[:restored] += 1
    end

    puts
    puts '=' * 60
    puts "[#{dry_run ? 'DRY-RUN' : 'EXECUTADO'}] Resultado:"
    stats.each { |k, v| puts "  #{k}: #{v}" }
    puts '=' * 60
  end
end
