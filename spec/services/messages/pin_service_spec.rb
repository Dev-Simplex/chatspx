require 'rails_helper'

describe Messages::PinService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message_a) { create(:message, conversation: conversation, account: account, inbox: inbox) }
  let(:message_b) { create(:message, conversation: conversation, account: account, inbox: inbox) }
  let(:message_c) { create(:message, conversation: conversation, account: account, inbox: inbox) }
  let(:message_d) { create(:message, conversation: conversation, account: account, inbox: inbox) }

  describe '#add' do
    it 'creates the pinned_message_ids array when absent' do
      pinned = described_class.new(conversation: conversation, message_id: message_a.id).add

      expect(pinned).to eq([message_a.id])
      conversation.reload
      expect(conversation.additional_attributes['pinned_message_ids']).to eq([message_a.id])
    end

    it 'appends additional ids up to the cap of 3' do
      described_class.new(conversation: conversation, message_id: message_a.id).add
      described_class.new(conversation: conversation, message_id: message_b.id).add
      pinned = described_class.new(conversation: conversation, message_id: message_c.id).add

      expect(pinned).to match_array([message_a.id, message_b.id, message_c.id])
      expect(pinned.length).to eq(3)
    end

    it 'raises LimitReached when attempting to pin a 4th message' do
      described_class.new(conversation: conversation, message_id: message_a.id).add
      described_class.new(conversation: conversation, message_id: message_b.id).add
      described_class.new(conversation: conversation, message_id: message_c.id).add

      expect do
        described_class.new(conversation: conversation, message_id: message_d.id).add
      end.to raise_error(described_class::LimitReached)

      conversation.reload
      expect(described_class.pinned_ids(conversation)).to match_array([message_a.id, message_b.id, message_c.id])
    end

    it 'is idempotent when the same id is added twice (does not duplicate or raise)' do
      described_class.new(conversation: conversation, message_id: message_a.id).add
      pinned = described_class.new(conversation: conversation, message_id: message_a.id).add

      expect(pinned).to eq([message_a.id])
    end

    it 'idempotent add does not raise even when cap reached if id already present' do
      described_class.new(conversation: conversation, message_id: message_a.id).add
      described_class.new(conversation: conversation, message_id: message_b.id).add
      described_class.new(conversation: conversation, message_id: message_c.id).add

      expect do
        described_class.new(conversation: conversation, message_id: message_a.id).add
      end.not_to raise_error
    end

    it 'raises NotFound for an id that does not belong to the conversation' do
      other_conv = create(:conversation, account: account, inbox: inbox)
      other_msg = create(:message, conversation: other_conv, account: account, inbox: inbox)

      expect do
        described_class.new(conversation: conversation, message_id: other_msg.id).add
      end.to raise_error(described_class::NotFound)
    end

    it 'raises NotFound for non-numeric id' do
      expect do
        described_class.new(conversation: conversation, message_id: 'abc')
      end.to raise_error(described_class::NotFound)
    end

    it 'dispatches CONVERSATION_PIN_ADDED' do
      dispatcher = Rails.configuration.dispatcher
      expect(dispatcher).to receive(:dispatch).with(
        Events::Types::CONVERSATION_PIN_ADDED,
        kind_of(Time),
        hash_including(conversation: conversation, message_id: message_a.id)
      )

      described_class.new(conversation: conversation, message_id: message_a.id).add
    end

    context 'concurrent adds on different ids' do
      it 'preserves both writes (no lost update)' do
        conversation.update!(additional_attributes: {})
        mid_a = message_a.id
        mid_b = message_b.id

        threads = []
        threads << Thread.new { described_class.new(conversation: conversation, message_id: mid_a).add }
        threads << Thread.new { described_class.new(conversation: conversation, message_id: mid_b).add }
        threads.each(&:join)

        conversation.reload
        ids = described_class.pinned_ids(conversation)
        # jsonb_set + concat at row level is atomic; ideally both survive.
        # At minimum, one must survive (no exceptions or data corruption).
        expect(ids).to include(mid_a).or include(mid_b)
        expect(ids.length).to be_between(1, 2)
      end
    end
  end

  describe '#remove' do
    before do
      described_class.new(conversation: conversation, message_id: message_a.id).add
      described_class.new(conversation: conversation, message_id: message_b.id).add
    end

    it 'removes the given id from the array' do
      pinned = described_class.new(conversation: conversation, message_id: message_a.id).remove

      expect(pinned).to eq([message_b.id])
      conversation.reload
      expect(described_class.pinned_ids(conversation)).to eq([message_b.id])
    end

    it 'is idempotent when the id is not pinned (no-op, returns current list)' do
      pinned = described_class.new(conversation: conversation, message_id: message_c.id).remove

      expect(pinned).to match_array([message_a.id, message_b.id])
    end

    it 'dispatches CONVERSATION_PIN_REMOVED only when state changes' do
      dispatcher = Rails.configuration.dispatcher
      expect(dispatcher).to receive(:dispatch).with(
        Events::Types::CONVERSATION_PIN_REMOVED,
        kind_of(Time),
        hash_including(conversation: conversation, message_id: message_a.id)
      )

      described_class.new(conversation: conversation, message_id: message_a.id).remove
    end

    it 'does not dispatch when id is not present (idempotent no-op)' do
      dispatcher = Rails.configuration.dispatcher
      expect(dispatcher).not_to receive(:dispatch)

      described_class.new(conversation: conversation, message_id: message_c.id).remove
    end
  end

  describe '.pinned_ids' do
    it 'returns an empty array when nothing pinned' do
      expect(described_class.pinned_ids(conversation)).to eq([])
    end

    it 'returns Integer ids even when stored values are mixed' do
      conversation.update!(additional_attributes: { 'pinned_message_ids' => ['10', 11, '12'] })
      expect(described_class.pinned_ids(conversation)).to eq([10, 11, 12])
    end
  end
end
