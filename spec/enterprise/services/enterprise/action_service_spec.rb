require 'rails_helper'

describe ActionService do
  let(:account) { create(:account) }

  describe '#add_sla' do
    let(:sla_policy) { create(:sla_policy, account: account) }
    let(:conversation) { create(:conversation, account: account) }
    let(:action_service) { described_class.new(conversation) }

    context 'when sla_policy_id is present' do
      it 'adds the sla policy to the conversation and create applied_sla entry' do
        action_service.add_sla([sla_policy.id])
        expect(conversation.reload.sla_policy_id).to eq(sla_policy.id)

        # check if appliedsla table entry is created with matching attributes
        applied_sla = AppliedSla.last
        expect(applied_sla.account_id).to eq(account.id)
        expect(applied_sla.sla_policy_id).to eq(sla_policy.id)
        expect(applied_sla.conversation_id).to eq(conversation.id)
        expect(applied_sla.sla_status).to eq('active')
      end

      it 'does not add the sla policy when contact is blocked' do
        conversation.contact.update!(blocked: true)

        expect { action_service.add_sla([sla_policy.id]) }.not_to change(AppliedSla, :count)
        expect(conversation.reload.sla_policy_id).to be_nil
      end
    end

    context 'when sla_policy_id is not present' do
      it 'does not add the sla policy to the conversation' do
        action_service.add_sla(nil)
        expect(conversation.reload.sla_policy_id).to be_nil
      end
    end

    context 'when conversation already has a sla policy' do
      it 'does not add the new sla policy to the conversation' do
        existing_sla_policy = sla_policy
        new_sla_policy = create(:sla_policy, account: account)
        conversation.update!(sla_policy_id: existing_sla_policy.id)
        action_service.add_sla([new_sla_policy.id])
        expect(conversation.reload.sla_policy_id).to eq(existing_sla_policy.id)
      end
    end

    context 'when sla_policy is not found' do
      it 'does not add the sla policy to the conversation' do
        action_service.add_sla([sla_policy.id + 1])
        expect(conversation.reload.sla_policy_id).to be_nil
      end
    end
  end

  describe '#assign_ai_agent' do
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }
    let(:assistant) { create(:captain_assistant, account: account) }
    let(:action_service) { described_class.new(conversation) }

    context 'when the assistant is eligible for the inbox' do
      before do
        create(:captain_inbox, captain_assistant: assistant, inbox: inbox)
      end

      it 'assigns the captain mirror clearing the human assignee in the same save' do
        agent = create(:user, account: account)
        create(:inbox_member, inbox: inbox, user: agent)
        conversation.update!(assignee: agent)

        action_service.assign_ai_agent([assistant.id])

        conversation.reload
        expect(conversation.assignee_agent_bot).to eq(assistant.mirror_agent_bot)
        expect(conversation.assignee_id).to be_nil
      end

      it 'creates the mirror on demand when missing' do
        assistant.agent_bot&.destroy!
        assistant.reload

        action_service.assign_ai_agent([assistant.id])

        mirror = conversation.reload.assignee_agent_bot
        expect(mirror).to be_present
        expect(mirror.captain_assistant_id).to eq(assistant.id)
        expect(mirror).to be_captain
      end

      it 'enqueues the AssignmentKickJob (after_commit da Fase A)' do
        expect do
          action_service.assign_ai_agent([assistant.id])
        end.to have_enqueued_job(Captain::Conversation::AssignmentKickJob).with(conversation)
      end
    end

    context 'with invalid params (no-op silencioso, padrão add_sla)' do
      it 'does nothing when assistant_ids is blank' do
        action_service.assign_ai_agent(nil)
        expect(conversation.reload.assignee_agent_bot_id).to be_nil
      end

      it 'does nothing for an unknown assistant id' do
        action_service.assign_ai_agent([assistant.id + 1000])
        expect(conversation.reload.assignee_agent_bot_id).to be_nil
      end

      it 'does nothing for an assistant from another account' do
        other_assistant = create(:captain_assistant)
        create(:captain_inbox, captain_assistant: assistant, inbox: inbox)

        action_service.assign_ai_agent([other_assistant.id])

        expect(conversation.reload.assignee_agent_bot_id).to be_nil
      end

      it 'does nothing when the assistant is not eligible for the conversation inbox' do
        action_service.assign_ai_agent([assistant.id])
        expect(conversation.reload.assignee_agent_bot_id).to be_nil
      end
    end
  end

  # Ordem segura da triagem (C5/A2b): assign_ai_agent ANTES de assign_team — o guard A2b
  # impede o auto-assign humano do time quando o espelho captain já é o dono.
  describe 'automation rule with assign_ai_agent followed by assign_team' do
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }
    let(:assistant) { create(:captain_assistant, account: account) }
    let(:team) { create(:team, account: account, allow_auto_assign: true) }
    let(:team_user) { create(:user, account: account) }

    before do
      create(:captain_inbox, captain_assistant: assistant, inbox: inbox)
      create(:inbox_member, inbox: inbox, user: team_user)
      create(:team_member, team: team, user: team_user)
      allow(OnlineStatusTracker).to receive(:get_available_users)
        .and_return({ team_user.id.to_s => 'online' })
    end

    it 'ends with the mirror as owner, the team set and no human assignee (guard A2b)' do
      rule = create(:automation_rule, account: account, event_name: 'conversation_created',
                                      actions: [
                                        { 'action_name' => 'assign_ai_agent', 'action_params' => [assistant.id] },
                                        { 'action_name' => 'assign_team', 'action_params' => [team.id] }
                                      ])

      AutomationRules::ActionService.new(rule, account, conversation).perform

      conversation.reload
      expect(conversation.assignee_agent_bot).to eq(assistant.mirror_agent_bot)
      expect(conversation.assignee_id).to be_nil
      expect(conversation.team_id).to eq(team.id)
    end
  end
end
