# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Conversations::ListPreloader do
  let!(:account) { create(:account) }
  let!(:agent_a) { create(:user, account: account, role: :agent) }
  let!(:agent_b) { create(:user, account: account, role: :agent) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox) }

  # presença de uma msg pública no meio garante que o filtro não a descarta nem quebra a ordenação
  let!(:public_msg) do # rubocop:disable RSpec/LetSetup
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, content: 'public hi')
  end
  let!(:from_a) do
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, sender: agent_a,
                     content: 'from A')
  end
  let!(:from_b) do
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, sender: agent_b,
                     content: 'from B')
  end

  after { Current.user = nil }

  describe 'last message preview with agent_message_isolation' do
    context 'when isolation is enabled' do
      before { inbox.update!(agent_message_isolation: true) }

      it 'previews the last message visible to the viewing agent (hides other agents)' do
        result = described_class.call([conversation], user: agent_a)
        preview = result.last_non_activity_messages[conversation.id]
        # from_b is the real latest, but it belongs to agent_b -> hidden for agent_a
        expect(preview.id).to eq(from_a.id)
      end

      it 'previews the real last message for an administrator' do
        result = described_class.call([conversation], user: admin)
        expect(result.last_non_activity_messages[conversation.id].id).to eq(from_b.id)
      end

      it 'previews the real last message when there is no viewer (default Current.user nil)' do
        result = described_class.call([conversation], user: nil)
        expect(result.last_non_activity_messages[conversation.id].id).to eq(from_b.id)
      end
    end

    context 'when isolation is disabled' do
      it 'previews the real last message even for a non-admin agent' do
        result = described_class.call([conversation], user: agent_a)
        expect(result.last_non_activity_messages[conversation.id].id).to eq(from_b.id)
      end
    end
  end
end
