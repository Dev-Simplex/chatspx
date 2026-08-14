require 'rails_helper'

RSpec.describe Conversations::OrphanRetriageJob do
  subject(:job) { described_class.perform_later(account) }

  let!(:account) { create(:account, settings: { reply_assignment_gate: true }) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:other_admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }

  let(:matching_conditions) do
    [{ 'values': ['open'], 'attribute_key': 'status', 'query_operator': nil, 'filter_operator': 'equal_to' }]
  end
  let(:non_matching_conditions) do
    [{ 'values': ['resolved'], 'attribute_key': 'status', 'query_operator': nil, 'filter_operator': 'equal_to' }]
  end

  def create_orphan(last_activity_at: 30.minutes.ago)
    conversation = create(:conversation, account: account, inbox: inbox, status: :open, assignee: nil)
    conversation.update_columns(last_activity_at: last_activity_at) # rubocop:disable Rails/SkipsModelValidations
    conversation
  end

  def orphan_notifications
    Notification.where(notification_type: 'conversation_orphaned', account_id: account.id)
  end

  it 'enqueues the job on the low queue' do
    expect { job }.to have_enqueued_job(described_class).on_queue('low')
  end

  describe 'orphan scope (open + both nils + window on last_activity_at)' do
    it 'does not treat a conversation assigned to a captain mirror as orphan' do
      assistant = create(:captain_assistant, account: account)
      conversation = create(:conversation, account: account, inbox: inbox, status: :open,
                                           assignee_agent_bot: assistant.mirror_agent_bot)
      conversation.update_columns(last_activity_at: 30.minutes.ago) # rubocop:disable Rails/SkipsModelValidations

      expect { described_class.perform_now(account) }.not_to change(orphan_notifications, :count)
      expect(conversation.reload.additional_attributes['orphan_alerted_at']).to be_nil
    end

    it 'does not treat a conversation assigned to a human as orphan' do
      conversation = create(:conversation, account: account, inbox: inbox, status: :open, assignee: admin)
      conversation.update_columns(last_activity_at: 30.minutes.ago) # rubocop:disable Rails/SkipsModelValidations

      expect { described_class.perform_now(account) }.not_to change(orphan_notifications, :count)
      expect(conversation.reload.additional_attributes['orphan_alerted_at']).to be_nil
    end

    it 'respects the default 15 minutes window' do
      conversation = create_orphan(last_activity_at: 10.minutes.ago)

      expect { described_class.perform_now(account) }.not_to change(orphan_notifications, :count)
      expect(conversation.reload.additional_attributes['orphan_alerted_at']).to be_nil
    end

    it 'respects a custom orphan_retriage_after window from account settings' do
      account.update!(orphan_retriage_after: 5)
      conversation = create_orphan(last_activity_at: 10.minutes.ago)

      expect { described_class.perform_now(account) }.to change(orphan_notifications, :count).by(2)
      expect(conversation.reload.additional_attributes['orphan_alerted_at']).to be_present
    end

    # GlitchTip #68: conversa cujo contato foi apagado (migration de FK nulificou contact_id)
    # é inválida no model — o update! do marcador reprovava e derrubava o batch inteiro.
    # Mesmo guard do Conversations::ResolutionJob.
    it 'ignores orphan conversations whose contact was deleted (contact_id nil)' do
      conversation = create_orphan
      conversation.update_columns(contact_id: nil) # rubocop:disable Rails/SkipsModelValidations
      tracker = instance_double(ChatwootExceptionTracker, capture_exception: nil)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

      expect { described_class.perform_now(account) }.not_to change(orphan_notifications, :count)

      expect(conversation.reload.additional_attributes['orphan_alerted_at']).to be_nil
      # sai na QUERY, não no rescue: a conversa não chega a ser tocada pelo laço
      expect(ChatwootExceptionTracker).not_to have_received(:new)
    end
  end

  describe 'resilience: one broken conversation cannot break the batch' do
    # conversa inválida em repouso (contact_inbox apagado) que PASSA pelo guard de contact_id:
    # representa a próxima variante do mesmo bug — o laço tem que seguir para as demais.
    def create_broken_orphan
      conversation = create_orphan
      conversation.update_columns(contact_inbox_id: nil) # rubocop:disable Rails/SkipsModelValidations
      conversation
    end

    before do
      tracker = instance_double(ChatwootExceptionTracker, capture_exception: nil)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)
    end

    it 'keeps processing the remaining conversations when one of them fails' do
      broken = create_broken_orphan
      healthy = create_orphan

      expect { described_class.perform_now(account) }.to change(orphan_notifications, :count).by(2)

      expect(orphan_notifications.pluck(:primary_actor_id).uniq).to eq([healthy.id])
      expect(healthy.reload.additional_attributes['orphan_alerted_at']).to be_present
      expect(broken.reload.additional_attributes['orphan_alerted_at']).to be_nil
    end

    it 'does not raise and reports the failing conversation' do
      broken = create_broken_orphan
      allow(Rails.logger).to receive(:error)

      expect { described_class.perform_now(account) }.not_to raise_error

      expect(Rails.logger).to have_received(:error)
        .with(/conversation=#{broken.id}.*ActiveRecord::RecordInvalid/)
      expect(ChatwootExceptionTracker).to have_received(:new).at_least(:once)
    end

    # o spam de notificação vinha daqui: notify_admins rodava ANTES do update! que falhava,
    # então os admins eram avisados a cada 5 min sobre uma conversa que nunca deduplicava.
    it 'does not notify admins when the alert marker cannot be persisted' do
      create_broken_orphan

      expect { described_class.perform_now(account) }.not_to change(orphan_notifications, :count)
    end
  end

  describe 'retriage (direct re-run of conversation_created rules)' do
    it 'assigns via matching rule and does NOT notify admins' do
      create(:automation_rule, account: account, event_name: 'conversation_created',
                               conditions: matching_conditions,
                               actions: [{ 'action_name' => 'assign_agent', 'action_params' => [admin.id] }])
      conversation = create_orphan

      expect { described_class.perform_now(account) }.not_to change(orphan_notifications, :count)

      expect(conversation.reload.assignee).to eq(admin)
      expect(conversation.additional_attributes['orphan_alerted_at']).to be_nil
    end

    it 'skips rules whose conditions do not match' do
      create(:automation_rule, account: account, event_name: 'conversation_created',
                               conditions: non_matching_conditions,
                               actions: [{ 'action_name' => 'assign_agent', 'action_params' => [admin.id] }])
      conversation = create_orphan

      described_class.perform_now(account)

      expect(conversation.reload.assignee).to be_nil
    end

    it 'ignores inactive rules and rules for other events' do
      create(:automation_rule, account: account, event_name: 'conversation_created', active: false,
                               conditions: matching_conditions,
                               actions: [{ 'action_name' => 'assign_agent', 'action_params' => [admin.id] }])
      create(:automation_rule, account: account, event_name: 'conversation_updated',
                               conditions: matching_conditions,
                               actions: [{ 'action_name' => 'assign_agent', 'action_params' => [admin.id] }])
      conversation = create_orphan

      described_class.perform_now(account)

      expect(conversation.reload.assignee).to be_nil
    end

    it 'does not let a failing rule action break the loop' do
      rule_with_error = create(:automation_rule, account: account, event_name: 'conversation_created',
                                                 conditions: matching_conditions,
                                                 actions: [{ 'action_name' => 'add_label', 'action_params' => %w[support] }])
      assigning_rule = create(:automation_rule, account: account, event_name: 'conversation_created',
                                                conditions: matching_conditions,
                                                actions: [{ 'action_name' => 'assign_agent', 'action_params' => [admin.id] }])
      conversation = create_orphan

      working_service = AutomationRules::ActionService.new(assigning_rule, account, conversation)
      allow(AutomationRules::ActionService).to receive(:new) do |rule, *_args|
        raise StandardError, 'boom' if rule == rule_with_error

        working_service
      end
      tracker = instance_double(ChatwootExceptionTracker, capture_exception: nil)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

      described_class.perform_now(account)

      expect(tracker).to have_received(:capture_exception)
      expect(conversation.reload.assignee).to eq(admin)
    end
  end

  # F1.4 — modo FILA: a re-triagem pode rotear a órfã pra um time, MAS não pode reanexar
  # a IA (senão a conversa volta pra IA e a fila por time some). O gate
  # Current.skip_ai_agent_assignment desliga só a action assign_ai_agent durante a re-triagem.
  describe 'fila mode: orphan retriage does not reattach the IA (F1.4)' do
    let(:assistant) { create(:captain_assistant, account: account) }
    let(:team) { create(:team, account: account) }

    before do
      create(:captain_inbox, captain_assistant: assistant, inbox: inbox)
      assistant.mirror_agent_bot # garante o espelho
    end

    it 'does NOT reassign the IA via an assign_ai_agent rule (queue stays intact)' do
      create(:automation_rule, account: account, event_name: 'conversation_created',
                               conditions: matching_conditions,
                               actions: [{ 'action_name' => 'assign_ai_agent', 'action_params' => [assistant.id] }])
      conversation = create_orphan

      described_class.perform_now(account)

      conversation.reload
      expect(conversation.assignee_agent_bot_id).to be_nil
    end

    it 'still routes the orphan to a team (assign_team works during retriage)' do
      create(:automation_rule, account: account, event_name: 'conversation_created',
                               conditions: matching_conditions,
                               actions: [{ 'action_name' => 'assign_team', 'action_params' => [team.id] }])
      conversation = create_orphan

      described_class.perform_now(account)

      expect(conversation.reload.team_id).to eq(team.id)
    end

    it 'restores Current.skip_ai_agent_assignment after the retriage' do
      create(:automation_rule, account: account, event_name: 'conversation_created',
                               conditions: matching_conditions,
                               actions: [{ 'action_name' => 'assign_ai_agent', 'action_params' => [assistant.id] }])
      create_orphan

      described_class.perform_now(account)

      expect(Current.skip_ai_agent_assignment).to be_nil
    end
  end

  describe 'classic mode: assign_ai_agent action still attaches the IA (not gated)' do
    let(:classic_account) { create(:account, settings: { reply_assignment_gate: false }) }
    let(:classic_inbox) { create(:inbox, account: classic_account) }
    let(:classic_contact) { create(:contact, account: classic_account) }
    let(:classic_assistant) { create(:captain_assistant, account: classic_account) }

    before do
      create(:captain_inbox, captain_assistant: classic_assistant, inbox: classic_inbox)
      classic_assistant.mirror_agent_bot
    end

    # Garante que o gate F1.4 é local ao modo fila: a action assign_ai_agent em si (triagem
    # inicial, sem skip) NÃO foi quebrada — segue atribuindo o espelho.
    it 'attaches the mirror when skip_ai_agent_assignment is not set' do
      conversation = create(:conversation, account: classic_account, inbox: classic_inbox,
                                           contact: classic_contact, status: :open, assignee: nil)
      rule = create(:automation_rule, account: classic_account, event_name: 'conversation_created',
                                      conditions: matching_conditions,
                                      actions: [{ 'action_name' => 'assign_ai_agent', 'action_params' => [classic_assistant.id] }])

      AutomationRules::ActionService.new(rule, classic_account, conversation).perform

      expect(conversation.reload.assignee_agent_bot_id).to eq(classic_assistant.mirror_agent_bot.id)
    end
  end

  describe 'notification per orphan episode (DC-8 dedupe)' do
    it 'notifies every admin once when the conversation stays orphan' do
      conversation = create_orphan

      expect { described_class.perform_now(account) }.to change(orphan_notifications, :count).by(2)

      expect(orphan_notifications.pluck(:user_id)).to contain_exactly(admin.id, other_admin.id)
      expect(orphan_notifications.pluck(:primary_actor_id).uniq).to eq([conversation.id])
      expect(conversation.reload.additional_attributes['orphan_alerted_at']).to be_present
    end

    it 'does not notify again on the next tick for the same episode' do
      create_orphan

      described_class.perform_now(account)

      expect { described_class.perform_now(account) }.not_to change(orphan_notifications, :count)
    end

    it 'resets the episode when there is new activity after the last alert' do
      conversation = create_orphan(last_activity_at: 30.minutes.ago)
      conversation.update!(additional_attributes: { 'orphan_alerted_at' => 2.hours.ago.iso8601 })

      expect { described_class.perform_now(account) }.to change(orphan_notifications, :count).by(2)
    end
  end
end
