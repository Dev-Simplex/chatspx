require 'rails_helper'

# O pin do escritório vem SÓ da configuração da própria conta. Já houve um último recurso com o
# escritório de um cliente, e a IA de outra conta mandou o endereço dele: pin errado manda a
# pessoa para o lugar errado. Sem configuração, nenhuma mensagem sai.
RSpec.describe Captain::Tools::EnviarLocalizacaoTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:conversation) { create(:conversation, account: account) }
  let(:contexto) { Struct.new(:state).new({ conversation: { id: conversation.id } }) }

  def escritorio(conta, lat:, lng:, nome: nil)
    AccountIntegration.create!(account: conta, provider: 'vista',
                               settings: { 'office_lat' => lat, 'office_lng' => lng, 'office_name' => nome }.compact)
  end

  context 'quando a conta não configurou o escritório' do
    before { escritorio(create(:account), lat: '-12.545', lng: '-55.711', nome: 'Outra conta') }

    it 'não envia pin e avisa o modelo que o endereço não está configurado' do
      resposta = nil
      expect { resposta = tool.perform(contexto) }.not_to(change { Message.count })

      expect(resposta).to include('não está configurado')
      expect(Attachment.where(file_type: :location)).to be_empty
    end

    it 'não envia pin quando falta uma das coordenadas' do
      escritorio(account, lat: '-12.545', lng: '')

      expect { tool.perform(contexto) }.not_to(change { Message.count })
    end
  end

  context 'quando a conta configurou o escritório' do
    before do
      escritorio(account, lat: '-15.601', lng: '-56.097', nome: 'Escritório da conta')
      escritorio(create(:account), lat: '-12.545', lng: '-55.711', nome: 'Outra conta')
    end

    it 'envia o pin com as coordenadas e o nome da própria conta' do
      expect { tool.perform(contexto) }.to change { conversation.messages.count }.by(1)

      anexo = conversation.messages.last.attachments.last
      expect(anexo.file_type).to eq('location')
      expect(anexo.coordinates_lat).to be_within(0.001).of(-15.601)
      expect(anexo.coordinates_long).to be_within(0.001).of(-56.097)
      expect(anexo.fallback_title).to eq('Escritório da conta')
    end
  end
end
