require 'rails_helper'

describe CaptainListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:captain_assistant, account: account, config: { feature_memory: true, feature_faq: true }) }
  let(:mirror) { assistant.mirror_agent_bot }

  describe '#conversation_resolved' do
    # No human assignee: a conversa pertence ao espelho captain (a invariante de
    # exclusividade limparia o espelho se um humano fosse o assignee).
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }

    let(:event_name) { :conversation_resolved }
    let(:event) { Events::Base.new(event_name, Time.zone.now, conversation: conversation) }

    before do
      create(:captain_inbox, captain_assistant: assistant, inbox: inbox)
    end

    context 'when the conversation is owned by the assistant mirror' do
      before do
        conversation.update!(assignee_agent_bot: mirror)
      end

      context 'when feature_memory is enabled' do
        before do
          assistant.config['feature_memory'] = true
          assistant.config['feature_faq'] = false
          assistant.save!
        end

        it 'generates and updates notes' do
          expect(Captain::Llm::ContactNotesService)
            .to receive(:new)
            .with(assistant, conversation)
            .and_return(instance_double(Captain::Llm::ContactNotesService, generate_and_update_notes: nil))
          expect(Captain::Llm::ConversationFaqService).not_to receive(:new)

          listener.conversation_resolved(event)
        end
      end

      context 'when feature_faq is enabled' do
        before do
          assistant.config['feature_faq'] = true
          assistant.config['feature_memory'] = false
          assistant.save!
        end

        it 'generates and deduplicates FAQs' do
          expect(Captain::Llm::ConversationFaqService)
            .to receive(:new)
            .with(assistant, conversation)
            .and_return(instance_double(Captain::Llm::ConversationFaqService, generate_and_deduplicate: false))
          expect(Captain::Llm::ContactNotesService).not_to receive(:new)

          listener.conversation_resolved(event)
        end
      end
    end

    context 'when the mirror was already detached but the assistant participated (post-handoff)' do
      # A2e: resolver limpa o dono-espelho; o assistant é recuperado pelo participante
      # (última mensagem com sender Captain::Assistant).
      before do
        assistant.config['feature_memory'] = true
        assistant.config['feature_faq'] = false
        assistant.save!
        create(:message, account: account, inbox: inbox, conversation: conversation,
                         message_type: :outgoing, sender: assistant, content: 'How can I help?')
      end

      it 'resolves the assistant via the last Captain::Assistant sender' do
        expect(Captain::Llm::ContactNotesService)
          .to receive(:new)
          .with(assistant, conversation)
          .and_return(instance_double(Captain::Llm::ContactNotesService, generate_and_update_notes: nil))

        listener.conversation_resolved(event)
      end
    end

    context 'when no assistant owns or participated in the conversation' do
      it 'is a no-op' do
        expect(Captain::Llm::ContactNotesService).not_to receive(:new)
        expect(Captain::Llm::ConversationFaqService).not_to receive(:new)

        listener.conversation_resolved(event)
      end
    end

    # Spec conjunto A2e x A4: resolver a conversa LIMPA o dono-espelho (A2e). O evento
    # conversation_resolved dispara DEPOIS do commit, então o assistant precisa ser
    # recuperado pelo participante (A4) — a última mensagem com sender Captain::Assistant.
    context 'when the conversation is resolved while owned by the mirror (A2e x A4)' do
      before do
        assistant.config['feature_memory'] = true
        assistant.config['feature_faq'] = false
        assistant.save!
        conversation.update!(assignee_agent_bot: mirror)
        create(:message, account: account, inbox: inbox, conversation: conversation,
                         message_type: :outgoing, sender: assistant, content: 'How can I help?')
      end

      it 'clears the mirror owner on resolve yet resolves the assistant via the participant' do
        conversation.resolved!

        expect(conversation.reload.assignee_agent_bot_id).to be_nil

        expect(Captain::Llm::ContactNotesService)
          .to receive(:new)
          .with(assistant, conversation)
          .and_return(instance_double(Captain::Llm::ContactNotesService, generate_and_update_notes: nil))

        listener.conversation_resolved(event)
      end
    end
  end
end
