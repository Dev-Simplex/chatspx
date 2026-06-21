require 'rails_helper'

RSpec.describe ReportPdfExport do
  let(:account) { create(:account) }

  describe 'validations' do
    it { is_expected.to validate_presence_of(:report_type) }

    it 'rejects an unsupported report_type' do
      export = build(:report_pdf_export, account: account, report_type: 'unknown')
      expect(export).not_to be_valid
      expect(export.errors[:report_type]).to be_present
    end

    it 'accepts the supported report types' do
      %w[nps csat bot conversations overview agent inbox team label sla].each do |report_type|
        expect(build(:report_pdf_export, account: account, report_type: report_type)).to be_valid
      end
    end
  end

  describe '#download_url' do
    let(:export) { create(:report_pdf_export, account: account, status: :completed) }

    it 'returns nil when no file is attached' do
      expect(export.download_url).to be_nil
    end

    it 'returns a signed blob url when a file is attached' do
      export.file.attach(io: StringIO.new('%PDF-1.4'), filename: 'nps.pdf', content_type: 'application/pdf')
      expect(export.download_url).to include('/rails/active_storage/blobs')
    end
  end

  describe '#duration_ms' do
    it 'returns nil without both timestamps' do
      expect(build(:report_pdf_export).duration_ms).to be_nil
    end

    it 'computes elapsed milliseconds' do
      export = build(:report_pdf_export, started_at: Time.current, completed_at: 2.seconds.from_now)
      expect(export.duration_ms).to be_within(50).of(2000)
    end
  end
end
