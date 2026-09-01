require 'rails_helper'

# A vitrine nasce AGNÓSTICA: a mensagem carrega `cards` em content_attributes e quem traduz
# pro formato de cada plataforma é o canal, no envio. É o contrário do interactive_payload,
# que nasceu no formato do WhatsApp e, em qualquer outro canal, saía como texto sem falhar.
RSpec.describe Captain::Tools::ApresentarImoveisTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({ conversation: { id: conversation.id } }) }
  let(:buscados) { { 'codigos_buscados' => %w[5194 5195] } }

  let(:outgoing) { conversation.reload.messages.where(message_type: :outgoing).order(:id) }

  def detalhes_de(codigo)
    { 'Codigo' => codigo, 'Status' => 'ALUGUEL', 'Categoria' => 'Casa', 'Dormitorios' => '3',
      'Bairro' => 'Centro', 'ValorLocacao' => '1950', 'AreaTotal' => '120',
      'Foto' => { '1' => { 'Foto' => "https://cdn.example.com/#{codigo}-a.jpg", 'Destaque' => 'Nao' },
                  '2' => { 'Foto' => "https://cdn.example.com/#{codigo}-b.jpg", 'Destaque' => 'Sim' } } }
  end

  before do
    # Sem rede: o Vista não é o que está sob teste aqui.
    allow(tool).to receive(:fetch_detalhes) { |codigo| detalhes_de(codigo) }
  end

  context 'when the channel draws cards (Instagram)' do
    let(:channel) { create(:channel_instagram, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: channel.inbox, custom_attributes: buscados) }

    it 'creates a single message carrying one card per property' do
      expect(tool.perform(tool_context, codigos: '5194, 5195')).to include('vitrine com 2 imóveis')

      expect(outgoing.count).to eq(1)
      expect(outgoing.first.content_attributes['cards'].size).to eq(2)
    end

    it 'describes each property from what the acervo returned, never from the model' do
      tool.perform(tool_context, codigos: '5194')

      card = outgoing.first.content_attributes['cards'].first
      expect(card['title']).to eq('Casa 3 quartos — Centro')
      expect(card['subtitle']).to eq('R$ 1950/mês · 120 m²')
      expect(card['image_url']).to eq('https://cdn.example.com/5194-b.jpg')
    end

    # O título do botão é o que volta como CONTEÚDO da mensagem quando o cliente toca; sem o
    # código nele, a IA receberia um "ver fotos" solto e não saberia de qual imóvel.
    it 'puts the property code both in the button title and in the payload' do
      tool.perform(tool_context, codigos: '5194')

      expect(outgoing.first.content_attributes['cards'].first['button']).to eq(
        'title' => 'Fotos do 5194', 'payload' => 'imovel:5194'
      )
    end

    it 'keeps a readable content, so the panel never shows an empty bubble' do
      tool.perform(tool_context, codigos: '5194')

      expect(outgoing.first.content).to include('Separei 1 opção pra você', 'Casa 3 quartos — Centro')
    end

    it 'refuses a code that no search of this conversation returned' do
      expect(tool.perform(tool_context, codigos: '9999')).to include('não apareceram na busca')
      expect(outgoing).to be_empty
    end
  end

  # Contraprova: em canal que não desenha card a vitrine NÃO sai — nem como card, nem como
  # mensagem muda. A IA recebe o que fazer no lugar, em vez de "enviei" sobre nada.
  context 'when the channel does not draw cards (WAHA)' do
    let(:channel) { create(:channel_api, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: channel.inbox, custom_attributes: buscados) }

    it 'creates no message and tells the agent to list the options as text' do
      expect(tool.perform(tool_context, codigos: '5194,5195')).to include('Apresente as opções em texto')

      expect(outgoing).to be_empty
    end
  end
end
