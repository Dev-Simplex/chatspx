require 'rails_helper'

RSpec.describe Captain::ConversationEvalSchedulerJob do
  let!(:account) do
    create(:account, custom_attributes: { 'eval_enabled' => true, 'eval_unit' => 'episode' })
  end
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }

  before do
    create(:captain_inbox, captain_assistant: assistant, inbox: inbox)
  end

  def create_episode(conversation, attrs = {})
    message = create(:message, account: account, inbox: inbox, conversation: conversation)
    Captain::ConversationEpisode.create!({
      account_id: account.id, conversation_id: conversation.id, seq: 1,
      first_message_id: message.id, last_message_id: message.id,
      started_at: 3.days.ago, last_message_at: 3.days.ago,
      boundary_reason: 'aberto', mensagens: 1
    }.merge(attrs))
  end

  # forja o órfão do jeito que ele nasce em produção: a conversa some (DeleteObjectJob,
  # destroy_async de contato/inbox) e o episódio fica — a tabela não tem FK nem dependent:.
  def create_orphan_episode
    conversation = create(:conversation, account: account, inbox: inbox)
    episode = create_episode(conversation)
    Conversation.where(id: conversation.id).delete_all
    episode
  end

  it 'enqueues the job on the scheduled_jobs queue' do
    expect { described_class.perform_later }.to have_enqueued_job(described_class).on_queue('scheduled_jobs')
  end

  # GlitchTip #128: ep.conversation nil derrubava #resegment_stale_open_episodes, que aborta
  # #enqueue_closed_episodes e o find_each das contas seguintes — o eval da conta parava inteiro.
  describe 'stale open episodes whose conversation was deleted' do
    it 'does not raise' do
      create_orphan_episode

      expect { described_class.perform_now }.not_to raise_error
    end

    it 'skips the orphan episode without calling the segmenter' do
      create_orphan_episode
      allow(Captain::EpisodeSegmenterService).to receive(:new).and_call_original

      described_class.perform_now

      expect(Captain::EpisodeSegmenterService).not_to have_received(:new)
    end

    it 'still enqueues the closed episodes of the account' do
      create_orphan_episode
      closed_conversation = create(:conversation, account: account, inbox: inbox)
      closed = create_episode(closed_conversation, boundary_reason: 'gap', ended_at: 2.hours.ago)
      # fora da janela de varredura: senão a re-segmentação reabriria o episódio
      closed_conversation.update_columns(last_activity_at: 3.days.ago) # rubocop:disable Rails/SkipsModelValidations

      expect { described_class.perform_now }
        .to have_enqueued_job(Captain::EpisodeEvalJob).with(closed)
    end

    it 'keeps processing the other accounts of the batch' do
      create_orphan_episode
      other_account = create(:account, custom_attributes: { 'eval_enabled' => true })
      other_inbox = create(:inbox, account: other_account)
      create(:captain_inbox, captain_assistant: create(:captain_assistant, account: other_account), inbox: other_inbox)
      conversation = create(:conversation, account: other_account, inbox: other_inbox)

      expect { described_class.perform_now }
        .to have_enqueued_job(Captain::ConversationEvalJob).with(conversation)
    end
  end

  describe 'resilience: one failing item cannot break the account' do
    before do
      tracker = instance_double(ChatwootExceptionTracker, capture_exception: nil)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)
    end

    it 'reports and moves on when the segmenter blows up on a conversation' do
      create(:conversation, account: account, inbox: inbox)
      allow(Captain::EpisodeSegmenterService).to receive(:new).and_raise(StandardError, 'boom')
      allow(Rails.logger).to receive(:error)

      expect { described_class.perform_now }.not_to raise_error
      expect(Rails.logger).to have_received(:error).with(/conversation=\d+.*boom/)
    end
  end
end
