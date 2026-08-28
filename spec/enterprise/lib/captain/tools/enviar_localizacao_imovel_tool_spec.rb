require 'rails_helper'

# Régua do cliente (28/08): em LOCAÇÃO o pin é o do imóvel; em VENDA é o do BAIRRO, porque a
# coordenada exata de um imóvel à venda é o insumo que um concorrente usa pra ir captar o
# imóvel direto com o proprietário. Medido em produção: 7 dos 33 pins enviados em 30 dias
# eram de imóveis à venda.
RSpec.describe Captain::Tools::EnviarLocalizacaoImovelTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }

  # Aquarela das Artes: bairro real de Sinop. O ponto do imóvel fica a poucas centenas de
  # metros do centroide do bairro — é o caso bom.
  let(:centroide_bairro) { { lat: -11.8343912, lng: -55.546244 } }
  let(:imovel_lat) { -11.8352 }
  let(:imovel_lng) { -55.5471 }

  def vista_responde(status:, bairro: 'Residencial Aquarela Das Artes')
    body = { 'Codigo' => '9908', 'Categoria' => 'Casa', 'Status' => status, 'Bairro' => bairro,
             'BairroComercial' => bairro, 'Latitude' => imovel_lat.to_s, 'Longitude' => imovel_lng.to_s }
    instance_double(HTTParty::Response, code: 200, parsed_response: body)
  end

  before do
    allow(tool).to receive_messages(vista_base_url: 'https://vista.test', vista_api_key: 'k',
                                    google_maps_key: 'g', geo_city: 'Sinop MT')
  end

  describe '#fetch_coordinates' do
    it 'sends the property pin for a rental' do
      allow(HTTParty).to receive(:get).and_return(vista_responde(status: 'Aluguel'))

      lat, lng, nome, escopo = tool.send(:fetch_coordinates, '9908')

      expect([lat, lng]).to eq([imovel_lat, imovel_lng])
      expect(nome).to include('9908')
      expect(escopo).to eq(:imovel)
    end

    it 'sends the neighbourhood pin for a sale, titled with the neighbourhood' do
      allow(HTTParty).to receive(:get).and_return(vista_responde(status: 'Venda'))
      allow(tool).to receive(:geocode_bairro).and_return(centroide_bairro)

      lat, lng, nome, escopo = tool.send(:fetch_coordinates, '9908')

      expect([lat, lng]).to eq([centroide_bairro[:lat], centroide_bairro[:lng]])
      expect(nome).to eq('Residencial Aquarela Das Artes')
      expect(nome).not_to include('9908')
      expect(escopo).to eq(:bairro)
    end

    # O Google devolve homônimo de outra cidade em vez de dizer que não achou. O acervo
    # entra como VERIFICADOR: se o centroide cai longe do imóvel real, não sai pin nenhum.
    it 'sends no pin when the geocoded neighbourhood lands far from the real property' do
      allow(HTTParty).to receive(:get).and_return(vista_responde(status: 'Venda'))
      allow(tool).to receive(:geocode_bairro).and_return({ lat: -19.9166813, lng: -43.9344931 })

      expect(tool.send(:fetch_coordinates, '9908')).to eq(described_class::SEM_PIN)
    end

    it 'sends no pin for a sale when the neighbourhood does not geocode' do
      allow(HTTParty).to receive(:get).and_return(vista_responde(status: 'Venda'))
      allow(tool).to receive(:geocode_bairro).and_return(nil)

      expect(tool.send(:fetch_coordinates, '9908')).to eq(described_class::SEM_PIN)
    end

    it 'sends no pin for a sale with no neighbourhood on file' do
      allow(HTTParty).to receive(:get).and_return(vista_responde(status: 'Venda', bairro: ''))

      expect(tool.send(:fetch_coordinates, '9908')).to eq(described_class::SEM_PIN)
    end
  end

  # Sem isto a IA anuncia "mandei a localização do imóvel" depois de mandar o pin do bairro,
  # e o que ela promete não bate com o que o cliente recebeu.
  describe '#confirmacao' do
    it 'tells the model a neighbourhood pin went out, and to withhold the street' do
      texto = tool.send(:confirmacao, '9908', 'Jardim Aurora', :bairro)

      expect(texto).to include('BAIRRO Jardim Aurora')
      expect(texto).to match(/nunca escreva a rua/i)
    end

    it 'keeps the plain confirmation for a property pin' do
      expect(tool.send(:confirmacao, '9908', 'x', :imovel)).to include('Pin de localização do imóvel 9908')
    end
  end
end
