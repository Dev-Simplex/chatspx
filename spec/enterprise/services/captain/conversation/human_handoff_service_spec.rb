require 'rails_helper'

# `aguardando_humano_desde` é o que põe a conversa na fila "Aguardando atendimento", e a
# limpeza dele reage a MUDANÇAS (assignee, espelho, resolve). Quando um humano já era dono no
# instante em que o marcador nasce, não há mudança futura a observar e a conversa fica presa.
# Medido na conv 4854 da Tozi: atribuída à consultora 09:33, marcada 09:34 — a fila insistia
# que ninguém atendia enquanto ela respondia o cliente.
RSpec.describe Captain::Conversation::HumanHandoffService do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  def handoff(reason: 'cliente pediu atendente')
    described_class.new(conversation: conversation, assistant: assistant, reason: reason).perform
    conversation.reload
  end

  context 'when nobody owns the conversation' do
    it 'marks it as awaiting a human, which is what puts it in the queue' do
      handoff

      expect(conversation.custom_attributes).to include('aguardando_humano_desde')
    end
  end

  context 'when a human already owns the conversation' do
    let(:agent) { create(:user, account: account, role: :agent) }

    before do
      create(:inbox_member, user: agent, inbox: inbox)
      conversation.update!(assignee: agent)
    end

    it 'does not announce a wait that nobody is waiting for' do
      handoff

      expect(conversation.custom_attributes).not_to include('aguardando_humano_desde')
    end

    # O resto do handoff continua: o contexto serve a quem vai atender.
    it 'still records the handoff note for whoever picks it up' do
      expect { handoff }.to change { conversation.messages.where(private: true).count }.by(1)
    end

    it 'keeps the human as the owner' do
      handoff

      expect(conversation.assignee_id).to eq(agent.id)
    end
  end
end
