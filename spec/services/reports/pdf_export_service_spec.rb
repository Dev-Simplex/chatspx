require 'rails_helper'

RSpec.describe Reports::PdfExportService do
  let(:account) { create(:account) }
  let(:export) do
    create(:report_pdf_export, account: account, report_type: 'nps',
                               filters: { 'since' => '1735689600', 'until' => '1749340800' })
  end

  describe '#call' do
    # Stub do FerrumPdf (Chromium): devolve o proprio HTML como "bytes" para
    # podermos inspecionar o template renderizado sem depender do browser.
    before do
      allow(FerrumPdf).to receive(:render_pdf) { |html:, **_| html }
    end

    it 'renders the nps template inside the SPX layout and returns hashed bytes' do
      result = described_class.new(export: export).call

      expect(result.sha256).to eq(Digest::SHA256.hexdigest(result.bytes))
      expect(result.bytes).to include('ChatSPX')
      expect(result.bytes).to include('Relatório de NPS')
      expect(result.bytes).to include('@font-face')
    end

    it 'propagates a resolver error for an unsupported report_type' do
      resolver = instance_double(Reports::PdfDataResolver)
      allow(Reports::PdfDataResolver).to receive(:new).and_return(resolver)
      allow(resolver).to receive(:resolve).and_raise(ArgumentError)

      expect { described_class.new(export: export).call }.to raise_error(ArgumentError)
    end
  end
end
