# frozen_string_literal: true

namespace :private_chat do
  desc 'Create private chat inbox, contact and conversation for account 6 (or ACCOUNT_ID). Set PRIVATE_CHAT_PASSWORD in ENV.'
  task setup: :environment do
    account_id = ENV.fetch('ACCOUNT_ID', '6').to_i
    account = Account.find_by(id: account_id)
    unless account
      puts "Account with id #{account_id} not found."
      exit 1
    end

    if PrivateChat::Config.enabled?
      puts "Private chat already configured (PRIVATE_CHAT_CONVERSATION_ID is set). Skipping."
      puts "  PRIVATE_CHAT_CONVERSATION_ID=#{PrivateChat::Config.conversation_id}"
      puts "  PRIVATE_CHAT_INBOX_ID=#{PrivateChat::Config.inbox_id}"
      exit 0
    end

    channel = Channel::Api.create!(account: account)
    inbox = Inbox.create!(
      account: account,
      channel: channel,
      name: 'Notas'
    )
    contact = Contact.create!(
      account: account,
      name: 'Sistema',
      email: "private-chat-#{SecureRandom.hex(8)}@internal.chatwoot"
    )
    contact_inbox = ContactInboxBuilder.new(
      contact: contact,
      inbox: inbox,
      source_id: "private_chat_#{SecureRandom.uuid}"
    ).perform
    conversation = Conversation.create!(
      account_id: account.id,
      inbox_id: inbox.id,
      contact_id: contact.id,
      contact_inbox_id: contact_inbox.id,
      status: :open
    )

    puts 'Private chat setup complete.'
    puts 'Coloque os IDs abaixo em app/services/private_chat/config.rb'
    puts "  HARDCODED_CONVERSATION_ID = #{conversation.id}"
    puts "  HARDCODED_INBOX_ID = #{inbox.id}"
    puts "  (HARDCODED_PASSWORD e HARDCODED_ACCOUNT_ID já têm padrão.)"
    puts ''
    puts "URL de acesso: /app/accounts/#{account.id}/notes"
  end
end
