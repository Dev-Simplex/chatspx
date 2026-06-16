require 'rails_helper'

RSpec.describe Attachments::PurgeBulkDownloadsJob, type: :job do
  let(:account) { create(:account) }

  it 'destroys expired records' do
    expired = create(:attachment_bulk_download, account: account, status: :completed, expires_at: 1.hour.ago)
    fresh = create(:attachment_bulk_download, account: account, status: :completed, expires_at: 1.hour.from_now)

    described_class.perform_now

    expect(AttachmentBulkDownload.exists?(expired.id)).to be(false)
    expect(AttachmentBulkDownload.exists?(fresh.id)).to be(true)
  end

  it 'fails records stuck in processing for over two hours' do
    stuck = create(:attachment_bulk_download, account: account, status: :processing,
                                              started_at: 3.hours.ago, expires_at: 1.day.from_now)
    recent = create(:attachment_bulk_download, account: account, status: :processing,
                                               started_at: 5.minutes.ago, expires_at: 1.day.from_now)

    described_class.perform_now

    expect(stuck.reload).to be_failed
    expect(recent.reload).to be_processing
  end
end
