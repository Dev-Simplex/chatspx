require 'rails_helper'

RSpec.describe Captain::EpisodeSegmenterService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  describe '#perform' do
    it 'segments the conversation messages into an open episode' do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing)

      expect { described_class.new(conversation: conversation).perform }
        .to change(Captain::ConversationEpisode.where(conversation_id: conversation.id), :count).by(1)

      episode = Captain::ConversationEpisode.find_by(conversation_id: conversation.id)
      expect(episode.boundary_reason).to eq('aberto')
      expect(episode.ended_at).to be_nil
      expect(episode.mensagens).to eq(2)
    end

    # GlitchTip #128: episódio órfão (conversa apagada — a tabela não tem FK nem dependent:)
    # entrega conversation: nil e estourava em #rows, matando o eval da conta inteira.
    context 'when the conversation is nil (orphan episode)' do
      it 'returns an empty list instead of raising' do
        expect { described_class.new(conversation: nil).perform }.not_to raise_error
        expect(described_class.new(conversation: nil).perform).to eq([])
      end

      it 'does not create any episode' do
        expect { described_class.new(conversation: nil).perform }
          .not_to change(Captain::ConversationEpisode, :count)
      end
    end
  end
end
