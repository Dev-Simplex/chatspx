namespace :contacts do
  desc(
    'Merge duplicate contacts by phone. Keeps the contact with the most recent conversation. ' \
    'Usage: rake contacts:merge_duplicate_phone_contacts[ACCOUNT_ID|all,DRY_RUN,BATCH_SIZE,PHONE]'
  )
  task :merge_duplicate_phone_contacts, %i[account_id dry_run batch_size phone] => :environment do |_task, args|
    account_id_arg = args[:account_id].to_s.strip
    dry_run = args[:dry_run].to_s != 'false'
    batch_size = (args[:batch_size] || 200).to_i
    phone_filter = args[:phone].presence
    raise 'batch_size must be greater than zero' if batch_size <= 0

    duplicate_account_ids = duplicate_phone_account_ids(phone_filter: phone_filter)
    accounts = if account_id_arg.present? && account_id_arg.downcase != 'all'
                 account_id = account_id_arg.to_i
                 raise 'account_id is required' if account_id <= 0

                 [Account.find(account_id)]
               else
                 Account.where(id: duplicate_account_ids).order(:id).to_a
               end

    raise 'no accounts with duplicate phones found for the given filter' if accounts.blank?

    global_stats = {
      accounts: accounts.size,
      duplicate_phone_groups: 0,
      processed_groups: 0,
      merged_contacts: 0,
      skipped_contacts: 0,
      errors: 0
    }

    puts(
      '[contacts:merge_duplicate_phone_contacts] ' \
      "account_scope=#{account_id_arg.presence || 'all'} dry_run=#{dry_run} " \
      "batch_size=#{batch_size} phone_filter=#{phone_filter || 'ALL'} accounts=#{accounts.size}"
    )

    accounts.each do |account|
      account_stats = merge_duplicate_phone_contacts_for_account(
        account: account,
        dry_run: dry_run,
        batch_size: batch_size,
        phone_filter: phone_filter
      )

      global_stats.keys.each do |key|
        next if key == :accounts

        global_stats[key] += account_stats[key]
      end
    end

    puts "[contacts:merge_duplicate_phone_contacts] global_summary=#{global_stats}"
  end

  def duplicate_phone_account_ids(phone_filter: nil)
    scope = Contact.where.not(phone_number: [nil, ''])
    scope = scope.where(phone_number: phone_filter) if phone_filter.present?

    scope.group(:account_id, :phone_number)
         .having('COUNT(*) > 1')
         .pluck(:account_id)
         .uniq
  end

  def merge_duplicate_phone_contacts_for_account(account:, dry_run:, batch_size:, phone_filter: nil)
    scope = Contact.where(account_id: account.id).where.not(phone_number: [nil, ''])
    scope = scope.where(phone_number: phone_filter) if phone_filter.present?

    duplicate_phones = scope.group(:phone_number).having('COUNT(*) > 1').pluck(:phone_number)
    stats = {
      duplicate_phone_groups: duplicate_phones.size,
      processed_groups: 0,
      merged_contacts: 0,
      skipped_contacts: 0,
      errors: 0
    }

    puts(
      '[contacts:merge_duplicate_phone_contacts] ' \
      "account_id=#{account.id} dry_run=#{dry_run} batch_size=#{batch_size} " \
      "phone_filter=#{phone_filter || 'ALL'} duplicate_groups=#{stats[:duplicate_phone_groups]}"
    )

    duplicate_phones.each_slice(batch_size) do |phones_batch|
      grouped_contacts = Contact.where(account_id: account.id, phone_number: phones_batch)
                                .to_a
                                .group_by(&:phone_number)
      conversation_stats = load_conversation_stats(grouped_contacts)

      grouped_contacts.each do |phone, contacts|
        next if contacts.size < 2

        stats[:processed_groups] += 1
        primary_contact, mergee_contacts = pick_primary_and_mergees(contacts, conversation_stats)
        puts(
          "GROUP account_id=#{account.id} phone=#{phone.inspect} primary_contact_id=#{primary_contact.id} " \
          "mergee_ids=#{mergee_contacts.map(&:id).join(',')}"
        )

        mergee_contacts.each do |mergee_contact|
          if dry_run
            stats[:merged_contacts] += 1
            next
          end

          begin
            ContactMergeAction.new(
              account: account,
              base_contact: primary_contact,
              mergee_contact: mergee_contact
            ).perform
            primary_contact.reload
            stats[:merged_contacts] += 1
          rescue StandardError => e
            stats[:errors] += 1
            stats[:skipped_contacts] += 1
            puts(
              "ERROR account_id=#{account.id} phone=#{phone.inspect} base_contact_id=#{primary_contact.id} " \
              "mergee_contact_id=#{mergee_contact.id} error=#{e.class}: #{e.message}"
            )
          end
        end
      end
    end

    puts "[contacts:merge_duplicate_phone_contacts] account_id=#{account.id} summary=#{stats}"
    stats
  end

  def load_conversation_stats(grouped_contacts)
    contact_ids = grouped_contacts.values.flatten.map(&:id)
    return {} if contact_ids.blank?

    stats = {}
    Conversation.where(contact_id: contact_ids)
                .group(:contact_id)
                .pluck(:contact_id, Arel.sql('MAX(last_activity_at)'), Arel.sql('COUNT(*)'))
                .each do |contact_id, latest_activity_at, total_conversations|
      stats[contact_id] = {
        latest_activity_at: latest_activity_at,
        total_conversations: total_conversations.to_i
      }
    end
    stats
  end

  def pick_primary_and_mergees(contacts, conversation_stats)
    ranked_contacts = contacts.sort_by do |contact|
      stats = conversation_stats[contact.id] || {}
      latest_activity_at = stats[:latest_activity_at] || contact.last_activity_at || Time.zone.at(0)
      total_conversations = stats[:total_conversations] || 0
      [latest_activity_at, total_conversations, contact.updated_at || Time.zone.at(0), contact.id]
    end.reverse

    [ranked_contacts.first, ranked_contacts.drop(1)]
  end
end
