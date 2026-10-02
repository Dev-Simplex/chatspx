require 'rails_helper'

RSpec.describe DeleteObjectJob, type: :job do
  describe '#perform' do
    context 'when object is heavy (Inbox)' do
      let!(:account) { create(:account) }
      let!(:inbox) { create(:inbox, account: account) }

      before do
        create_list(:conversation, 3, account: account, inbox: inbox)
        ReportingEvent.create!(account: account, inbox: inbox, name: 'inbox_metric', value: 1.0)
      end

      it 'enqueues on the low queue' do
        expect { described_class.perform_later('Inbox', inbox.id) }
          .to have_enqueued_job(described_class).with('Inbox', inbox.id).on_queue('low')
      end

      it 'pre-deletes heavy associations and then destroys the object' do
        conv_ids = inbox.conversations.pluck(:id)
        ci_ids = inbox.contact_inboxes.pluck(:id)
        contact_ids = inbox.contacts.pluck(:id)
        re_ids = inbox.reporting_events.pluck(:id)

        described_class.perform_now('Inbox', inbox.id)

        # Reload associations to ensure database state is current
        expect(Conversation.where(id: conv_ids).reload).to be_empty
        expect(ContactInbox.where(id: ci_ids).reload).to be_empty
        expect(ReportingEvent.where(id: re_ids).reload).to be_empty
        # Contacts should not be deleted for inbox destroy
        expect(Contact.where(id: contact_ids).reload).not_to be_empty
        expect { inbox.reload }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context 'when object is heavy (Account)' do
      let!(:account) { create(:account) }
      let!(:inbox1) { create(:inbox, account: account) }
      let!(:inbox2) { create(:inbox, account: account) }

      before do
        create_list(:conversation, 2, account: account, inbox: inbox1)
        create_list(:conversation, 1, account: account, inbox: inbox2)
        ReportingEvent.create!(account: account, name: 'acct_metric', value: 2.5)
        ReportingEvent.create!(account: account, inbox: inbox1, name: 'acct_inbox_metric', value: 3.5)
      end

      it 'pre-deletes conversations, contacts, inboxes and reporting events and then destroys the account' do
        conv_ids = account.conversations.pluck(:id)
        contact_ids = account.contacts.pluck(:id)
        inbox_ids = account.inboxes.pluck(:id)
        re_ids = account.reporting_events.pluck(:id)

        described_class.perform_now('Account', account.id)

        # Reload associations to ensure database state is current
        expect(Conversation.where(id: conv_ids).reload).to be_empty
        expect(Contact.where(id: contact_ids).reload).to be_empty
        expect(Inbox.where(id: inbox_ids).reload).to be_empty
        expect(ReportingEvent.where(id: re_ids).reload).to be_empty
        expect { account.reload }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    # Regressao: as quatro tabelas abaixo nasceram com FK RESTRICT e sem `dependent:`,
    # entao qualquer conversa tocada pela IA ou por um flow travava a exclusao da caixa.
    # Como o job roda em background, a API respondia 200 "excluida" e a caixa voltava no
    # proximo reload (visto na FABRICA em 08/09/2026). Ver migration 20260908120000.
    # T07: agente que ja recebeu atribuicao nao saia — o historico apontava para ele com FK RESTRICT.
    # O historico e do relatorio da conta: fica, so perde o vinculo.
    context 'when the agent left assignment history behind' do
      let!(:account) { create(:account) }
      let!(:agent) { create(:user, account: account, role: :agent) }
      let!(:history) do
        create(:conversation_assignment_history, account: account, conversation: create(:conversation, account: account), assignee: agent)
      end

      it 'destroys the agent and keeps the history without the assignee' do
        expect { described_class.perform_now('User', agent.id) }.not_to raise_error

        expect(User.where(id: agent.id)).to be_empty
        expect(history.reload.assignee_id).to be_nil
      end
    end

    context 'when the conversation carries AI and flow trails' do
      let!(:account) { create(:account) }
      let!(:inbox) { create(:inbox, account: account) }
      let!(:conversation) { create(:conversation, account: account, inbox: inbox) }
      let!(:flow) { create(:flow, account: account) }

      before do
        Captain::AssistantLog.create!(
          captain_assistant: create(:captain_assistant, account: account),
          conversation: conversation,
          event_type: 'response'
        )
        create(:flow_run, flow: flow, account: account, conversation: conversation, contact: conversation.contact)
        create(:flow_step_log, flow: flow, account: account, conversation: conversation)
        create(:message_sequence_enrollment, conversation: conversation,
                                             message_sequence: create(:message_sequence, account: account))
      end

      it 'destroys the inbox instead of dying on a foreign key' do
        expect { described_class.perform_now('Inbox', inbox.id) }.not_to raise_error

        expect(Inbox.where(id: inbox.id)).to be_empty
        expect(Conversation.where(id: conversation.id)).to be_empty
        expect(Captain::AssistantLog.where(conversation_id: conversation.id)).to be_empty
        expect(FlowRun.where(conversation_id: conversation.id)).to be_empty
        expect(FlowStepLog.where(conversation_id: conversation.id)).to be_empty
        expect(MessageSequenceEnrollment.where(conversation_id: conversation.id)).to be_empty
      end
    end

    context 'when object is regular (Label)' do
      it 'just destroys the object' do
        label = create(:label)

        described_class.perform_now('Label', label.id)

        expect { label.reload }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
