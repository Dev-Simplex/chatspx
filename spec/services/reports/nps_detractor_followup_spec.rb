require 'rails_helper'

RSpec.describe Reports::NpsDetractorFollowup do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  def detractor_scope
    account.nps_responses.where(status: :responded).where.not(score: nil)
  end

  it 'reports zeros when there are no detractors' do
    create(:conversation, account: account, inbox: inbox).tap do |conv|
      create(:nps_response, conversation: conv, score: 10, status: :responded, answered_at: Time.current)
    end
    result = described_class.new(detractor_scope).to_h
    expect(result[:total]).to eq(0)
    expect(result[:avg_followup_seconds]).to be_nil
  end

  it 'counts a detractor with a later agent reply as followed up and averages the latency' do
    conv = create(:conversation, account: account, inbox: inbox, status: :open)
    answered = 1.hour.ago
    create(:nps_response, conversation: conv, score: 3, status: :responded, answered_at: answered)
    create(:message, account: account, inbox: inbox, conversation: conv,
                     message_type: :outgoing, content: 'Oi, vamos resolver', created_at: answered + 600)

    result = described_class.new(detractor_scope).to_h
    expect(result[:total]).to eq(1)
    expect(result[:followed_up_count]).to eq(1)
    expect(result[:awaiting_count]).to eq(0)
    expect(result[:avg_followup_seconds]).to be_within(2).of(600)
  end

  it 'counts a detractor with no later agent reply as awaiting' do
    conv = create(:conversation, account: account, inbox: inbox, status: :open)
    create(:nps_response, conversation: conv, score: 2, status: :responded, answered_at: 1.hour.ago)

    result = described_class.new(detractor_scope).to_h
    expect(result[:total]).to eq(1)
    expect(result[:followed_up_count]).to eq(0)
    expect(result[:awaiting_count]).to eq(1)
  end

  it 'ignores the NPS survey thank-you (skip_signature) message as a follow-up' do
    conv = create(:conversation, account: account, inbox: inbox, status: :open)
    answered = 1.hour.ago
    create(:nps_response, conversation: conv, score: 4, status: :responded, answered_at: answered)
    create(:message, account: account, inbox: inbox, conversation: conv,
                     message_type: :outgoing, content: 'Obrigado!', created_at: answered + 5,
                     content_attributes: { skip_signature: true })

    result = described_class.new(detractor_scope).to_h
    expect(result[:awaiting_count]).to eq(1)
    expect(result[:followed_up_count]).to eq(0)
  end

  context 'with a detractor awaiting a human reply' do
    let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :open) }
    let(:answered_at) { 1.hour.ago }

    before do
      create(:nps_response, conversation: conversation, score: 3, status: :responded, answered_at: answered_at)
    end

    ['Captain::Assistant', 'AgentBot', nil].each do |sender_type|
      it "ignores outgoing messages from #{sender_type || 'automation without a sender'}" do
        message = create(:message, conversation: conversation, account: account, inbox: inbox,
                                   message_type: :outgoing, created_at: answered_at + 60)
        sender = case sender_type
                 when 'Captain::Assistant' then create(:captain_assistant, account: account)
                 when 'AgentBot' then create(:agent_bot)
                 end
        message.update!(sender: sender)

        result = described_class.new(detractor_scope).to_h
        expect(result[:followed_up_count]).to eq(0)
        expect(result[:awaiting_count]).to eq(1)
      end
    end

    it 'ignores the survey even when it has a human sender' do
      create(:message, conversation: conversation, account: account, inbox: inbox,
                       message_type: :outgoing, created_at: answered_at + 60, content_attributes: { nps_survey: true })

      expect(described_class.new(detractor_scope).to_h[:awaiting_count]).to eq(1)
    end

    it 'counts a human reply from another team regardless of the viewer' do
      team = create(:team, account: account)
      other_team = create(:team, account: account)
      inbox.update!(team_message_isolation: true)
      conversation.update!(team: other_team)
      reply = create(:message, conversation: conversation, account: account, inbox: inbox,
                               message_type: :outgoing, created_at: answered_at + 600)
      conversation.update!(team: team)
      viewer = create(:user, account: account)

      allow(Current).to receive(:user).and_return(viewer)
      expect(conversation.reload.messages).not_to include(reply)
      result = described_class.new(detractor_scope).to_h
      expect(result[:followed_up_count]).to eq(1)
      expect(result[:awaiting_count]).to eq(0)
      expect(result[:avg_followup_seconds]).to be_within(2).of(600)
    end

    it 'reports the full cohort total when the scan is truncated' do
      limit = described_class::SCAN_LIMIT
      create_list(:nps_response, limit, :detractor, conversation: conversation, answered_at: answered_at)

      result = described_class.new(detractor_scope).to_h
      expect(result[:total]).to eq(limit + 1)
      expect(result[:awaiting_count]).to eq(limit)
      expect(result[:followed_up_count]).to eq(0)
      expect(result[:scan_truncated]).to be(true)
    end
  end
end
