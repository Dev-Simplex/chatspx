require 'rails_helper'

RSpec.describe Conversations::DeleteService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:ip) { '127.0.0.1' }
  let(:service) { described_class.new(conversation: conversation, user: user, ip: ip) }

  context 'when deleting an email conversation' do
    let(:inbox) { create(:channel_email, :imap_email, account: account).inbox }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }
    let!(:incoming_message) { create(:message, account: account, inbox: inbox, conversation: conversation, source_id: 'incoming@example.com') }
    let(:deleted_message_tracker) { instance_double(Imap::DeletedMessageTracker, record: true) }

    before do
      allow(Imap::DeletedMessageTracker).to receive(:new).with(inbox: inbox).and_return(deleted_message_tracker)
    end

    it 'records incoming message source ids and enqueues the deletion job' do
      expect { service.perform }
        .to have_enqueued_job(DeleteObjectJob).with('Conversation', conversation.id, user.id, ip)

      expect(deleted_message_tracker).to have_received(:record).with([incoming_message.source_id])
    end
  end

  context 'when deleting a non-email conversation' do
    let(:conversation) { create(:conversation, account: account) }

    it 'enqueues the deletion job without recording message source ids' do
      expect(Imap::DeletedMessageTracker).not_to receive(:new)

      expect { service.perform }
        .to have_enqueued_job(DeleteObjectJob).with('Conversation', conversation.id, user.id, ip)
    end
  end

  # ChatSPX (item 26): os dois exemplos acima asseveravam a chamada COM OS ARGUMENTOS ERRADOS — é
  # por isso que o P0 passava verde. O que faltava era medir o EFEITO. `DeleteObjectJob` começa com
  # `return unless ALLOWED_OBJECT_TYPES.include?(object_type)`, e comparar String com uma instância
  # de Conversation dá false: o job retornava na primeira linha, sem exceção e sem log, a API
  # respondia 200 OK e a conversa continuava lá.
  describe 'o efeito, não a chamada' do
    let(:conversation) { create(:conversation, account: account) }

    it 'actually deletes the conversation' do
      perform_enqueued_jobs(only: DeleteObjectJob) { service.perform }

      expect(Conversation.exists?(conversation.id)).to be(false)
    end

    # Correção (b): sem cascade nas 4 FKs que apontam para conversations, o destroy! volta a rodar
    # e levanta InvalidForeignKey DENTRO de um job com retry — trocaríamos "some em silêncio" por
    # "falha em loop no GlitchTip". Aqui a conversa carrega os quatro bloqueadores de uma vez.
    it 'deletes the conversation even with flow runs, step logs, captain logs and sequence enrollments attached' do
      flow = create(:flow, account: account)
      flow_run = create(:flow_run, flow: flow, account: account, conversation: conversation, contact: conversation.contact)
      step_log = create(:flow_step_log, flow: flow, account: account, conversation: conversation, flow_run: flow_run)
      enrollment = create(:message_sequence_enrollment,
                          message_sequence: create(:message_sequence, account: account),
                          conversation: conversation)
      assistant_log = Captain::AssistantLog.create!(
        captain_assistant: create(:captain_assistant, account: account),
        conversation: conversation,
        event_type: 'response'
      )

      perform_enqueued_jobs(only: DeleteObjectJob) { service.perform }

      expect(Conversation.exists?(conversation.id)).to be(false)
      # NOT NULL na coluna -> cascade: não existem sem a conversa.
      expect(FlowRun.exists?(flow_run.id)).to be(false)
      expect(MessageSequenceEnrollment.exists?(enrollment.id)).to be(false)
      # Nullable -> SET NULL: o log de execução/IA SOBREVIVE, só perde o vínculo.
      expect(FlowStepLog.find(step_log.id).conversation_id).to be_nil
      expect(Captain::AssistantLog.find(assistant_log.id).conversation_id).to be_nil
    end
  end
end
