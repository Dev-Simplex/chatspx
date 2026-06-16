require 'rails_helper'

RSpec.describe AttachmentBulkDownload, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:requester_user).class_name('User').optional }
    it { is_expected.to belong_to(:conversation).optional }
  end

  describe 'enum status' do
    it 'defines the export lifecycle states' do
      expect(described_class.statuses).to eq('pending' => 0, 'processing' => 1, 'completed' => 2, 'failed' => 3)
    end
  end

  describe 'caps and retention constants' do
    it 'caps files and bytes per request and retains zips for 7 days' do
      expect(described_class::MAX_FILES).to eq(500)
      expect(described_class::MAX_TOTAL_BYTES).to eq(2.gigabytes)
      expect(described_class::RETENTION).to eq(7.days)
    end
  end

  describe 'scopes' do
    let(:account) { create(:account) }

    it '.active returns only pending/processing' do
      pending = create(:attachment_bulk_download, account: account, status: :pending)
      processing = create(:attachment_bulk_download, account: account, status: :processing)
      create(:attachment_bulk_download, account: account, status: :completed)

      expect(account.attachment_bulk_downloads.active).to contain_exactly(pending, processing)
    end

    it '.expired returns records past expires_at' do
      expired = create(:attachment_bulk_download, account: account, expires_at: 1.hour.ago)
      create(:attachment_bulk_download, account: account, expires_at: 1.hour.from_now)

      expect(account.attachment_bulk_downloads.expired).to contain_exactly(expired)
    end
  end

  describe '#download_url' do
    let(:export) { create(:attachment_bulk_download) }

    it 'returns nil when no file is attached' do
      expect(export.download_url).to be_nil
    end

    it 'returns a signed attachment url when a file is attached' do
      export.file.attach(io: StringIO.new('zip'), filename: 'midias.zip', content_type: 'application/zip')
      expect(export.download_url).to include('midias.zip').or include('blobs')
    end
  end

  describe '#duration_ms' do
    it 'is nil until both timestamps are set' do
      expect(build(:attachment_bulk_download, started_at: nil, completed_at: nil).duration_ms).to be_nil
    end

    it 'returns the elapsed milliseconds' do
      record = build(:attachment_bulk_download, started_at: Time.current, completed_at: 2.seconds.from_now)
      expect(record.duration_ms).to be_within(50).of(2000)
    end
  end
end
