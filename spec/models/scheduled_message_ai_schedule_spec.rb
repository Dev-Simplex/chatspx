require 'rails_helper'

# CHAT-165: a lista de conversas mostra um indicador quando há agendada da IA pendente. O horário
# vive em custom_attributes['agendada_ia_em'], que já vem no payload de cada conversa.
RSpec.describe ScheduledMessage do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:assistant) { create(:captain_assistant, account: account) }

  def agendada(quando:, assistant_id: assistant.id)
    described_class.create!(conversation: conversation, inbox: inbox, message: 'Texto', scheduled_at: quando,
                            status: :pending, captain_assistant_id: assistant_id)
  end

  def marcado
    conversation.reload.custom_attributes['agendada_ia_em']
  end

  it 'marca a conversa com o horário da próxima agendada da IA' do
    agendada(quando: 5.hours.from_now)
    primeira = agendada(quando: 2.hours.from_now)

    expect(Time.zone.parse(marcado)).to be_within(1.second).of(primeira.scheduled_at)
  end

  it 'passa para a seguinte quando a primeira sai de cena, e limpa quando não resta nenhuma' do
    depois = agendada(quando: 5.hours.from_now)
    antes = agendada(quando: 2.hours.from_now)

    antes.update!(status: :cancelled)
    expect(Time.zone.parse(marcado)).to be_within(1.second).of(depois.scheduled_at)

    depois.update!(status: :sent)
    expect(conversation.reload.custom_attributes).not_to have_key('agendada_ia_em')
  end

  it 'não marca agendada criada por pessoa' do
    agendada(quando: 2.hours.from_now, assistant_id: nil)

    expect(conversation.reload.custom_attributes).not_to have_key('agendada_ia_em')
  end

  it 'preserva os outros atributos da conversa' do
    conversation.update!(custom_attributes: { 'outro' => 'valor' })
    agendada(quando: 2.hours.from_now)

    expect(conversation.reload.custom_attributes['outro']).to eq('valor')
  end
end
