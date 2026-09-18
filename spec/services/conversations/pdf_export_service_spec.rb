require 'rails_helper'

RSpec.describe Conversations::PdfExportService do
  describe '#footer_template' do
    it 'shows the export ID and page number without an unrendered hash placeholder' do
      service = described_class.allocate
      service.instance_variable_set(:@export, Struct.new(:id).new(42))

      footer = service.send(:footer_template)

      expect(footer).to include('Export ID #42', 'pageNumber', 'totalPages')
      expect(footer).not_to include('HASH_AFTER_RENDER')
    end
  end

  describe 'integrity text' do
    it 'directs the reader to the export record for the SHA-256 hash' do
      template = Rails.root.join('app/views/conversations/pdf_export.html.erb').read

      expect(template).to include('sha256sum arquivo.pdf', 'registro do export')
      expect(template).not_to include('rodapé de cada página contém o hash')
    end
  end
end
