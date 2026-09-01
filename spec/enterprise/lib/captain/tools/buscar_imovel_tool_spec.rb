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

    it 'records price and neighbourhood in the sibling map, under both codes' do
      track

      dados = conversation.reload.custom_attributes['dados_imoveis']
      expect(dados['9908']).to eq('preco' => 450_000.0, 'bairro' => 'Jardim Paraíso')
      expect(dados['5501']).to eq(dados['9908'])
    end

    it 'merges into what a previous search already recorded' do
      conversation.update!(custom_attributes: { 'urls_imoveis' => { '111' => 'https://www.toziimoveis.com.br/imovel/casa-111' },
                                                'dados_imoveis' => { '111' => { 'preco' => 1.0, 'bairro' => 'Centro' } } })

      track

      attrs = conversation.reload.custom_attributes
      expect(attrs['urls_imoveis'].keys).to contain_exactly('111', '9908', '5501')
      expect(attrs['dados_imoveis'].keys).to contain_exactly('111', '9908', '5501')
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

      # O rescue é o que torna a regressão invisível. Os dois níveis são conferidos de
      # propósito: assim a asserção pega a exceção engolida independente de em qual nível
      # ela for logada, e não vira refém da escolha entre warn e error.
      it 'does not swallow an exception on the way' do
        conversation.update!(custom_attributes: { 'urls_imoveis' => nil })
        allow(Rails.logger).to receive(:error)
        allow(Rails.logger).to receive(:warn)

        track

        expect(Rails.logger).not_to have_received(:error).with(/track_urls/)
        expect(Rails.logger).not_to have_received(:warn).with(/track_urls/)
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

  # A palavra "condomínio" aparecia com dois sentidos na MESMA linha do resultado: a taxa
  # (ValorCondominio) e o fato de o imóvel ficar em condomínio fechado (Condominio). Na conv
  # 4809 o modelo usou a taxa como evidência do fato e anunciou ao cliente que duas casas
  # avulsas eram em condomínio fechado — e a conduta de visita aplicou o caminho errado por
  # cima disso. Estes testes fixam a distinção no texto que o modelo lê.
  describe 'condomínio: taxa e fato são coisas diferentes' do
    let(:avulso_com_taxa) do
      imovel.merge('Condominio' => 'Nao', 'ValorCondominio' => '300', 'ValorLocacao' => '1300', 'ValorVenda' => '0')
    end

    before { allow(tool).to receive_messages(site_api_key: nil, format_extras: '') }

    it 'calls the fee a fee, never just "condomínio"' do
      expect(tool.send(:format_taxas, avulso_com_taxa)).to include('taxa de condomínio R$ 300')
    end

    it 'says the property does NOT sit in a gated community when Vista says Nao' do
      expect(tool.send(:format_condominio, avulso_com_taxa)).to include('NÃO fica em condomínio fechado')
    end

    it 'says it DOES when Vista says Sim' do
      expect(tool.send(:format_condominio, imovel.merge('Condominio' => 'Sim'))).to include('FICA em condomínio fechado')
    end

    it 'stays silent when Vista has no answer' do
      expect(tool.send(:format_condominio, imovel.merge('Condominio' => ''))).to eq('')
    end

    # O caso da 4809 inteiro: taxa presente E imóvel avulso, na mesma linha.
    it 'keeps fee and fact distinguishable on the same listing line' do
      linha = tool.send(:format_listings, [avulso_com_taxa], false)

      expect(linha).to include('taxa de condomínio R$ 300')
      expect(linha).to include('NÃO fica em condomínio fechado')
    end
  end

  # A IA apresentou três casas ao cliente e a terceira não existia — bairro sem casa nenhuma
  # e código inexistente no Vista. A trava do enviar_fotos_imovel barra a FOTO de código não
  # buscado, mas não barra a FALA. Fechar a lista é o que tira o espaço onde a invenção cabe.
  describe 'a lista devolvida é um conjunto fechado' do
    before { allow(tool).to receive_messages(site_api_key: nil, format_extras: '') }

    it 'numbers every option' do
      texto = tool.send(:format_listings, [imovel, imovel.merge('Codigo' => '7777')], true)

      expect(texto).to include('1) (cód 9908')
      expect(texto).to include('2) (cód 7777')
    end

    it 'states the total and forbids completing the list from memory' do
      texto = tool.send(:format_listings, [imovel], true)

      expect(texto).to include('São 1 opção(ões) e não existem outras')
      expect(texto).to match(/nunca complete a lista de memória/i)
    end
  end

  # Régua do cliente: locação pode endereço completo, venda só o bairro — endereço de imóvel
  # à venda é o insumo que um concorrente usa pra captar o imóvel com o proprietário.
  describe 'endereço na descrição do anúncio' do
    let(:descricao) { "Casa ampla\nLocalizada na Rua das Palmeiras, 1234\n3 quartos" }

    it 'keeps the street for a rental' do
      expect(tool.send(:descricao_limpa, descricao, venda: false)).to include('Rua das Palmeiras, 1234')
    end

    it 'replaces the street with an explicit marker for a sale' do
      limpa = tool.send(:descricao_limpa, descricao, venda: true)

      expect(limpa).not_to include('Palmeiras')
      expect(limpa).not_to include('1234')
      expect(limpa).to include('[endereço não divulgado em venda')
    end

    it 'keeps the rest of the description intact in a sale' do
      expect(tool.send(:descricao_limpa, descricao, venda: true)).to include('3 quartos')
    end
  end

  # O Google nunca responde "não achei" para um bairro que não conhece — devolve um homônimo
  # de outra cidade. Medido em 28/08 sobre os 259 bairros do acervo: 259 "resolveram" e 67
  # caíram a mais de 3 km dos imóveis reais, o pior a 518 km. Sem veto, a distância que a IA
  # anuncia ao cliente sai de um ponto em outro estado.
  describe 'veto de sanidade do geocoding' do
    let(:escritorio) { { lat: -11.8519937, lng: -55.5093314, name: 'Escritório' } }

    before do
      allow(tool).to receive_messages(google_maps_key: 'k', geo_city: 'Sinop MT', office_coords: escritorio)
    end

    it 'accepts a point inside the urban radius' do
      allow(tool).to receive(:geocode_google).and_return({ lat: -11.8343912, lng: -55.546244 })

      expect(tool.send(:geocode_referencia, 'Aquarela das Artes')).to be_present
    end

    it 'rejects a namesake in another state' do
      allow(tool).to receive(:geocode_google).and_return({ lat: -19.9166813, lng: -43.9344931 })

      expect(tool.send(:geocode_referencia, 'Jardim Belo Horizonte')).to be_nil
    end

    it 'returns nil without a Google key instead of guessing' do
      allow(tool).to receive(:google_maps_key).and_return(nil)

      expect(tool.send(:geocode_referencia, 'Centro')).to be_nil
    end
  end

  # Mobiliado não é filtro de listagem no Vista (o /listar devolve HTTP 400 pedindo
  # Caracteristicas.Mobiliado). A IA prometia "vou buscar se tem mobiliada" e não buscava.
  describe 'mobiliado' do
    it 'widens the fetch so the post-filter has candidates' do
      expect(tool.send(:quantidade_para, false, true)).to eq(described_class::TETO_INSPECAO)
    end

    it 'keeps the default page size when nobody asked for it' do
      expect(tool.send(:quantidade_para, false, nil)).to eq(5)
    end

    it 'reports the search as done, not as pending, when nothing matches' do
      texto = tool.send(:sem_mobiliado, 12)

      expect(texto).to include('Conferi 12')
      expect(texto).to match(/não prometa nova busca/i)
    end
  end
end
