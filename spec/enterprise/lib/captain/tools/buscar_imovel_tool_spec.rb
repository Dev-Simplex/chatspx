require 'rails_helper'

RSpec.describe Captain::Tools::BuscarImovelTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:tool_context) { Struct.new(:state).new({ conversation: { id: conversation.id } }) }

  let(:imovel) do
    { 'Codigo' => '9908', 'ImoCodigo' => '5501', 'Categoria' => 'Casa', 'Bairro' => 'Jardim Paraíso',
      'Cidade' => 'Sinop', 'ValorVenda' => '450000', 'ValorLocacao' => '0' }
  end

  # track_urls alimenta o fix_property_links (response_builder_job): sem urls_imoveis na
  # conversa, TODO link da Tozi na resposta da IA é apagado. Ele roda dentro de um rescue,
  # então a falha não levanta — ela some. Por isso os testes olham o resultado gravado na
  # conversa, e não a exceção: é assim que o modo de falha real se manifesta.
  describe '#track_urls' do
    subject(:track) { tool.send(:track_urls, tool_context, [imovel], true) }

    # Sem chave do site o build_url cai no formato montado localmente: mantém a suíte
    # offline e o link previsível, independente do que houver no .env da máquina.
    before { allow(tool).to receive(:site_api_key).and_return(nil) }

    it 'records the URL under both the Codigo and the ImoCodigo' do
      track

      urls = conversation.reload.custom_attributes['urls_imoveis']
      expect(urls.keys).to contain_exactly('9908', '5501')
      expect(urls['9908']).to eq(urls['5501'])
      expect(urls['9908']).to include('9908')
    end

    it 'records price and neighbourhood in the sibling map' do
      track

      expect(conversation.reload.custom_attributes['dados_imoveis']['9908'])
        .to eq('preco' => 450_000.0, 'bairro' => 'Jardim Paraíso')
    end

    it 'merges into what a previous search already recorded' do
      conversation.update!(custom_attributes: { 'urls_imoveis' => { '111' => 'https://www.toziimoveis.com.br/imovel/casa-111' },
                                                'dados_imoveis' => { '111' => { 'preco' => 1.0, 'bairro' => 'Centro' } } })

      track

      attrs = conversation.reload.custom_attributes
      expect(attrs['urls_imoveis'].keys).to contain_exactly('111', '9908', '5501')
      expect(attrs['dados_imoveis'].keys).to contain_exactly('111', '9908')
    end

    it 'keeps unrelated custom attributes untouched' do
      conversation.update!(custom_attributes: { 'codigos_buscados' => %w[111] })

      track

      expect(conversation.reload.custom_attributes['codigos_buscados']).to eq(%w[111])
    end

    # A REGRESSÃO. A chave existir valendo nil é diferente de ela estar ausente, e é
    # gravável: o endpoint de custom_attributes da conversa faz
    # `params.permit(custom_attributes: {})` e escreve o hash inteiro como veio, null
    # incluso. Com `fetch('urls_imoveis', {})` o default não entra — vem o nil, `nil.merge`
    # levanta NoMethodError, o rescue engole, e a busca segue como se tivesse gravado.
    context 'when the key exists holding nil' do
      it 'still records urls_imoveis' do
        conversation.update!(custom_attributes: { 'urls_imoveis' => nil })

        track

        expect(conversation.reload.custom_attributes['urls_imoveis']).to include('9908')
      end

      it 'still records dados_imoveis' do
        conversation.update!(custom_attributes: { 'dados_imoveis' => nil })

        track

        expect(conversation.reload.custom_attributes['dados_imoveis']).to include('9908')
      end

      it 'recovers both maps when both are nil' do
        conversation.update!(custom_attributes: { 'urls_imoveis' => nil, 'dados_imoveis' => nil })

        track

        attrs = conversation.reload.custom_attributes
        expect(attrs['urls_imoveis']).to include('9908')
        expect(attrs['dados_imoveis']).to include('9908')
      end

      # O rescue é o que torna a regressão invisível: sem esta asserção, uma falha aqui
      # continuaria passando despercebida se as demais fossem afrouxadas.
      it 'does not swallow an exception on the way' do
        conversation.update!(custom_attributes: { 'urls_imoveis' => nil })
        allow(Rails.logger).to receive(:error)

        track

        expect(Rails.logger).not_to have_received(:error).with(/track_urls/)
      end
    end

    # Imóvel de locação numa busca de venda vem com ValorVenda zerado: sem preço confiável
    # a guarda de preço não deve opinar, então ele fica de fora do dados_imoveis — mas o
    # link continua válido e precisa estar no urls_imoveis.
    it 'keeps a zero-priced property out of dados_imoveis but keeps its URL' do
      tool.send(:track_urls, tool_context, [imovel.merge('ValorVenda' => '0')], true)

      attrs = conversation.reload.custom_attributes
      expect(attrs['urls_imoveis']).to include('9908')
      expect(attrs['dados_imoveis']).to be_empty
    end

    it 'caps each map at the last 60 entries' do
      imoveis = (1..40).map { |i| imovel.merge('Codigo' => "a#{i}", 'ImoCodigo' => "b#{i}") }

      tool.send(:track_urls, tool_context, imoveis, true)

      expect(conversation.reload.custom_attributes['urls_imoveis'].size).to eq(60)
    end

    it 'does nothing without a conversation in the tool state' do
      expect { tool.send(:track_urls, Struct.new(:state).new({}), [imovel], true) }.not_to raise_error
    end
  end
end
