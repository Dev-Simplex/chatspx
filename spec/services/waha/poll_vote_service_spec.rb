# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Waha::PollVoteService do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_api, account: account) }
  let(:inbox) do
    inbox = channel.inbox
    inbox.update!(waha_session_name: 'nicolas')
    inbox
  end
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '556696413342@c.us') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }

  # The original outgoing poll, with the WAHA WAMID stored on source_id.
  let(:poll_message) do
    create(:message, conversation: conversation, inbox: inbox, message_type: :outgoing,
                     content: 'Está satisfeito?',
                     content_type: :input_select,
                     source_id: 'true_556696413342@c.us_POLL123',
                     content_attributes: { items: [
                       { 'title' => 'Sim', 'value' => 'sim' },
                       { 'title' => 'Não', 'value' => 'nao' }
                     ] })
  end

  def payload(vote:, poll: { 'id' => poll_message.source_id })
    { 'vote' => vote, 'poll' => poll }
  end

  describe '#perform' do
    it 'creates an incoming message with the selected option text' do
      poll_message
      described_class.new(
        session_name: 'nicolas',
        payload: payload(vote: { 'id' => 'vote-1', 'from' => '556696413342@c.us', 'selectedOptions' => ['Sim'] })
      ).perform

      msg = conversation.messages.incoming.last
      expect(msg.content).to eq('Sim')
      expect(msg.source_id).to eq('vote-1')
      expect(msg.content_attributes['poll_vote']['poll_message_id']).to eq(poll_message.id)
    end

    it 'joins multiple selected options' do
      poll_message
      described_class.new(
        session_name: 'nicolas',
        payload: payload(vote: { 'id' => 'vote-2', 'selectedOptions' => %w[Sim Não] })
      ).perform

      expect(conversation.messages.incoming.last.content).to eq('Sim, Não')
    end

    it 'resolves option objects ({name}) to their text' do
      poll_message
      described_class.new(
        session_name: 'nicolas',
        payload: payload(vote: { 'id' => 'vote-3', 'selectedOptions' => [{ 'name' => 'Não' }] })
      ).perform

      expect(conversation.messages.incoming.last.content).to eq('Não')
    end

    it 'maps a numeric/index option back to the poll title' do
      poll_message
      described_class.new(
        session_name: 'nicolas',
        payload: payload(vote: { 'id' => 'vote-4', 'selectedOptions' => ['0'] })
      ).perform

      expect(conversation.messages.incoming.last.content).to eq('Sim')
    end

    context 'when the same voter changes their answer several times' do
      it 'keeps a single answer message and updates it to the latest choice' do
        poll_message
        %w[Sim Não Sim].each_with_index do |opt, i|
          described_class.new(
            session_name: 'nicolas',
            payload: payload(vote: { 'id' => "chg-#{i}", 'from' => '55@c.us', 'selectedOptions' => [opt] })
          ).perform
        end

        votes = conversation.messages.incoming.select { |m| m.content_attributes&.dig('poll_vote') }
        expect(votes.size).to eq(1)
        expect(votes.first.content).to eq('Sim')
      end

      it 'does not re-broadcast when the resent choice is unchanged' do
        poll_message
        2.times do
          described_class.new(
            session_name: 'nicolas',
            payload: payload(vote: { 'id' => 'same-1', 'from' => '55@c.us', 'selectedOptions' => ['Sim'] })
          ).perform
        end
        msg_before = conversation.messages.incoming.last
        expect(conversation.messages.incoming.where(id: msg_before.id).count).to eq(1)
        expect(conversation.messages.incoming.select { |m| m.content_attributes&.dig('poll_vote') }.size).to eq(1)
      end
    end

    it 'keeps separate answers for different voters on the same poll' do
      poll_message
      described_class.new(session_name: 'nicolas',
                          payload: payload(vote: { 'id' => 'a', 'from' => 'aaa@c.us', 'selectedOptions' => ['Sim'] })).perform
      described_class.new(session_name: 'nicolas',
                          payload: payload(vote: { 'id' => 'b', 'from' => 'bbb@c.us', 'selectedOptions' => ['Não'] })).perform

      votes = conversation.messages.incoming.select { |m| m.content_attributes&.dig('poll_vote') }
      expect(votes.size).to eq(2)
    end

    it 'is idempotent on repeated deliveries of the same vote id' do
      poll_message
      2.times do
        described_class.new(
          session_name: 'nicolas',
          payload: payload(vote: { 'id' => 'vote-dup', 'selectedOptions' => ['Sim'] })
        ).perform
      end

      expect(conversation.messages.incoming.where(source_id: 'vote-dup').count).to eq(1)
    end

    it 'does nothing when the poll message is unknown' do
      expect do
        described_class.new(
          session_name: 'nicolas',
          payload: payload(vote: { 'id' => 'v', 'selectedOptions' => ['Sim'] }, poll: { 'id' => 'unknown-wamid' })
        ).perform
      end.not_to change(Message, :count)
    end

    it 'does nothing when no option was selected' do
      poll_message
      expect do
        described_class.new(
          session_name: 'nicolas',
          payload: payload(vote: { 'id' => 'v', 'selectedOptions' => [] })
        ).perform
      end.not_to change(conversation.messages.incoming, :count)
    end

    it 'matches by message-id suffix when the vote references the poll via @lid (different chat prefix)' do
      poll_message # stored source_id: true_556696413342@c.us_POLL123
      described_class.new(
        session_name: 'nicolas',
        payload: payload(
          vote: { 'id' => 'vote-lid', 'selectedOptions' => ['Sim'] },
          poll: { 'id' => 'true_91792259199205@lid_POLL123' }
        )
      ).perform

      msg = conversation.messages.incoming.last
      expect(msg.content).to eq('Sim')
      expect(msg.content_attributes['poll_vote']['poll_message_id']).to eq(poll_message.id)
    end

    it 'falls back to pollCreationMessageKey.ID from raw _data for the message id' do
      poll_message
      described_class.new(
        session_name: 'nicolas',
        payload: {
          'vote' => { 'id' => 'vote-raw', 'selectedOptions' => ['Não'] },
          'poll' => { 'id' => 'true_unknown@lid_NOPE' },
          '_data' => { 'Message' => { 'pollUpdateMessage' => { 'pollCreationMessageKey' => { 'ID' => 'POLL123' } } } }
        }
      ).perform

      expect(conversation.messages.incoming.last.content).to eq('Não')
    end

    it 'reads the poll id when nested under the vote' do
      poll_message
      described_class.new(
        session_name: 'nicolas',
        payload: { 'vote' => { 'id' => 'vote-5', 'selectedOptions' => ['Sim'], 'poll' => { 'id' => poll_message.source_id } } }
      ).perform

      expect(conversation.messages.incoming.last.content).to eq('Sim')
    end
  end
end
