require 'rails_helper'

RSpec.describe Reports::PdfExportJob do
  let(:account) { create(:account) }
  let(:export) { create(:report_pdf_export, account: account, report_type: 'nps') }

  it 'queues on low' do
    expect(described_class.new.queue_name).to eq('low')
  end

  context 'when the service succeeds' do
    let(:result) { Reports::PdfExportService::Result.new(bytes: '%PDF-1.4 bytes', sha256: 'abc123') }

    before do
      service = instance_double(Reports::PdfExportService, call: result)
      allow(Reports::PdfExportService).to receive(:new).and_return(service)
    end

    it 'attaches the file and marks the export completed' do
      described_class.perform_now(export.id)
      export.reload

      expect(export).to be_completed
      expect(export.file).to be_attached
      expect(export.sha256).to eq('abc123')
      expect(export.file_size).to eq('%PDF-1.4 bytes'.bytesize)
      expect(export.completed_at).to be_present
    end
  end

  context 'when the service raises' do
    before do
      service = instance_double(Reports::PdfExportService)
      allow(Reports::PdfExportService).to receive(:new).and_return(service)
      allow(service).to receive(:call).and_raise(StandardError, 'boom')
    end

    it 'marks the export failed and re-raises' do
      expect { described_class.perform_now(export.id) }.to raise_error(StandardError, 'boom')
      export.reload
      expect(export).to be_failed
      expect(export.error_message).to include('boom')
    end
  end

  it 'no-ops for a missing export id' do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end
end
