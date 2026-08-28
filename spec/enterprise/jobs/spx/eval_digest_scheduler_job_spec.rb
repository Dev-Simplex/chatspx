require 'rails_helper'

RSpec.describe Spx::EvalDigestSchedulerJob do
  it 'enqueues only for accounts that opted in' do
    pediu = create(:account, custom_attributes: { 'eval_digest' => { 'enabled' => true } })
    create(:account)
    create(:account, custom_attributes: { 'eval_digest' => { 'enabled' => false } })
    create(:account, custom_attributes: { 'outra_coisa' => true })

    expect { described_class.perform_now }.to have_enqueued_job(Spx::EvalDigestJob).with(pediu).exactly(:once)
  end

  it 'does nothing when no account opted in' do
    create(:account)

    expect { described_class.perform_now }.not_to have_enqueued_job(Spx::EvalDigestJob)
  end
end
