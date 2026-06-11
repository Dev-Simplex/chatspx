require 'rails_helper'

RSpec.describe Account::ConversationsResolutionSchedulerJob, type: :job do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }

  describe '#perform - captain resolutions' do
    context 'when handling different inbox types' do
      let!(:regular_inbox) { create(:inbox, account: account) }
      let!(:email_inbox) { create(:inbox, :with_email, account: account) }

      before do
        create(:captain_inbox, captain_assistant: assistant, inbox: regular_inbox)
        create(:captain_inbox, captain_assistant: assistant, inbox: email_inbox)
      end

      it 'enqueues resolution jobs only for non-email inboxes with captain enabled' do
        expect do
          described_class.perform_now
        end.to have_enqueued_job(Captain::InboxPendingConversationsResolutionJob)
          .with(regular_inbox)
          .exactly(:once)
      end

      it 'does not enqueue resolution jobs for email inboxes even with captain enabled' do
        expect do
          described_class.perform_now
        end.not_to have_enqueued_job(Captain::InboxPendingConversationsResolutionJob)
          .with(email_inbox)
      end
    end

    context 'when account has captain auto resolve disabled' do
      let!(:regular_inbox) { create(:inbox, account: account) }

      before do
        create(:captain_inbox, captain_assistant: assistant, inbox: regular_inbox)
        account.update!(captain_auto_resolve_mode: 'disabled')
      end

      it 'does not enqueue resolution jobs' do
        expect do
          described_class.perform_now
        end.not_to have_enqueued_job(Captain::InboxPendingConversationsResolutionJob)
          .with(regular_inbox)
      end
    end

    context 'when account uses legacy disabled settings key' do
      let!(:regular_inbox) { create(:inbox, account: account) }

      before do
        create(:captain_inbox, captain_assistant: assistant, inbox: regular_inbox)
        account.update!(settings: account.settings.merge('captain_disable_auto_resolve' => true))
      end

      it 'does not enqueue resolution jobs' do
        expect do
          described_class.perform_now
        end.not_to have_enqueued_job(Captain::InboxPendingConversationsResolutionJob)
          .with(regular_inbox)
      end
    end

    context 'when inbox has no captain enabled' do
      let!(:inbox_without_captain) { create(:inbox, account: create(:account)) }

      it 'does not enqueue resolution jobs' do
        expect do
          described_class.perform_now
        end.not_to have_enqueued_job(Captain::InboxPendingConversationsResolutionJob)
          .with(inbox_without_captain)
      end
    end

    # A4: com has_many (A5) duas IAs elegíveis na mesma inbox compartilham uma única
    # CaptainInbox por (assistant, inbox). O scheduler dedupa por inbox_id — uma inbox
    # com 2 elegíveis ainda enfileira o job UMA vez.
    context 'when an inbox is eligible for two assistants' do
      let!(:regular_inbox) { create(:inbox, account: account) }
      let(:second_assistant) { create(:captain_assistant, account: account) }

      before do
        create(:captain_inbox, captain_assistant: assistant, inbox: regular_inbox)
        # 2ª elegibilidade na mesma inbox: o índice único do banco é no PAR
        # (captain_assistant_id, inbox_id), então usamos insert_all p/ não esbarrar na
        # validação model-only (substituída por uniqueness composta em A5).
        CaptainInbox.insert_all( # rubocop:disable Rails/SkipsModelValidations
          [{ captain_assistant_id: second_assistant.id, inbox_id: regular_inbox.id,
             created_at: Time.current, updated_at: Time.current }]
        )
      end

      it 'enqueues the resolution job for the inbox exactly once' do
        expect do
          described_class.perform_now
        end.to have_enqueued_job(Captain::InboxPendingConversationsResolutionJob)
          .with(regular_inbox)
          .exactly(:once)
      end
    end
  end
end
