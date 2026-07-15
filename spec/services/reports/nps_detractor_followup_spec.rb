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
end
