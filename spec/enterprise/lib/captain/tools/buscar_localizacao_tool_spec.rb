require 'rails_helper'

# A cidade era fixa no código ("Sinop MT"), então referência de bairro de QUALQUER outra
# cidade era geocodificada como se fosse Sinop. Passa a vir da conta — e sem config o
# comportamento tem que ser byte-a-byte o de antes, senão o merge muda contas ao vivo.
RSpec.describe Captain::Tools::BuscarLocalizacaoTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({}) }

  before { account.update!(custom_attributes: { 'google_maps_key' => 'chave-de-teste' }) }

  def stub_geocode(status: 'OK')
    body = { 'status' => status,
             'results' => [{ 'formatted_address' => 'Rua X', 'geometry' => { 'location' => { 'lat' => -1, 'lng' => -2 } } }] }
    allow(HTTParty).to receive(:get).and_return(instance_double(HTTParty::Response, code: 200, parsed_response: body))
  end

  describe 'cidade da busca' do
    it 'usa a cidade historica quando a conta nao configura nada' do
      stub_geocode
      tool.perform(tool_context, local: 'Jardim Paraiso')

      expect(HTTParty).to have_received(:get).with(anything, hash_including(query: hash_including(address: 'Jardim Paraiso Sinop MT')))
    end

    it 'usa a cidade configurada na conta' do
      account.update!(custom_attributes: account.custom_attributes.merge('geo_city' => 'Cuiaba MT'))
      stub_geocode
      tool.perform(tool_context, local: 'Jardim Paraiso')

      expect(HTTParty).to have_received(:get).with(anything, hash_including(query: hash_including(address: 'Jardim Paraiso Cuiaba MT')))
    end

    it 'nomeia a cidade da conta quando nao acha o local' do
      account.update!(custom_attributes: account.custom_attributes.merge('geo_city' => 'Cuiaba MT'))
      stub_geocode(status: 'ZERO_RESULTS')

      expect(tool.perform(tool_context, local: 'Jardim Paraiso')).to include('Cuiaba MT')
    end
  end

  # A description é class-level no RubyLLM::Tool; o override de instância é o que deixa o
  # LLM saber a cidade REAL da conta (mesmo idioma do HandoffTool).
  describe '#description' do
    it 'anuncia a cidade da conta' do
      account.update!(custom_attributes: account.custom_attributes.merge('geo_city' => 'Cuiaba MT'))

      expect(tool.description).to include('Cuiaba MT')
    end

    it 'anuncia a cidade historica sem config' do
      expect(tool.description).to include('Sinop MT')
    end
  end
end
