# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InternalMessages::NoteMentionService do
  let(:account) { create(:account) }
  let(:author) { create(:user, account: account, role: :agent, name: 'Misya') }
  let(:colleague) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account) }
  let(:note) do
    create(:message, conversation: conversation, account: account, inbox: conversation.inbox, sender: author, private: true,
                     message_type: :outgoing, content: "Oi [@Ana](mention://user/#{colleague.id}/Ana), olha isso")
  end

  before { account.enable_features!('internal_chat') }

  def dm_messages
    InternalChannels::FindOrCreateDmService.new(account: account, user: author, other_user: colleague).perform.messages
  end

  it 'posts the note excerpt with the conversation card in the DM' do
    described_class.new(message: note, user_ids: [colleague.id]).perform

    posted = dm_messages.last
    expect(posted.user).to eq(author)
    expect(posted.shared_conversation).to eq(conversation)
    expect(posted.content).to include("##{conversation.display_id}", '@Ana, olha isso')
  end

  it 'does not duplicate when the same note is processed again' do
    2.times { described_class.new(message: note, user_ids: [colleague.id]).perform }

    expect(dm_messages.count).to eq(1)
  end

  it 'skips the author mentioning themselves' do
    described_class.new(message: note, user_ids: [author.id]).perform

    expect(account.internal_channels.count).to eq(0)
  end

  it 'does nothing when the internal chat is off for the account' do
    account.disable_features!('internal_chat')
    described_class.new(message: note, user_ids: [colleague.id]).perform

    expect(account.internal_channels.count).to eq(0)
  end
end
