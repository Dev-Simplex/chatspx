require 'rails_helper'

# E4 (Fase E) — trilha de auditoria da atribuição do espelho captain no AssistantLog:
# o watcher after_commit em Enterprise::Concerns::Conversation loga quem (IA) assumiu/
# soltou cada conversa e por quê. O assistant do release é capturado pelo valor ANTIGO
# do saved_change (o espelho captain tem captain_assistant_id NOT NULL).
# Arquivo nomeado pelo design (fase-d-design.md §10.3) — descreve Conversation de propósito.
RSpec.describe Conversation, type: :model do # rubocop:disable RSpec/SpecFilePathFormat
  describe 'captain mirror assignment telemetry (E4)' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
    let(:agent) { create(:user, account: account, role: :agent) }
    let(:assistant) { create(:captain_assistant, account: account) }
    let(:mirror) { assistant.mirror_agent_bot }

    def telemetry_logs(event_type = nil)
      scope = Captain::AssistantLog.where(event_type: %w[mirror_assigned mirror_released human_takeover])
      event_type ? scope.where(event_type: event_type) : scope
    end

    describe 'mirror_assigned' do
      it 'logs when the mirror takes an unowned conversation' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: nil)

        expect do
          conversation.update!(assignee_agent_bot: mirror)
        end.to change { telemetry_logs('mirror_assigned').count }.by(1)

        log = telemetry_logs('mirror_assigned').ordered.first
        expect(log.captain_assistant).to eq(assistant)
        expect(log.conversation).to eq(conversation)
        expect(log.payload['previous_agent_bot_id']).to be_nil
      end

      it 'logs the previous mirror in the payload on AI -> AI transfer (and does not log a release)' do
        other_assistant = create(:captain_assistant, account: account)
        conversation = create(:conversation, account: account, inbox: inbox, assignee: nil, assignee_agent_bot: mirror)

        expect do
          conversation.update!(assignee_agent_bot: other_assistant.mirror_agent_bot)
        end.to change { telemetry_logs('mirror_assigned').count }.by(1)
                                                                 .and(not_change { telemetry_logs('mirror_released').count })

        log = telemetry_logs('mirror_assigned').ordered.first
        expect(log.captain_assistant).to eq(other_assistant)
        expect(log.payload['previous_agent_bot_id']).to eq(mirror.id)
      end
    end

    describe 'mirror_released' do
      it 'logs with reason resolve when resolving clears the mirror (A2e)' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: nil, assignee_agent_bot: mirror)

        expect do
          conversation.update!(status: :resolved)
        end.to change { telemetry_logs('mirror_released').count }.by(1)

        log = telemetry_logs('mirror_released').ordered.first
        expect(log.captain_assistant).to eq(assistant) # capturado pelo valor ANTIGO do saved_change
        expect(log.conversation).to eq(conversation)
        expect(log.payload).to include('reason' => 'resolve', 'new_assignee_id' => nil)
      end

      it 'logs with reason unassigned when the mirror is removed without a new owner (automation/None)' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: nil, assignee_agent_bot: mirror)

        expect do
          conversation.update!(assignee_agent_bot: nil)
        end.to change { telemetry_logs('mirror_released').count }.by(1)

        log = telemetry_logs('mirror_released').ordered.first
        expect(log.payload).to include('reason' => 'unassigned', 'new_assignee_id' => nil)
      end
    end

    describe 'human_takeover' do
      it 'logs with reason assignment when a human assignee resets the mirror (core reset / dialog D2)' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: nil, assignee_agent_bot: mirror)

        expect do
          conversation.update!(assignee: agent)
        end.to change { telemetry_logs('human_takeover').count }.by(1)

        log = telemetry_logs('human_takeover').ordered.first
        expect(log.captain_assistant).to eq(assistant)
        expect(log.payload).to include('reason' => 'assignment', 'new_assignee_id' => agent.id)
      end

      it 'logs with reason reply when a human replies without assigning themselves (A2c)' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: nil, assignee_agent_bot: mirror)

        expect do
          create(:message, message_type: :outgoing, conversation: conversation)
        end.to change { telemetry_logs('human_takeover').count }.by(1)

        log = telemetry_logs('human_takeover').ordered.first
        expect(log.payload).to include('reason' => 'reply', 'new_assignee_id' => nil)
      end
    end

    describe 'guards' do
      it 'does not log when only the human assignee changes (assign_agent nil keeps the mirror untouched)' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: agent)

        expect do
          conversation.update!(assignee_id: nil)
        end.not_to(change(telemetry_logs, :count))
      end

      it 'ignores webhook bots (no captain assistant) without raising' do
        webhook_bot = create(:agent_bot, account: account)
        conversation = create(:conversation, account: account, inbox: inbox, assignee: nil)

        expect do
          conversation.update!(assignee_agent_bot: webhook_bot)
          conversation.update!(assignee_agent_bot: nil)
        end.not_to(change(telemetry_logs, :count))
      end

      it 'does not log when the transaction rolls back (after_commit)' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: nil)
        mirror # cria assistant + espelho FORA da transação revertida

        expect do
          ActiveRecord::Base.transaction do
            conversation.update!(assignee_agent_bot: mirror)
            raise ActiveRecord::Rollback
          end
        end.not_to(change(telemetry_logs, :count))
      end

      it 'does not break the assignment when logging fails' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: nil)
        allow(Captain::AssistantLog).to receive(:create!).and_raise(StandardError, 'boom')

        expect { conversation.update!(assignee_agent_bot: mirror) }.not_to raise_error
        expect(conversation.reload.assignee_agent_bot).to eq(mirror)
      end
    end
  end
end
