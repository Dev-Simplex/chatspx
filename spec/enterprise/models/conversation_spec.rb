require 'rails_helper'

RSpec.describe Conversation, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:sla_policy).optional }
  end

  describe 'SLA policy updates' do
    let(:conversation) { create(:conversation) }
    let!(:sla_policy) { create(:sla_policy, account: conversation.account) }

    before do
      stub_request(:get, %r{\Ahttps://www\.gravatar\.com.*}).to_return(status: 404)
      stub_request(:get, %r{\Ahttps://www\.google\.com/s2/favicons.*}).to_return(status: 404)
    end

    it 'generates an activity message when the SLA policy is updated' do
      conversation.update!(sla_policy_id: sla_policy.id)

      perform_enqueued_jobs

      activity_message = conversation.messages.where(message_type: 'activity').last

      expect(activity_message).not_to be_nil
      expect(activity_message.message_type).to eq('activity')
      expect(activity_message.content).to include('added SLA policy')
    end

    # TODO: Reenable this when we let the SLA policy be removed from a conversation
    # it 'generates an activity message when the SLA policy is removed' do
    #   conversation.update!(sla_policy_id: sla_policy.id)
    #   conversation.update!(sla_policy_id: nil)

    #   perform_enqueued_jobs

    #   activity_message = conversation.messages.where(message_type: 'activity').last

    #   expect(activity_message).not_to be_nil
    #   expect(activity_message.message_type).to eq('activity')
    #   expect(activity_message.content).to include('removed SLA policy')
    # end
  end

  describe 'sla_policy' do
    let(:account) { create(:account) }
    let(:conversation) { create(:conversation, account: account) }
    let(:sla_policy) { create(:sla_policy, account: account) }
    let(:different_account_sla_policy) { create(:sla_policy) }

    context 'when sla_policy is getting updated' do
      it 'throws error if sla policy belongs to different account' do
        conversation.sla_policy = different_account_sla_policy
        expect(conversation.valid?).to be false
        expect(conversation.errors[:sla_policy]).to include('sla policy account mismatch')
      end

      it 'creates applied sla record if sla policy is present' do
        conversation.sla_policy = sla_policy
        conversation.save!
        expect(conversation.applied_sla.sla_policy_id).to eq(sla_policy.id)
      end

      it 'throws error if contact is blocked' do
        conversation.contact.update!(blocked: true)
        conversation.sla_policy = sla_policy

        expect(conversation.valid?).to be false
        expect(conversation.errors[:sla_policy]).to eq(['cannot be assigned to conversations with blocked contacts'])
      end

      it 'allows assigning sla after contact is unblocked' do
        conversation.contact.update!(blocked: true)
        conversation.contact.update!(blocked: false)
        conversation.sla_policy = sla_policy

        conversation.save!

        expect(conversation.applied_sla.sla_policy_id).to eq(sla_policy.id)
      end

      it 'keeps existing behavior when contact is missing' do
        conversation.update_columns(contact_id: nil, contact_inbox_id: nil) # rubocop:disable Rails/SkipsModelValidations

        expect(conversation.reload.sla_applicable?).to be true
      end
    end

    context 'when conversation already has a different sla' do
      before do
        conversation.update(sla_policy: create(:sla_policy, account: account))
      end

      it 'throws error if trying to assing a different sla' do
        conversation.sla_policy = sla_policy
        expect(conversation.valid?).to be false
        expect(conversation.errors[:sla_policy]).to eq(['conversation already has a different sla'])
      end

      it 'throws error if trying to set sla to nil' do
        conversation.sla_policy = nil
        expect(conversation.valid?).to be false
        expect(conversation.errors[:sla_policy]).to eq(['cannot remove sla policy from conversation'])
      end
    end
  end

  describe 'assignment capacity limits' do
    describe 'team assignment with inbox auto-assignment disabled' do
      let(:account) { create(:account) }
      let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false, auto_assignment_config: { max_assignment_limit: 1 }) }
      let(:team) { create(:team, account: account, allow_auto_assign: true) }
      let!(:agent1) { create(:user, account: account, role: :agent, auto_offline: false) }
      let!(:agent2) { create(:user, account: account, role: :agent, auto_offline: false) }

      before do
        create(:inbox_member, inbox: inbox, user: agent1)
        create(:inbox_member, inbox: inbox, user: agent2)
        create(:team_member, team: team, user: agent1)
        create(:team_member, team: team, user: agent2)
        # Both agents are over the limit (simulate by assigning open conversations)
        create_list(:conversation, 2, inbox: inbox, assignee: agent1, status: :open)
        create_list(:conversation, 2, inbox: inbox, assignee: agent2, status: :open)
      end

      it 'does not enforce max_assignment_limit for team assignment when inbox auto-assignment is disabled' do
        conversation = create(:conversation, inbox: inbox, account: account, assignee: nil, status: :open)

        # Assign to team to trigger the assignment logic
        conversation.update!(team: team)

        # Should assign to a team member even if they are over the limit
        expect(conversation.reload.assignee).to be_present
        expect([agent1, agent2]).to include(conversation.reload.assignee)
      end
    end
  end

  # A2b — invariante de exclusividade: em NENHUM fluxo a conversa termina persistida com
  # assignee humano E espelho captain (assignee_id + assignee_agent_bot_id) ao mesmo tempo.
  describe 'captain mirror exclusivity invariant (A2b)' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account, enable_auto_assignment: true) }
    let(:agent) { create(:user, account: account, role: :agent, auto_offline: false) }
    let(:assistant) { create(:captain_assistant, account: account) }
    let(:mirror) { assistant.mirror_agent_bot }

    before do
      create(:inbox_member, inbox: inbox, user: agent)
    end

    context 'with direct save' do
      it 'clears the mirror when a human assignee is set on a conversation owned by the AI' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: nil, assignee_agent_bot: mirror)

        conversation.update!(assignee: agent)

        conversation.reload
        expect(conversation.assignee).to eq(agent)
        expect(conversation.assignee_agent_bot_id).to be_nil
      end

      it 'never persists human assignee and captain mirror together when both are set in one save' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: nil)

        conversation.update!(assignee: agent, assignee_agent_bot: mirror)

        conversation.reload
        expect(conversation.assignee_id.present? && conversation.assignee_agent_bot_id.present?).to be(false)
      end
    end

    context 'with legacy round-robin auto-assignment (assignment_v2 off, default)' do
      it 'does not steal a conversation owned by the captain mirror' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: nil, assignee_agent_bot: mirror)

        conversation.reload
        expect(conversation.assignee_id).to be_nil
        expect(conversation.assignee_agent_bot).to eq(mirror)
      end

      it 'still assigns conversations without a captain mirror (control)' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: nil)

        expect(conversation.reload.assignee).to eq(agent)
      end
    end

    context 'with team change (triage: team + mirror in the same automation)' do
      # Inbox sem round-robin: isola o caminho do team-change (ensure_assignee_is_from_team),
      # que dispara independente de enable_auto_assignment.
      let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
      let(:team) { create(:team, account: account, allow_auto_assign: true) }

      before do
        create(:team_member, team: team, user: agent)
      end

      it 'does not auto-assign a human from the team when the mirror owns the conversation' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: nil, assignee_agent_bot: mirror)

        conversation.update!(team: team)

        conversation.reload
        expect(conversation.assignee_id).to be_nil
        expect(conversation.assignee_agent_bot).to eq(mirror)
      end

      it 'preserves exclusivity when team and mirror are set in the same save' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: nil)

        conversation.update!(team: team, assignee_agent_bot: mirror)

        conversation.reload
        expect(conversation.assignee_id.present? && conversation.assignee_agent_bot_id.present?).to be(false)
        expect(conversation.assignee_agent_bot).to eq(mirror)
      end

      it 'still auto-assigns a team member when there is no captain mirror (control)' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: nil)

        conversation.update!(team: team)

        expect(conversation.reload.assignee).to eq(agent)
      end
    end

    context 'with V2 bulk auto-assignment' do
      before do
        account.enable_features!('assignment_v2')
        assignment_policy = create(:assignment_policy, account: account, enabled: true)
        create(:inbox_assignment_policy, inbox: inbox, assignment_policy: assignment_policy)
      end

      it 'does not steal a conversation owned by the captain mirror' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: nil, assignee_agent_bot: mirror)

        AutoAssignment::AssignmentService.new(inbox: inbox).perform_bulk_assignment

        conversation.reload
        expect(conversation.assignee_id).to be_nil
        expect(conversation.assignee_agent_bot).to eq(mirror)
      end
    end
  end

  # A2e — resolver a conversa limpa o dono-espelho captain (e SÓ ele): reopen nasce sem
  # dono e a triagem re-atribui. Snooze mantém; bot webhook e assignee humano preservados.
  describe 'release_captain_mirror_on_resolve (A2e)' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
    let(:assistant) { create(:captain_assistant, account: account) }
    let(:mirror) { assistant.mirror_agent_bot }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil, assignee_agent_bot: mirror) }

    it 'clears the captain mirror when the conversation is resolved' do
      conversation.update!(status: :resolved)

      expect(conversation.reload.assignee_agent_bot_id).to be_nil
    end

    it 'reopens without an owner after resolve' do
      conversation.update!(status: :resolved)
      conversation.update!(status: :open)

      expect(conversation.reload.assignee_agent_bot_id).to be_nil
    end

    it 'keeps the captain mirror on snooze' do
      conversation.update!(status: :snoozed, snoozed_until: 1.day.from_now)

      expect(conversation.reload.assignee_agent_bot).to eq(mirror)
    end

    it 'keeps a webhook bot assignment on resolve' do
      webhook_bot = create(:agent_bot, account: account)
      conversation.update!(assignee_agent_bot: webhook_bot)

      conversation.update!(status: :resolved)

      expect(conversation.reload.assignee_agent_bot).to eq(webhook_bot)
    end

    it 'does not touch the human assignee on resolve' do
      agent = create(:user, account: account, role: :agent)
      conversation.update!(assignee_agent_bot: nil, assignee: agent)

      conversation.update!(status: :resolved)

      expect(conversation.reload.assignee).to eq(agent)
    end
  end

  # A2d — setar o espelho captain numa conversa com incoming pendente cutuca o pipeline
  # (1º turno da triagem assíncrona + transferência IA->IA). Desatribuição/espelho->humano
  # não disparam; a resposta da IA não muda o dono -> sem loop.
  describe 'kick_captain_pipeline_after_mirror_assignment (A2d)' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
    let(:assistant) { create(:captain_assistant, account: account) }
    let(:mirror) { assistant.mirror_agent_bot }

    it 'enqueues the kick job when a mirror is assigned (nil -> mirror)' do
      conversation = create(:conversation, account: account, inbox: inbox, assignee: nil, assignee_agent_bot: nil)

      expect do
        conversation.update!(assignee_agent_bot: mirror)
      end.to have_enqueued_job(Captain::Conversation::AssignmentKickJob).with(conversation)
    end

    it 'enqueues on human -> mirror (assignee cleared so the mirror wins exclusivity)' do
      agent = create(:user, account: account, role: :agent)
      conversation = create(:conversation, account: account, inbox: inbox, assignee: agent)

      expect do
        conversation.update!(assignee: nil, assignee_agent_bot: mirror)
      end.to have_enqueued_job(Captain::Conversation::AssignmentKickJob)
    end

    it 'enqueues on mirror -> mirror (IA->IA transfer)' do
      other = create(:captain_assistant, account: account)
      conversation = create(:conversation, account: account, inbox: inbox, assignee: nil, assignee_agent_bot: mirror)

      expect do
        conversation.update!(assignee_agent_bot: other.mirror_agent_bot)
      end.to have_enqueued_job(Captain::Conversation::AssignmentKickJob)
    end

    it 'does NOT enqueue on mirror -> human (release)' do
      agent = create(:user, account: account, role: :agent)
      conversation = create(:conversation, account: account, inbox: inbox, assignee: nil, assignee_agent_bot: mirror)

      expect do
        conversation.update!(assignee: agent)
      end.not_to have_enqueued_job(Captain::Conversation::AssignmentKickJob)
    end

    it 'does NOT enqueue when the mirror is cleared (mirror -> nil)' do
      conversation = create(:conversation, account: account, inbox: inbox, assignee: nil, assignee_agent_bot: mirror)

      expect do
        conversation.update!(assignee_agent_bot: nil)
      end.not_to have_enqueued_job(Captain::Conversation::AssignmentKickJob)
    end

    it 'does NOT enqueue when a webhook bot is assigned (non-captain)' do
      webhook_bot = create(:agent_bot, account: account)
      conversation = create(:conversation, account: account, inbox: inbox, assignee: nil, assignee_agent_bot: nil)

      expect do
        conversation.update!(assignee_agent_bot: webhook_bot)
      end.not_to have_enqueued_job(Captain::Conversation::AssignmentKickJob)
    end
  end
end
