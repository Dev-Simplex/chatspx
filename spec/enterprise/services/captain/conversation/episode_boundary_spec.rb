require 'rails_helper'

# CHAT-180 (conv 22777, conta 6): a portaria voltou 22h depois de uma conversa resolvida e a
# janela entregou à IA o atendimento da véspera inteiro. A resolução tem que cortar a janela
# do runtime mesmo depois que o cron gravou a segmentação do Eval, que não a enxerga.
RSpec.describe Captain::Conversation::EpisodeBoundary do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:inicio) { 23.hours.ago }
  let!(:reentrada) do
    mensagem(:outgoing, inicio)
    mensagem(:incoming, inicio + 1.minute)
    mensagem(:activity, inicio + 18.hours, 'Conversa marcada como resolvida por um atendente')
    mensagem(:incoming, inicio + 22.hours)
  end

  def mensagem(tipo, instante, conteudo = 'oi')
    create(:message, account: account, inbox: inbox, conversation: conversation,
                     message_type: tipo, content: conteudo, created_at: instante)
  end

  it 'starts the current attendance at the message after the resolution' do
    expect(described_class.new(conversation: conversation).atual.first_message_id).to eq(reentrada.id)
  end

  it 'still cuts at the resolution after the Eval cron has written its episodes' do
    Captain::EpisodeSegmenterService.new(conversation: conversation).perform

    fronteira = described_class.new(conversation: conversation)

    expect(fronteira.atual.first_message_id).to eq(reentrada.id)
    expect(fronteira.anteriores(limite: 3).map(&:boundary_reason)).to eq(['resolve'])
  end
end
