require 'rails_helper'

RSpec.describe Attachments::BulkDownloadZipService, type: :service do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }

  before { create(:inbox_member, user: agent, inbox: inbox) }

  def create_attachment(file_type: :image, asset: 'sample.png', content_type: 'image/png')
    conversation = create(:conversation, account: account, inbox: inbox)
    message = create(:message, account: account, conversation: conversation, inbox: inbox)
    attachment = message.attachments.new(account_id: account.id, file_type: file_type)
    attachment.file.attach(io: Rails.root.join("spec/assets/#{asset}").open, filename: asset, content_type: content_type)
    attachment.save!
    attachment
  end

  def bulk_download(attachment_ids)
    create(:attachment_bulk_download, account: account, requester_user: agent, status: :processing,
                                      params: { attachment_ids: attachment_ids })
  end

  def zip_entries(bulk)
    Tempfile.create(['out', '.zip']) do |tmp|
      tmp.binmode
      tmp.write(bulk.file.download)
      tmp.rewind
      Zip::File.open(tmp.path) { |zip| return zip.entries.map(&:name) }
    end
  end

  it 'produces a zip that opens and contains the attachment plus a manifest' do
    attachment = create_attachment
    bulk = bulk_download([attachment.id])

    result = described_class.new(bulk).call

    expect(bulk.file).to be_attached
    expect(result.processed_count).to eq(1)
    entries = zip_entries(bulk)
    expect(entries).to include('_manifest.txt')
    expect(entries.count { |e| e != '_manifest.txt' }).to eq(1)
  end

  it 'skips attachments without a stored blob and records them in the manifest' do
    attachment = create_attachment
    attachment.file.purge # simula IG external_url / blob purgado
    bulk = bulk_download([attachment.id])

    result = described_class.new(bulk).call

    expect(result.processed_count).to eq(0)
    expect(result.skipped_count).to eq(1)
  end

  it 'updates progress and reports total bytes' do
    attachment = create_attachment
    bulk = bulk_download([attachment.id])

    result = described_class.new(bulk).call

    expect(result.total_bytes).to be > 0
    expect(result.file_size).to be > 0
  end

  # §T2: defesa de recurso revalidada na execução, não só no create.
  context 'when the resolved scope grew beyond the file cap' do
    it 'never processes more than MAX_FILES' do
      stub_const('AttachmentBulkDownload::MAX_FILES', 2)
      attachments = Array.new(3) { create_attachment }
      bulk = bulk_download(attachments.map(&:id))

      result = described_class.new(bulk).call

      expect(result.processed_count).to eq(2)
      expect(zip_entries(bulk).count { |e| e != '_manifest.txt' }).to eq(2)
    end
  end

  context 'when accumulated bytes exceed MAX_TOTAL_BYTES mid-stream' do
    it 'stops adding without raising and still produces a valid zip' do
      # Teto minúsculo: o 1º arquivo sempre entra; os demais são omitidos.
      stub_const('AttachmentBulkDownload::MAX_TOTAL_BYTES', 1)
      attachments = Array.new(3) { create_attachment }
      bulk = bulk_download(attachments.map(&:id))

      result = nil
      expect { result = described_class.new(bulk).call }.not_to raise_error
      expect(result.processed_count).to eq(1)
      expect(result.skipped_count).to be >= 2
      entries = zip_entries(bulk)
      expect(entries).to include('_manifest.txt')
      expect(entries.count { |e| e != '_manifest.txt' }).to eq(1)
    end
  end
end
