require 'rails_helper'

RSpec.describe Attachments::BulkDownloadJob, type: :job do
  let(:account) { create(:account) }
  let(:bulk) { create(:attachment_bulk_download, account: account, status: :pending) }

  it 'is enqueued on the low queue' do
    expect { described_class.perform_later(bulk.id) }.to have_enqueued_job(described_class).on_queue('low')
  end

  context 'when the service succeeds' do
    it 'marks the record completed with counts' do
      result = Attachments::BulkDownloadZipService::Result.new(
        file_size: 1234, processed_count: 3, skipped_count: 1, total_bytes: 9999
      )
      service = instance_double(Attachments::BulkDownloadZipService, call: result)
      allow(Attachments::BulkDownloadZipService).to receive(:new).and_return(service)

      described_class.perform_now(bulk.id)

      expect(bulk.reload).to be_completed
      expect(bulk.processed_count).to eq(3)
      expect(bulk.file_size).to eq(1234)
      expect(bulk.completed_at).to be_present
    end
  end

  context 'when every attachment was skipped' do
    it 'marks the record failed instead of completed' do
      result = Attachments::BulkDownloadZipService::Result.new(
        file_size: 0, processed_count: 0, skipped_count: 2, total_bytes: 0
      )
      service = instance_double(Attachments::BulkDownloadZipService, call: result)
      allow(Attachments::BulkDownloadZipService).to receive(:new).and_return(service)

      described_class.perform_now(bulk.id)

      expect(bulk.reload).to be_failed
      expect(bulk.error_message).to be_present
    end
  end

  context 'when the service raises' do
    it 'marks the record failed and re-raises' do
      allow(Attachments::BulkDownloadZipService).to receive(:new).and_raise(StandardError, 'boom')

      expect { described_class.perform_now(bulk.id) }.to raise_error(StandardError, 'boom')
      expect(bulk.reload).to be_failed
      expect(bulk.error_message).to include('boom')
    end
  end

  it 'is idempotent: does not regenerate a completed record' do
    bulk.update!(status: :completed)
    expect(Attachments::BulkDownloadZipService).not_to receive(:new)

    described_class.perform_now(bulk.id)
  end

  # §T4: registro apagado entre o pedido e a execução é erro PERMANENTE.
  context 'when the scope resolution raises RecordNotFound' do
    it 'marks the record failed without re-raising (no Sidekiq retries)' do
      allow(Attachments::BulkDownloadZipService).to receive(:new)
        .and_raise(ActiveRecord::RecordNotFound, 'gone')

      expect { described_class.perform_now(bulk.id) }.not_to raise_error
      expect(bulk.reload).to be_failed
      expect(bulk.error_message).to include('registro_nao_encontrado')
    end
  end

  # §T3: TOCTOU de autorização no modo conversa.
  context 'when the requester lost inbox access between create and job' do
    let(:agent) { create(:user, account: account, role: :agent) }
    let(:inbox) { create(:inbox, account: account) }
    let(:inbox_member) { create(:inbox_member, user: agent, inbox: inbox) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }

    def conversation_bulk
      create(:attachment_bulk_download, account: account, requester_user: agent,
                                        conversation: conversation, status: :pending,
                                        params: { conversation_id: conversation.id })
    end

    it 'fails terminally and never generates the zip when access is revoked' do
      inbox_member # garante que a conversa existe sob uma inbox real
      revoked_bulk = conversation_bulk
      inbox_member.destroy! # acesso revogado dentro da janela de retenção

      expect(Attachments::BulkDownloadZipService).not_to receive(:new)
      expect { described_class.perform_now(revoked_bulk.id) }.not_to raise_error

      expect(revoked_bulk.reload).to be_failed
      expect(revoked_bulk.error_message).to include('acesso_revogado')
      expect(revoked_bulk.file).not_to be_attached
    end

    it 'proceeds normally when the agent still has access' do
      inbox_member
      ok_bulk = conversation_bulk
      result = Attachments::BulkDownloadZipService::Result.new(
        file_size: 10, processed_count: 1, skipped_count: 0, total_bytes: 10
      )
      service = instance_double(Attachments::BulkDownloadZipService, call: result)
      allow(Attachments::BulkDownloadZipService).to receive(:new).and_return(service)

      described_class.perform_now(ok_bulk.id)

      expect(ok_bulk.reload).to be_completed
    end
  end
end
