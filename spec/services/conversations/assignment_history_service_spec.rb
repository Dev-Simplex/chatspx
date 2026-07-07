require 'rails_helper'

RSpec.describe Conversations::AssignmentHistoryService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:actor) { create(:user, account: account, role: :agent) }
  let(:assignee) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  before do
    create(:inbox_member, inbox: inbox, user: actor)
    create(:inbox_member, inbox: inbox, user: assignee)
  end

  after { Current.reset }

  # Testado através do fluxo real (conversation.update! → after_commit → service), que é onde
  # o writer roda em produção. Cada exemplo apenas fixa o contexto (Current.user/executed_by).
  describe 'recording via the assignment hook' do
    context 'when a human assigns to another person (manual)' do
      before { Current.user = actor }

      it 'records one manual row crediting the actor' do
        expect { conversation.update!(assignee: assignee) }
          .to change(ConversationAssignmentHistory, :count).by(1)

        row = ConversationAssignmentHistory.last
        expect(row).to have_attributes(
          account_id: account.id,
          conversation_id: conversation.id,
          assignee_id: assignee.id,
          assigned_by_id: actor.id,
          source: 'manual'
        )
        expect(row.assigned_at).to be_present
        expect(row.unassigned_at).to be_nil
      end
    end

    context 'when a person picks the conversation for themselves (self_assigned)' do
      before { Current.user = assignee }

      it 'records a self_assigned row with the actor equal to the assignee' do
        conversation.update!(assignee: assignee)

        row = ConversationAssignmentHistory.last
        expect(row.source).to eq('self_assigned')
        expect(row.assigned_by_id).to eq(assignee.id)
      end
    end

    context 'when auto-assignment (round-robin) sets the assignee' do
      before do
        Current.user = nil
        Current.executed_by = inbox
      end

      it 'records an auto_round_robin row without crediting an author' do
        conversation.update!(assignee: assignee)

        row = ConversationAssignmentHistory.last
        expect(row.source).to eq('auto_round_robin')
        expect(row.assigned_by_id).to be_nil
      end
    end

    context 'when an automation rule assigns the conversation' do
      let(:rule) { create(:automation_rule, account: account) }

      before { Current.executed_by = rule }

      it 'records an automation row without an author' do
        conversation.update!(assignee: assignee)

        row = ConversationAssignmentHistory.last
        expect(row.source).to eq('automation')
        expect(row.assigned_by_id).to be_nil
      end
    end

    context 'when the conversation is unassigned (assignee -> nil)' do
      before do
        Current.user = actor
        conversation.update!(assignee: assignee)
      end

      it 'closes the open interval without creating a new row' do
        expect { conversation.update!(assignee: nil) }
          .not_to change(ConversationAssignmentHistory, :count)

        expect(ConversationAssignmentHistory.last.unassigned_at).to be_present
      end
    end

    context 'when the conversation is reassigned (A -> B)' do
      before do
        Current.user = actor
        conversation.update!(assignee: actor)
      end

      it 'closes the previous interval and opens a new one for B' do
        first = ConversationAssignmentHistory.last

        expect { conversation.update!(assignee: assignee) }
          .to change(ConversationAssignmentHistory, :count).by(1)

        expect(first.reload.unassigned_at).to be_present
        latest = ConversationAssignmentHistory.last
        expect(latest.assignee_id).to eq(assignee.id)
        expect(latest.unassigned_at).to be_nil
      end
    end

    context 'when the history writer fails' do
      before do
        Current.user = actor
        allow(ConversationAssignmentHistory).to receive(:create!).and_raise(StandardError, 'boom')
      end

      it 'never breaks the assignment itself (best-effort)' do
        expect { conversation.update!(assignee: assignee) }.not_to raise_error
        expect(conversation.reload.assignee_id).to eq(assignee.id)
      end
    end
  end
end
