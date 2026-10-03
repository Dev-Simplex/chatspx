require 'rails_helper'

RSpec.describe Captain::Conversation::Reentrada do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:atendente) { create(:user, account: account) }

  def mensagem(tipo, instante, **attrs)
    create(:message, account: account, inbox: inbox, conversation: conversation,
                     message_type: tipo, content: 'oi', created_at: instante, **attrs)
  end

  def assumiu(instante)
    Captain::AssistantLog.create!(captain_assistant: assistant, conversation_id: conversation.id,
                                  event_type: 'mirror_assigned', created_at: instante)
  end

  it 'is nil when the AI never took over the conversation' do
    mensagem(:incoming, 2.hours.ago)

    expect(described_class.new(conversation: conversation).corte_id).to be_nil
  end

  # Conv 22777: o atendente falou na véspera; a portaria escreveu e a conversa voltou para a IA.
  it 'cuts at the last outgoing message before the AI took over, keeping what the contact sent while waiting' do
    mensagem(:incoming, 1.day.ago)
    ultima_do_humano = mensagem(:outgoing, 1.day.ago + 1.minute, sender: atendente)
    mensagem(:incoming, 10.minutes.ago)
    assumiu(10.minutes.ago + 1.second)

    expect(described_class.new(conversation: conversation).corte_id).to eq(ultima_do_humano.id)
  end

  it 'uses the most recent takeover' do
    mensagem(:incoming, 3.days.ago)
    assumiu(3.days.ago + 1.second)
    mensagem(:outgoing, 2.days.ago, sender: atendente)
    segunda = mensagem(:outgoing, 1.day.ago, sender: atendente)
    assumiu(1.hour.ago)

    expect(described_class.new(conversation: conversation).corte_id).to eq(segunda.id)
  end

  it 'is opt-in per account' do
    expect(described_class.enabled_for?(account)).to be(false)

    account.update!(custom_attributes: { 'captain_reentry_summary' => true })

    expect(described_class.enabled_for?(account)).to be(true)
  end
end
