require 'rails_helper'

RSpec.describe Captain::Tools::TransferirParaAgenteTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account, name: 'Bruna Vendas') }
  let(:target_assistant) { create(:captain_assistant, account: account, name: 'Leo Locacao', description: 'Especialista em locacao') }
  let(:tool) { described_class.new(assistant) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:tool_context) { Struct.new(:state).new({ conversation: { id: conversation.id } }) }

  describe '#description' do
    it 'enumerates the other assistants of the account (id: name — specialty)' do
      target_assistant

      description = tool.description

      expect(description).to include('Transfer this conversation to another AI agent')
      expect(description).to include("#{target_assistant.id}: Leo Locacao — Especialista em locacao")
      expect(description).not_to include("#{assistant.id}: Bruna Vendas")
    end

    it 'instructs the LLM not to announce the transfer (DC-7, transferência silenciosa)' do
      expect(tool.description).to include('Do NOT write any message after calling this tool')
    end
  end

  describe '#parameters' do
    it 'declares assistant_id (required) and reason (optional)' do
      expect(tool.parameters[:assistant_id].type).to eq('string')
      expect(tool.parameters[:assistant_id].required).to be true
      expect(tool.parameters[:reason].required).to be false
    end
  end

  describe '#perform' do
    context 'when the target assistant is eligible for the inbox' do
      before do
        create(:captain_inbox, captain_assistant: assistant, inbox: inbox)
        create(:captain_inbox, captain_assistant: target_assistant, inbox: inbox)
      end

      it 'assigns the target mirror clearing the human assignee in the same save' do
        agent = create(:user, account: account)
        create(:inbox_member, inbox: inbox, user: agent)
        conversation.update!(assignee: agent)

        result = tool.perform(tool_context, assistant_id: target_assistant.id.to_s)

        expect(result).to eq("Conversation transferred to #{target_assistant.name}")
        conversation.reload
        expect(conversation.assignee_agent_bot).to eq(target_assistant.mirror_agent_bot)
        expect(conversation.assignee_id).to be_nil
      end

      it 'enqueues the AssignmentKickJob so the new AI answers the pending incoming (DC-7)' do
        expect do
          tool.perform(tool_context, assistant_id: target_assistant.id.to_s)
        end.to have_enqueued_job(Captain::Conversation::AssignmentKickJob)
      end

      it 'creates the mirror on demand when missing' do
        target_assistant.agent_bot&.destroy!
        target_assistant.reload

        tool.perform(tool_context, assistant_id: target_assistant.id.to_s)

        mirror = conversation.reload.assignee_agent_bot
        expect(mirror).to be_present
        expect(mirror.captain_assistant_id).to eq(target_assistant.id)
      end

      it 'creates a private audit note when a reason is given' do
        expect do
          tool.perform(tool_context, assistant_id: target_assistant.id.to_s, reason: 'cliente quer alugar')
        end.to change(Message, :count).by(1)

        note = conversation.messages.last
        expect(note.private).to be true
        expect(note.content).to eq("Transferido para #{target_assistant.name}: cliente quer alugar")
        expect(note.sender).to eq(assistant)
      end

      it 'does not create any visible message (transferência silenciosa, DC-7)' do
        expect do
          tool.perform(tool_context, assistant_id: target_assistant.id.to_s)
        end.not_to change(Message, :count)
      end
    end

    context 'with invalid targets' do
      before do
        create(:captain_inbox, captain_assistant: assistant, inbox: inbox)
      end

      it 'rejects transferring to itself' do
        result = tool.perform(tool_context, assistant_id: assistant.id.to_s)

        expect(result).to eq('Cannot transfer to self')
        expect(conversation.reload.assignee_agent_bot_id).to be_nil
      end

      it 'rejects an assistant from another account' do
        foreign_assistant = create(:captain_assistant)

        result = tool.perform(tool_context, assistant_id: foreign_assistant.id.to_s)

        expect(result).to eq('Assistant not found')
        expect(conversation.reload.assignee_agent_bot_id).to be_nil
      end

      it 'rejects an unknown assistant id' do
        result = tool.perform(tool_context, assistant_id: '999999')

        expect(result).to eq('Assistant not found')
      end

      it 'rejects an assistant not eligible for the conversation inbox' do
        result = tool.perform(tool_context, assistant_id: target_assistant.id.to_s)

        expect(result).to eq('Assistant is not eligible for this inbox')
        expect(conversation.reload.assignee_agent_bot_id).to be_nil
      end
    end

    context 'when conversation does not exist' do
      let(:tool_context) { Struct.new(:state).new({ conversation: { id: 999_999 } }) }

      it 'returns error message' do
        expect(tool.perform(tool_context, assistant_id: target_assistant.id.to_s)).to eq('Conversation not found')
      end
    end
  end

  describe 'registry (tools.yml + resolução por convenção)' do
    it 'is registered as a built-in agent tool' do
      tool_ids = Captain::Assistant.built_in_tool_ids
      expect(tool_ids).to include('transferir_para_agente')
    end

    it 'resolves the class from the snake_case id' do
      expect(Captain::Assistant.resolve_tool_class('transferir_para_agente')).to eq(described_class)
    end
  end

  describe '#active?' do
    it 'returns true for public tools' do
      expect(tool.active?).to be true
    end
  end
end
