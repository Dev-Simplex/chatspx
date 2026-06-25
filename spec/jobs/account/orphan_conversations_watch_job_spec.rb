require 'rails_helper'

RSpec.describe Account::OrphanConversationsWatchJob do
  subject(:job) { described_class.perform_later }

  let!(:account_with_gate) { create(:account, settings: { reply_assignment_gate: true }) }
  let!(:account_without_gate) { create(:account) }
  let!(:account_with_gate_off) { create(:account, settings: { reply_assignment_gate: false }) }

  it 'enqueues the job on the scheduled_jobs queue' do
    expect { job }.to have_enqueued_job(described_class)
      .on_queue('scheduled_jobs')
  end

  it 'fans out Conversations::OrphanRetriageJob only for accounts with reply_assignment_gate ON' do
    expect(Conversations::OrphanRetriageJob).to receive(:perform_later).with(account_with_gate).once
    expect(Conversations::OrphanRetriageJob).not_to receive(:perform_later).with(account_without_gate)
    expect(Conversations::OrphanRetriageJob).not_to receive(:perform_later).with(account_with_gate_off)

    described_class.perform_now
  end
end
