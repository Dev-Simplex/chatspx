require 'rails_helper'

RSpec.describe Conversations::QueueEscalationJob do
  subject(:job) { described_class.perform_later(account) }

  let!(:account) { create(:account, settings: { reply_assignment_gate: true }) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:other_admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:team) { create(:team, account: account) }

  def escalation_notifications
    Notification.where(notification_type: 'conversation_orphaned', account_id: account.id)
  end

  # Conversa "aguardando atendimento" na fila do time:
  # open + sem dono humano + sem espelho captain + com team_id.
  def create_queued(last_activity_at: 30.minutes.ago, conv_team: team)
    conversation = create(:conversation, account: account, inbox: inbox, status: :open,
                                         assignee: nil, team: conv_team)
    conversation.update_columns(last_activity_at: last_activity_at) # rubocop:disable Rails/SkipsModelValidations
    conversation
  end

  # Por padrão: o time TEM um agente online (para isolar o teste de tempo).
  def stub_online(user_ids)
    allow(OnlineStatusTracker).to receive(:get_available_users)
      .with(account.id)
      .and_return(user_ids.index_with { 'online' })
  end

  def add_to_team(user, on_team: team)
    create(:team_member, user: user, team: on_team)
  end

  before do
    add_to_team(agent)
    stub_online([agent.id]) # time online por padrão
  end

  it 'enqueues the job on the low queue' do
    expect { job }.to have_enqueued_job(described_class).on_queue('low')
  end

  describe 'escalation by time (> 10 min waiting, team online)' do
    it 'escalates a conversation waiting more than the default 10 minutes' do
      conversation = create_queued(last_activity_at: 30.minutes.ago)

      expect { described_class.perform_now(account) }.to change(escalation_notifications, :count).by(2)
      expect(conversation.reload.custom_attributes['fila_escalada_em']).to be_present
    end

    it 'does NOT escalate a conversation waiting less than 10 minutes when team is online' do
      conversation = create_queued(last_activity_at: 5.minutes.ago)

      expect { described_class.perform_now(account) }.not_to change(escalation_notifications, :count)
      expect(conversation.reload.custom_attributes['fila_escalada_em']).to be_nil
    end

    it 'respects a custom queue_escalation_after window from account settings' do
      account.update!(queue_escalation_after: 2)
      conversation = create_queued(last_activity_at: 5.minutes.ago)

      expect { described_class.perform_now(account) }.to change(escalation_notifications, :count).by(2)
      expect(conversation.reload.custom_attributes['fila_escalada_em']).to be_present
    end

    it 'notifies every admin (and only admins) once' do
      create_queued(last_activity_at: 30.minutes.ago)

      described_class.perform_now(account)

      expect(escalation_notifications.pluck(:user_id)).to contain_exactly(admin.id, other_admin.id)
      expect(escalation_notifications.where(user_id: agent.id)).to be_empty
    end
  end

  describe 'escalation by team with no one online (even < 10 min)' do
    it 'escalates immediately when no team member is online' do
      stub_online([]) # ninguém online na conta
      conversation = create_queued(last_activity_at: 1.minute.ago)

      expect { described_class.perform_now(account) }.to change(escalation_notifications, :count).by(2)
      expect(conversation.reload.custom_attributes['fila_escalada_em']).to be_present
    end

    it 'escalates immediately when online users belong to OTHER teams only' do
      other_team = create(:team, account: account)
      other_agent = create(:user, account: account, role: :agent)
      add_to_team(other_agent, on_team: other_team)
      stub_online([other_agent.id]) # online, mas não no time da conversa
      conversation = create_queued(last_activity_at: 1.minute.ago, conv_team: team)

      expect { described_class.perform_now(account) }.to change(escalation_notifications, :count).by(2)
      expect(conversation.reload.custom_attributes['fila_escalada_em']).to be_present
    end

    it 'does NOT escalate (< 10 min) when the conversation team has an online member' do
      conversation = create_queued(last_activity_at: 1.minute.ago, conv_team: team)
      # agent já está online e no time (setup do before)

      expect { described_class.perform_now(account) }.not_to change(escalation_notifications, :count)
      expect(conversation.reload.custom_attributes['fila_escalada_em']).to be_nil
    end
  end

  describe 'dedup (escalates only once per conversation)' do
    it 'does not re-notify on a subsequent run' do
      create_queued(last_activity_at: 30.minutes.ago)

      expect { described_class.perform_now(account) }.to change(escalation_notifications, :count).by(2)
      expect { described_class.perform_now(account) }.not_to change(escalation_notifications, :count)
    end
  end

  describe 'scope (only queued conversations in fila por time)' do
    it 'ignores conversations assigned to a human (sai do escopo quando assumida)' do
      conversation = create_queued(last_activity_at: 30.minutes.ago)
      conversation.update!(assignee: agent)

      expect { described_class.perform_now(account) }.not_to change(escalation_notifications, :count)
      expect(conversation.reload.custom_attributes['fila_escalada_em']).to be_nil
    end

    it 'ignores conversations still mirrored to a captain (IA recapturou)' do
      assistant = create(:captain_assistant, account: account)
      conversation = create(:conversation, account: account, inbox: inbox, status: :open,
                                           assignee: nil, team: team,
                                           assignee_agent_bot: assistant.mirror_agent_bot)
      conversation.update_columns(last_activity_at: 30.minutes.ago) # rubocop:disable Rails/SkipsModelValidations

      expect { described_class.perform_now(account) }.not_to change(escalation_notifications, :count)
    end

    it 'ignores conversations without a team_id (não estão na fila por time)' do
      conversation = create_queued(last_activity_at: 30.minutes.ago, conv_team: nil)

      expect { described_class.perform_now(account) }.not_to change(escalation_notifications, :count)
      expect(conversation.reload.custom_attributes['fila_escalada_em']).to be_nil
    end

    it 'ignores resolved conversations' do
      conversation = create_queued(last_activity_at: 30.minutes.ago)
      conversation.update!(status: :resolved)

      expect { described_class.perform_now(account) }.not_to change(escalation_notifications, :count)
    end
  end

  describe 'classic mode (reply_assignment_gate OFF) never escalates' do
    let!(:account) { create(:account, settings: { reply_assignment_gate: false }) }

    it 'does nothing for accounts without the gate' do
      conversation = create_queued(last_activity_at: 30.minutes.ago)

      expect { described_class.perform_now(account) }.not_to change(escalation_notifications, :count)
      expect(conversation.reload.custom_attributes['fila_escalada_em']).to be_nil
    end
  end
end
