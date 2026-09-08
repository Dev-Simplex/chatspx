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
      expect(tool.send(:format_condominio, avulso_com_taxa)).to include('AVULSO — fora de condomínio fechado')
    end

    it 'says it DOES when Vista says Sim' do
      expect(tool.send(:format_condominio, imovel.merge('Condominio' => 'Sim'))).to include('EM CONDOMÍNIO FECHADO')
    end

    it 'stays silent when Vista has no answer' do
      expect(tool.send(:format_condominio, imovel.merge('Condominio' => ''))).to eq('')
    end

    # O rótulo negativo não pode CONTER o positivo: "NÃO fica em condomínio fechado" tem
    # dentro de si "fica em condomínio fechado", e perder o "NÃO" inverte o dado. Conv 33099
    # (03/09): o retorno dizia que era avulso e a IA anunciou condomínio fechado dois minutos
    # depois, oferecendo agendar visita num imóvel de chave avulsa.
    it 'does not let the negative label contain the positive one' do
      sim = tool.send(:format_condominio, imovel.merge('Condominio' => 'Sim'))
      nao = tool.send(:format_condominio, imovel.merge('Condominio' => 'Nao'))

      expect(nao).not_to include(sim.delete('[]').strip)
    end

    it 'leads with the word that decides, before the word condomínio' do
      nao = tool.send(:format_condominio, imovel.merge('Condominio' => 'Nao'))

      expect(nao.index('AVULSO')).to be < nao.index('condomínio')
    end

    # O caso da 4809 inteiro: taxa presente E imóvel avulso, na mesma linha.
    it 'keeps fee and fact distinguishable on the same listing line' do
      linha = tool.send(:format_listings, nil, [avulso_com_taxa], false)

      expect(linha).to include('taxa de condomínio R$ 300')
      expect(linha).to include('AVULSO — fora de condomínio fechado')
    end
  end

  # A IA apresentou três casas ao cliente e a terceira não existia — bairro sem casa nenhuma
  # e código inexistente no Vista. A trava do enviar_fotos_imovel barra a FOTO de código não
  # buscado, mas não barra a FALA. Fechar a lista é o que tira o espaço onde a invenção cabe.
  describe 'a lista devolvida é um conjunto fechado' do
    before { allow(tool).to receive_messages(site_api_key: nil, format_extras: '') }

    it 'numbers every option' do
      texto = tool.send(:format_listings, nil, [imovel, imovel.merge('Codigo' => '7777')], true)

      expect(texto).to include('1) (cód 9908')
      expect(texto).to include('2) (cód 7777')
    end

    it 'states the total and forbids completing the list from memory' do
      texto = tool.send(:format_listings, nil, [imovel], true)

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

    # Antes a busca comum pedia 5 ao Vista, e só se enxerga o que se pede: o total ficava
    # indistinguível de "só existem 5". Numa conversa de 01/09 havia 17 apartamentos para
    # locação, a IA viu 5 e disse ao cliente que eram todas as opções.
    it 'asks for the ceiling in the ordinary search too, so the total is knowable' do
      expect(tool.send(:quantidade_para, false, nil)).to eq(described_class::TETO_INSPECAO)
    end

    it 'reports the search as done, not as pending, when nothing matches' do
      texto = tool.send(:sem_mobiliado, 12)

      expect(texto).to include('Conferi 12')
      expect(texto).to match(/não prometa nova busca/i)
    end
  end

  # Conv 32979: a cliente abriu com "casa pra alugar com dois quartos sendo uma suíte" e recebeu
  # cinco casas, das quais QUATRO tinham Suites=0 no Vista. Não foi desatenção do modelo — a
  # ferramenta não tinha por onde filtrar. No acervo de locação daquele dia havia 22 casas de 2
  # quartos e apenas 3 com suíte; a busca ordenou por distância, cortou nas 5 mais próximas, e
  # duas das três com suíte nunca apareceram — uma delas mais barata que três das oferecidas.
  describe 'suíte' do
    # Suites é numérico e o Vista filtra por RANGE. Testado ao vivo contra o acervo: com
    # `['1','10']` voltam as 3 casas (de 1 e de 2 suítes); com `'1'` voltam 2, porque a de duas
    # fica de fora. O range é o que exprime "pelo menos uma".
    def filtro_de(**args)
      capturado = nil
      allow(tool).to receive(:fetch_vista) do |filter, **_|
        capturado ||= filter
        []
      end
      tool.perform(tool_context, status_tipo: 'locacao', **args)
      capturado
    end

    it 'asks the Vista for at least one suite, not for exactly one' do
      expect(filtro_de(categoria: 'Casa', dormitorios: 2, suite: true)['Suites']).to eq(%w[1 10])
    end

    it 'does not constrain suites when the client did not ask for one' do
      expect(filtro_de(categoria: 'Casa', dormitorios: 2)).not_to have_key('Suites')
    end

    # "2 quartos sendo 1 suíte" são dois filtros, não um: quem pede suíte não abre mão do
    # número de quartos, e foi assim que a cliente falou.
    it 'keeps the bedroom count alongside the suite filter' do
      filtro = filtro_de(categoria: 'Casa', dormitorios: 2, suite: true)

      expect(filtro['Dormitorios']).to eq(2)
      expect(filtro['Suites']).to eq(%w[1 10])
    end

    # Sem imóvel com suíte no bairro pedido, a alternativa em outro bairro precisa continuar
    # tendo suíte — senão a ampliação devolve justamente o que o cliente recusou.
    it 'carries the suite filter into the wider search that drops the neighbourhood' do
      filter = { 'Categoria' => 'Casa', 'Bairro' => ['like', '%Delta%'], 'Suites' => %w[1 10] }
      recebido = nil
      allow(tool).to receive(:fetch_vista) do |f, **_|
        recebido = f
        []
      end

      tool.send(:ampliar_sem_bairro, tool_context, filter, false, 'Delta', nil)

      expect(recebido['Suites']).to eq(%w[1 10])
      expect(recebido).not_to have_key('Bairro')
    end
  end

  # "Não existem outras" só é verdade quando a lista mostrada É o acervo do critério. O rodapé
  # afirmava isso sempre — e a apresentação corta em MOSTRAR, então a afirmação era falsa em
  # todo critério com mais opções que isso.
  describe 'o rodapé sobre o total' do
    it 'closes the set only when everything found is on the list' do
      texto = tool.send(:rodape, 3, 3)

      expect(texto).to include('não existem outras')
    end

    it 'says how many exist when the list was cut' do
      texto = tool.send(:rodape, 5, 17)

      expect(texto).to include('5 das 17')
      expect(texto).to match(/N[ÃA]O diga que são todas/i)
      expect(texto).not_to include('não existem outras')
    end

    # A trava anti-invenção vale nos DOIS ramos: dizer que há mais não pode virar licença
    # para o modelo completar a lista de memória, que é o defeito que o rodapé fechado veio
    # resolver na conv 4809.
    it 'keeps the anti-invention rule in both endings' do
      textos = [tool.send(:rodape, 3, 3), tool.send(:rodape, 5, 17)]

      expect(textos).to all(match(/SOMENTE im[óo]vel desta lista/i))
      expect(textos).to all(match(/nunca complete a lista de mem[óo]ria/i))
    end
  end

  # Conv 33006: o cliente chegou por um portal de terceiros, que abre a conversa com o nome do
  # anúncio entre aspas. A página do portal não serve pra nada (é SPA: o og:title é genérico do
  # site), mas o título É o TituloSite do próprio cadastro — medido em 8 títulos reais, 6
  # acharam o imóvel exato.
  describe 'anúncio de portal de terceiro' do
    it 'searches the Vista by the advert title the client pasted' do
      capturado = nil
      allow(tool).to receive(:fetch_vista) do |filter, **_|
        capturado ||= filter
        []
      end

      tool.perform(tool_context, status_tipo: 'locacao', titulo: 'CASA JD TERRA RICA')

      expect(capturado['TituloSite']).to eq(['like', '%CASA JD TERRA RICA%'])
    end

    # Os 2 títulos que não casaram eram anúncio de OUTRA imobiliária no mesmo portal. Devolver
    # "nenhum imóvel encontrado" ali fez a IA dizer ao cliente que não havia apartamento nenhum
    # — havia 17. O retorno tem que separar "não achei ESTE" de "não temos imóveis".
    it 'says the advert may belong to another agency instead of implying an empty catalogue' do
      allow(tool).to receive(:fetch_vista).and_return([])

      texto = tool.perform(tool_context, status_tipo: 'locacao', titulo: 'APARTAMENTO QUE NAO E NOSSO')

      expect(texto).to include('pode não ser nosso')
      expect(texto).to match(/N[ÃA]O conclua que não temos imóveis/i)
      expect(texto).not_to eq('Nenhum imóvel encontrado com esses critérios.')
    end
  end

  # O Vista recusa quantidade acima de 50 com HTTP 400 e a busca volta VAZIA — sem erro
  # visível, só "nenhum imóvel encontrado" com o acervo cheio. Foi assim que o ramo
  # mobiliado nasceu quebrado e, quando o teto passou a valer para a busca comum, derrubou
  # toda busca de imóvel em produção.
  # Conv 33099 (03/09): a placa dizia 6767, o modelo leu 6763 e depois 6762 na MESMA foto, e
  # as duas vezes anunciou ao cliente que o imóvel não existia — inventando o porquê. O imóvel
  # estava no acervo; só apareceu quando o cliente digitou o número. Em 30 dias, 75 de 450
  # buscas por código voltam vazias e em 6 conversas a busca seguinte, com outro número, achou.
  describe 'código que não aparece no acervo' do
    it 'warns that the number may have been misread from a photo' do
      texto = tool.send(:codigo_nao_encontrado, '6762')

      expect(texto).to include('6762')
      expect(texto).to match(/FOTO|placa/i)
    end

    it 'forbids announcing the property as non-existent or already rented' do
      texto = tool.send(:codigo_nao_encontrado, '6762')

      expect(texto).to match(/N[ÃA]O afirme/i)
      expect(texto).to match(/j[áa] foi alugad/i)
    end

    it 'asks for the client to confirm the number instead' do
      expect(tool.send(:codigo_nao_encontrado, '6762')).to match(/confirme o n[úu]mero/i)
    end

    # A ressalva vale para o número que o AGENTE leu, não para o que o cliente escreveu —
    # senão a busca por código digitado nunca poderia dizer que não achou.
    it 'still allows treating a client-typed code as truly absent' do
      expect(tool.send(:codigo_nao_encontrado, '6762')).to match(/cliente escreveu ou falou/i)
    end
  end

  # Conv 33632 (07/09): a cliente colou "Casa Portal do Servidor" de um portal, a busca por
  # TituloSite não achou e a IA respondeu que o anúncio "pode ser de outra imobiliária" — sobre
  # o 9819, que é da Tozi. O título de portal é "Categoria + Bairro" (a mesma composição da URL
  # do site), e 23 dos 50 imóveis de locação estão com TituloSite VAZIO, o 9819 entre eles.
  describe 'título de portal que não casa com o cadastro' do
    it 'splits the category off the front of the title' do
      expect(tool.send(:decompor_titulo, 'Casa Portal do Servidor')).to eq(['Casa', 'Portal Servidor'])
    end

    it 'matches the longest category first, so a compound one is not cut short' do
      categoria, = tool.send(:decompor_titulo, 'Conjunto de Kitnets Jardim Itália')

      expect(categoria).to eq('Conjunto de Kitnets')
    end

    it 'leaves the title alone when it opens with no known category' do
      expect(tool.send(:decompor_titulo, 'Portal do Servidor')).to eq([nil, 'Portal Servidor'])
    end

    # Sem a fronteira de palavra, o "na" do conectivo é removido de dentro de Canadá e o bairro
    # vira "Cadá" — o termo deixa de casar e o imóvel some.
    it 'strips connectives as whole words, never inside a neighbourhood name' do
      _, resto = tool.send(:decompor_titulo, 'CASA - RES. CANADÁ')

      expect(resto).to eq('CANADÁ')
    end

    it 'offers the neighbourhood from the end first, shortening from the left' do
      expect(tool.send(:candidatos_de_bairro, 'PISCINA JARDIM IMPERIAL'))
        .to eq(['PISCINA JARDIM IMPERIAL', 'JARDIM IMPERIAL', 'IMPERIAL'])
    end

    it 'drops one-letter fragments that would match half the base' do
      expect(tool.send(:candidatos_de_bairro, 'a JARDIM IMPERIAL')).not_to include('a JARDIM IMPERIAL')
    end

    # A explicação que a IA repetiu ao cliente era a menos provável das duas.
    it 'stops leading with the other-agency explanation' do
      texto = tool.send(:titulo_sem_correspondencia, 'Casa Portal do Servidor')

      expect(texto).to match(/cadastrado sem título/i)
      expect(texto).to match(/MENOS prov[áa]vel/i)
      expect(texto).to match(/N[ÃA]O conclua/i)
    end
  end

  # O campo Condominio é preenchido à mão e erra: medido no acervo em 08/09, 9 dos 50 imóveis
  # de locação cobram taxa E estão marcados como avulsos, contra 4 marcados "Sim". Na conv
  # 33632 a IA leu "avulso" no 9819 e mandou a cliente retirar a chave para visitar sozinha um
  # imóvel que fica em condomínio fechado.
  describe 'quando o cadastro de condomínio se contradiz' do
    it 'still calls it avulso when there is no fee at all' do
      im = { 'Condominio' => 'Nao', 'ValorCondominio' => '0' }

      expect(tool.send(:format_condominio, im)).to include('AVULSO')
    end

    it 'refuses to call it avulso when it charges a condo fee' do
      im = { 'Condominio' => 'Nao', 'ValorCondominio' => '350' }

      expect(tool.send(:format_condominio, im)).not_to include('AVULSO')
      expect(tool.send(:format_condominio, im)).to include('INDEFINIDO')
    end

    # O dano da 33632 não foi o rótulo, foi o que ele autorizou.
    it 'blocks the self-service key pickup while it is undefined' do
      im = { 'Condominio' => 'Nao', 'ValorCondominio' => '350' }

      expect(tool.send(:format_condominio, im)).to match(/N[ÃA]O ofereça a retirada de/i)
    end

    it 'keeps trusting the field when it says yes' do
      im = { 'Condominio' => 'Sim', 'ValorCondominio' => '350' }

      expect(tool.send(:format_condominio, im)).to eq(' [EM CONDOMÍNIO FECHADO]')
    end

    it 'stays silent when the field has no answer' do
      expect(tool.send(:format_condominio, { 'Condominio' => '', 'ValorCondominio' => '350' })).to eq('')
    end
  end

  describe 'o teto de paginação' do
    it 'never asks the Vista for more than the API accepts' do
      expect(described_class::TETO_INSPECAO).to be <= 50
      expect(tool.send(:quantidade_para, false, nil)).to be <= 50
      expect(tool.send(:quantidade_para, true, nil)).to be <= 50
      expect(tool.send(:quantidade_para, false, true)).to be <= 50
    end
  end

  # O bairro pedido sem imóvel cai no fallback, que buscava sem o filtro e cortava os
  # MOSTRAR primeiros NA ORDEM DO VISTA — sempre a mesma. Medido em 03/09 com cinco bairros
  # diferentes: os quatro mesmos imóveis nas cinco vezes. Em 30 dias, 126 menções da IA a
  # Bella Morada e 119 a Aurora, contra 3 e 15 do time, com o acervo espalhado por ~20
  # bairros.
  describe 'alternativas de outros bairros' do
    def imovel(cod, bairro, dist = nil)
      { 'Codigo' => cod, 'Bairro' => bairro }.tap { |h| h['dist_km'] = dist if dist }
    end

    it 'ranks by distance when every option has one' do
      lista = [imovel('1', 'Aurora', 8.0), imovel('2', 'Centro', 1.5), imovel('3', 'Bela Vista', 4.0)]

      expect(tool.send(:ordenar_alternativas, lista).map { |i| i['Codigo'] }).to eq(%w[2 3 1])
    end

    # Sem geocoding não há proximidade medida, e inventar uma seria pior: o Google resolve
    # 100% dos bairros e erra 26% deles por mais de 3 km.
    it 'takes turns between neighbourhoods when there is no distance' do
      lista = [imovel('1', 'Aurora'), imovel('2', 'Aurora'), imovel('3', 'Aurora'),
               imovel('4', 'Bella Morada'), imovel('5', 'Centro')]

      ordem = tool.send(:ordenar_alternativas, lista).map { |i| i['Codigo'] }

      expect(ordem.first(3)).to contain_exactly('1', '4', '5')
      expect(ordem.size).to eq(5)
    end

    it 'keeps every option, dropping none' do
      nomes = %w[A B C]
      lista = (1..9).map { |n| imovel(n.to_s, nomes[n % 3]) }

      expect(tool.send(:ordenar_alternativas, lista).map { |i| i['Codigo'] }).to match_array(lista.map { |i| i['Codigo'] })
    end

    # Distância parcial é o caso NORMAL, não a exceção: medido no acervo de locação em
    # 03/09, 24 dos 29 imóveis têm coordenada e 5 não. Exigir que todos tivessem descartava
    # a medida de 24 por causa de 5 — e a lista voltava a ser a ordem do Vista, que é o bug.
    it 'still ranks by distance when only some options have one' do
      lista = [imovel('1', 'Aurora'), imovel('2', 'Centro', 4.0), imovel('3', 'Bela Vista', 0.5)]

      expect(tool.send(:ordenar_alternativas, lista).map { |i| i['Codigo'] }).to eq(%w[3 2 1])
    end

    it 'never drops the ones without a coordinate, it puts them last' do
      lista = [imovel('1', 'Aurora'), imovel('2', 'Aurora'), imovel('3', 'Centro', 4.0)]

      expect(tool.send(:ordenar_alternativas, lista).map { |i| i['Codigo'] }).to eq(%w[3 1 2])
    end
  end
end
