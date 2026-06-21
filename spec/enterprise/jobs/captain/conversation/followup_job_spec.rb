require 'rails_helper'

RSpec.describe Captain::Conversation::FollowupJob, type: :job do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:token) { 'followup-token-1' }
  let(:conversation) do
    create(:conversation, inbox: inbox, account: account, status: :open,
                          assignee_agent_bot: assistant.mirror_agent_bot,
                          custom_attributes: { 'followup_token' => token, 'followup_count' => 1 })
  end

  before do
    allow(Captain::Conversation::ResponseBuilderJob).to receive(:perform_now)
    # Última mensagem visível é da IA (lead sem responder) — pré-condição da cutucada.
    create(:message, conversation: conversation, account: account, inbox: inbox,
                     message_type: :outgoing, sender: assistant, content: 'Posso ajudar em algo mais?')
    # 11h em America/Cuiaba — fora das quiet hours (não remarca).
    travel_to Time.utc(2026, 6, 11, 15, 0)
  end

  context 'when the conversation is still owned by the assistant mirror' do
    it 'fires the nudge from the owner assistant and consumes token/followup_count' do
      described_class.perform_now(conversation, token)

      expect(Captain::Conversation::ResponseBuilderJob)
        .to have_received(:perform_now).with(conversation, assistant, directive: a_string_including('cutucada'))
      expect(conversation.reload.custom_attributes['followup_count']).to eq(2)
      expect(conversation.reload.custom_attributes['followup_token']).to be_nil
    end

    it 'no longer blocks on the atendimento_humano custom attribute (trava morta)' do
      conversation.update!(custom_attributes: conversation.custom_attributes.merge('atendimento_humano' => true))

      described_class.perform_now(conversation, token)

      expect(Captain::Conversation::ResponseBuilderJob).to have_received(:perform_now)
    end
  end

  context 'when the conversation was transferred to another assistant (IA→IA)' do
    it 'fires the nudge from the CURRENT owner, not the one that scheduled it' do
      other_assistant = create(:captain_assistant, account: account)
      conversation.update!(assignee_agent_bot: other_assistant.mirror_agent_bot)

      described_class.perform_now(conversation, token)

      expect(Captain::Conversation::ResponseBuilderJob)
        .to have_received(:perform_now).with(conversation, other_assistant, directive: kind_of(String))
    end
  end

  # A3 (nit 9): dono resolvido ANTES de consumir token/followup_count — cutucada que não
  # vai sair não gasta tentativa nem invalida o token.
  context 'when a human owns the conversation' do
    before do
      conversation.update!(assignee: agent)
    end

    it 'dies without firing and without consuming token or followup_count' do
      described_class.perform_now(conversation, token)

      expect(Captain::Conversation::ResponseBuilderJob).not_to have_received(:perform_now)
      expect(conversation.reload.custom_attributes['followup_count']).to eq(1)
      expect(conversation.reload.custom_attributes['followup_token']).to eq(token)
    end

    it 'does not move the card to Frio even with followups exhausted' do
      allow(Spx::Tozi::FunnelPlacementService).to receive(:move)
      conversation.update!(custom_attributes: conversation.custom_attributes.merge('followup_count' => described_class::MAX_FOLLOWUPS))

      described_class.perform_now(conversation, token)

      expect(Spx::Tozi::FunnelPlacementService).not_to have_received(:move)
      expect(conversation.reload.custom_attributes['followup_token']).to eq(token)
    end
  end

  context 'when the conversation has no owner' do
    it 'dies without firing and without consuming the token' do
      conversation.update!(assignee_agent_bot: nil)

      described_class.perform_now(conversation, token)

      expect(Captain::Conversation::ResponseBuilderJob).not_to have_received(:perform_now)
      expect(conversation.reload.custom_attributes['followup_token']).to eq(token)
    end
  end

  context 'when followups are exhausted and the AI still owns the conversation' do
    it 'cools the lead and moves the card to Frio' do
      allow(Spx::Tozi::FunnelPlacementService).to receive(:move)
      reactivation = instance_double(Spx::Tozi::ReactivationCadenceService, perform: true)
      allow(Spx::Tozi::ReactivationCadenceService).to receive(:new).and_return(reactivation)
      conversation.update!(custom_attributes: conversation.custom_attributes.merge('followup_count' => described_class::MAX_FOLLOWUPS))

      described_class.perform_now(conversation, token)

      expect(conversation.reload.custom_attributes['tozi_status_lead']).to eq('esfriado')
      expect(Spx::Tozi::FunnelPlacementService).to have_received(:move).with(conversation: conversation, to: 'frio')
      expect(Captain::Conversation::ResponseBuilderJob).not_to have_received(:perform_now)
    end
  end

  context 'when the token is stale (replaced by a newer followup)' do
    it 'does nothing' do
      described_class.perform_now(conversation, 'another-token')

      expect(Captain::Conversation::ResponseBuilderJob).not_to have_received(:perform_now)
      expect(conversation.reload.custom_attributes['followup_count']).to eq(1)
    end
  end
end
