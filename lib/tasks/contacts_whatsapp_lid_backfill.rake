namespace :contacts do
  desc(
    'Backfill WhatsApp phone_number for contacts with LID. ' \
    'Usage: rake contacts:backfill_whatsapp_lid_phone[ACCOUNT_ID,DRY_RUN,BATCH_SIZE,USE_WAHA,SESSION_NAME]'
  )
  task :backfill_whatsapp_lid_phone, %i[account_id dry_run batch_size use_waha session_name] => :environment do |_task, args|
    account_id = args[:account_id].presence
    dry_run = args[:dry_run].to_s != 'false'
    batch_size = (args[:batch_size] || 200).to_i
    use_waha = args[:use_waha].to_s == 'true'
    session_name = args[:session_name].presence

    raise 'batch_size must be greater than zero' if batch_size <= 0
    raise 'account_id is required when session_name is provided' if session_name.present? && account_id.blank?

    waha_service = use_waha ? Waha::ApiService.new : nil
    sessions_cache = {}
    e164_regex = /\+[1-9]\d{1,14}\z/

    normalize_phone = lambda do |pn|
      clean_number = pn.to_s.split('@').first.to_s.gsub(/\D/, '')
      next nil if clean_number.blank?

      phone_number = "+#{clean_number}"
      normalized = Contacts::BrazilPhoneNormalizer.normalize(phone_number)
      normalized.match?(e164_regex) ? normalized : nil
    end

    phone_from_custom_attributes = lambda do |contact|
      attributes = contact.custom_attributes || {}
      jid = attributes['waha_whatsapp_jid'].presence || attributes['waha_whatsapp_chat_id'].presence
      normalize_phone.call(jid)
    end

    sessions_for_account = lambda do |id|
      if session_name.present?
        sessions_cache[id] ||= [session_name]
        next sessions_cache[id]
      end

      sessions_cache[id] ||= Inbox.where(account_id: id).where.not(waha_session_name: nil).pluck(:waha_session_name).uniq
    end

    phone_from_waha_lookup = lambda do |contact|
      return nil unless use_waha

      sessions = sessions_for_account.call(contact.account_id)
      return nil if sessions.blank?

      resolved_phone = nil
      sessions.each do |waha_session_name|
        response = waha_service.get_lid_phone_number(waha_session_name, contact.identifier)
        pn = response['pn'].presence || response[:pn].presence || response['number'].presence || response[:number].presence
        normalized = normalize_phone.call(pn)
        next if normalized.blank?

        resolved_phone = normalized
        break
      rescue Waha::ApiService::Error
        next
      end

      resolved_phone
    end

    scope = Contact.where('contacts.identifier LIKE ?', '%@lid')
    scope = scope.where(account_id: account_id) if account_id

    total_scope = scope.count
    stats = {
      total_scope: total_scope,
      inspected: 0,
      problematic: 0,
      updated: 0,
      resolved_from_custom_attributes: 0,
      resolved_from_waha: 0,
      skipped_no_resolution: 0,
      skipped_same_phone: 0,
      skipped_conflict: 0,
      flagged_conflict_candidate: 0
    }

    puts(
      "[contacts:backfill_whatsapp_lid_phone] " \
      "account_id=#{account_id || 'ALL'} " \
      "dry_run=#{dry_run} batch_size=#{batch_size} use_waha=#{use_waha} " \
      "session_name=#{session_name || 'AUTO'}"
    )
    puts "[contacts:backfill_whatsapp_lid_phone] scope=#{total_scope}"

    scope.find_in_batches(batch_size: batch_size) do |batch|
      batch.each do |contact|
        stats[:inspected] += 1

        lid_digits = contact.identifier.to_s.delete_suffix('@lid')
        placeholder_phone = lid_digits.present? ? "+#{lid_digits}" : nil
        problematic = contact.phone_number.blank? || (placeholder_phone.present? && contact.phone_number == placeholder_phone)
        next unless problematic

        stats[:problematic] += 1

        resolved_phone = phone_from_custom_attributes.call(contact)
        resolved_source = 'custom_attributes'

        if resolved_phone.blank?
          resolved_phone = phone_from_waha_lookup.call(contact)
          resolved_source = 'waha'
        end

        if resolved_phone.blank?
          stats[:skipped_no_resolution] += 1
          next
        end

        if resolved_phone == contact.phone_number
          stats[:skipped_same_phone] += 1
          next
        end

        existing_contact = Contact.where(account_id: contact.account_id, phone_number: resolved_phone)
                                  .where.not(id: contact.id)
                                  .order(last_activity_at: :desc, updated_at: :desc)
                                  .first
        if existing_contact.present?
          stats[:skipped_conflict] += 1
          puts(
            "CONFLICT contact_id=#{contact.id} account_id=#{contact.account_id} " \
            "existing_contact_id=#{existing_contact.id} " \
            "phone=#{resolved_phone.inspect} identifier=#{contact.identifier.inspect}"
          )

          unless dry_run
            custom_attributes = (contact.custom_attributes || {}).dup
            custom_attributes['waha_resolved_phone_candidate'] = resolved_phone
            custom_attributes['waha_phone_conflict_contact_id'] = existing_contact.id
            custom_attributes['waha_phone_conflict_detected_at'] = Time.zone.now.iso8601

            # rubocop:disable Rails/SkipsModelValidations
            contact.update_columns(custom_attributes: custom_attributes, updated_at: Time.zone.now)
            # rubocop:enable Rails/SkipsModelValidations
            stats[:flagged_conflict_candidate] += 1
          end
          next
        end

        if dry_run
          puts(
            "DRY_RUN contact_id=#{contact.id} account_id=#{contact.account_id} " \
            "old_phone=#{contact.phone_number.inspect} " \
            "new_phone=#{resolved_phone.inspect} " \
            "source=#{resolved_source} identifier=#{contact.identifier.inspect}"
          )
          stats[:updated] += 1
          stats[:resolved_from_custom_attributes] += 1 if resolved_source == 'custom_attributes'
          stats[:resolved_from_waha] += 1 if resolved_source == 'waha'
          next
        end

        begin
          # rubocop:disable Rails/SkipsModelValidations
          contact.update_columns(phone_number: resolved_phone, updated_at: Time.zone.now)
          # rubocop:enable Rails/SkipsModelValidations
          stats[:updated] += 1
          stats[:resolved_from_custom_attributes] += 1 if resolved_source == 'custom_attributes'
          stats[:resolved_from_waha] += 1 if resolved_source == 'waha'
        rescue ActiveRecord::RecordNotUnique
          stats[:skipped_conflict] += 1
          puts(
            "CONFLICT contact_id=#{contact.id} account_id=#{contact.account_id} " \
            "phone=#{resolved_phone.inspect} identifier=#{contact.identifier.inspect}"
          )
        end
      end
    end

    puts "[contacts:backfill_whatsapp_lid_phone] summary=#{stats}"
  end
end
