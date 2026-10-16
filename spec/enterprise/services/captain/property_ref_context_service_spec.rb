require 'rails_helper'

RSpec.describe Captain::PropertyRefContextService, type: :model do
  let(:account) { create(:account, custom_attributes: { 'property_ref_context' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  let(:imovel) do
    { 'Codigo' => '9412', 'Categoria' => 'Casa', 'Status' => 'Aluguel', 'ValorVenda' => '0',
      'ValorLocacao' => '3200', 'ValorCondominio' => '731.55',
      'Bairro' => 'Santorini Residence', 'Cidade' => 'Sinop', 'Dormitorios' => '3' }
  end

  let(:codigos_no_acervo) { %w[9412] }

  def note_for(content)
    message = create(:message, account: account, inbox: inbox, conversation: conversation,
                               message_type: :incoming, content: content)
    service = described_class.new(message: message)
    # Offline: a chave só precisa existir pro opt-in, e o acervo é dublê. `site_domain` é o
    # default do concern, mas fixá-lo aqui evita que .env de máquina mude o resultado.
    allow(service).to receive_messages(vista_api_key: 'k', site_domain: 'toziimoveis.com.br')
    allow(service).to receive(:fetch_imovel) { |codigo| codigos_no_acervo.include?(codigo) ? imovel.merge('Codigo' => codigo) : nil }
    service.note
  end

  # O caso que motivou: o lead colou o link e a ficha não era montada, então o preço do
  # imóvel só existia na memória do modelo — que afirmou R$ 2.400 num imóvel de R$ 3.200.
  describe 'código vindo do link da página' do
    it 'monta a ficha a partir do link, com o valor real do acervo' do
      nota = note_for('https://www.toziimoveis.com.br/imovel/aluguel-casa-santorini-residence-sinop-9412')

      expect(nota).to include('código 9412')
      expect(nota).to include('aluguel R$ 3.200')
      expect(nota).to include('disponível para locação')
    end

    it 'lê o código do FIM do segmento, não um número solto do slug' do
      nota = note_for('https://www.toziimoveis.com.br/imovel/apto-123-quartos-sinop-9412')

      expect(nota).to include('código 9412')
    end

    it 'aceita o link com barra final e com query' do
      expect(note_for('https://www.toziimoveis.com.br/imovel/casa-sinop-9412/')).to include('código 9412')
      expect(note_for('https://www.toziimoveis.com.br/imovel/casa-sinop-9412?utm_source=ig')).to include('código 9412')
    end

    it 'resolve o link mesmo com texto em volta' do
      expect(note_for('oi, vi esse https://www.toziimoveis.com.br/imovel/casa-sinop-9412 ainda tem?')).to include('código 9412')
    end
  end

  # A amarra que impede a ficha errada: código de OUTRO site casaria com um imóvel nosso, e
  # a IA passaria dado do nosso acervo falando do imóvel do concorrente.
  describe 'link de fora do domínio da conta' do
    it 'não monta ficha' do
      expect(note_for('https://www.portalconcorrente.com.br/imovel/casa-sinop-9412')).to be_nil
    end
  end

  describe 'formato "Ref:" (não-regressão)' do
    it 'segue montando a ficha' do
      expect(note_for('Tenho interesse no imóvel (Ref: 9412)')).to include('código 9412')
    end

    it 'tem precedência quando a mensagem traz os dois' do
      nota = note_for('(Ref: 9412) https://www.toziimoveis.com.br/imovel/casa-sinop-7777')

      expect(nota).to include('código 9412')
    end
  end

  # O texto pronto da comunidade da Tozi traz o código por extenso, sem "Ref:" nem link. Sem a
  # ficha, a triagem perguntou "alugar ou comprar?" para um imóvel só de venda (conversa 44350).
  describe 'código escrito depois de "imóvel" ou "código"' do
    # Os números dos casos negativos também existem no acervo: se a ficha não sai, é porque o
    # padrão não casou, e não porque o imóvel não existe.
    let(:codigos_no_acervo) { %w[9412 9835 10102 10113 7777 1500 2500 123] }

    it 'reconhece o texto pronto da comunidade' do
      expect(note_for('Vi na comunidade sobre o imóvel 10102 e quero saber mais.')).to include('código 10102')
    end

    it 'aceita as variações de escrita' do
      expect(note_for('quero saber do código 9835')).to include('código 9835')
      expect(note_for('cód. 9412 ainda tem?')).to include('código 9412')
      expect(note_for('vi o imovel 10113')).to include('código 10113')
      expect(note_for('IMÓVEL nº 9412')).to include('código 9412')
    end

    it 'não confunde valor nem metragem com código' do
      ['imóvel de 1500 reais', 'imóvel 300 mil', 'imóvel R$ 2500', 'imóvel 2500 reais', 'imóvel 1500 m²',
       'imóvel 1500 metros', 'imóvel 250 mil', 'imóvel 1500,00', 'casa com 1500 m²'].each do |texto|
        expect(note_for(texto)).to be_nil, "casou indevidamente: #{texto}"
      end
    end

    it 'exige ao menos 4 dígitos' do
      expect(note_for('imóvel 123')).to be_nil
    end

    it 'perde para o "Ref:" e para o link quando a mensagem traz os dois' do
      expect(note_for('imóvel 7777 (Ref: 9412)')).to include('código 9412')
      expect(note_for('imóvel 7777 https://www.toziimoveis.com.br/imovel/casa-sinop-9412')).to include('código 9412')
    end
  end

  # A ficha passa a SUBSTITUIR a busca (medido: com ela no contexto o agente responde sem
  # chamar o buscar_imovel). Se ela omitir ou arredondar o custo, a resposta fica pior que a
  # de hoje — foi por isso que o condomínio entrou, e com centavos.
  describe 'valores que a ficha carrega' do
    # Pelo caminho "Ref:", que já existia: assim a prova de mutação acusa a mudança dos
    # VALORES, e não a do link (que faria qualquer exemplo com URL falhar no código velho).
    it 'traz o condomínio com os centavos exatos, sem arredondar' do
      nota = note_for('Tenho interesse (Ref: 9412)')

      expect(nota).to include('condomínio R$ 731,55')
      expect(nota).not_to include('R$ 732')
    end

    it 'mantém valor inteiro sem casas decimais' do
      nota = note_for('https://www.toziimoveis.com.br/imovel/casa-sinop-9412')

      expect(nota).to include('aluguel R$ 3.200')
      expect(nota).not_to include('R$ 3.200,00')
    end

    it 'omite o condomínio quando o imóvel não tem' do
      imovel['ValorCondominio'] = '0'

      expect(note_for('Tenho interesse (Ref: 9412)')).not_to include('condomínio')
    end
  end

  describe 'caminhos em que não se aplica' do
    it 'ignora mensagem sem código nenhum' do
      expect(note_for('Boa tarde, tudo bem?')).to be_nil
    end

    it 'ignora link do site que não é de imóvel' do
      expect(note_for('https://www.toziimoveis.com.br/contato')).to be_nil
    end

    it 'é no-op para conta sem o opt-in' do
      account.update!(custom_attributes: {})

      expect(note_for('https://www.toziimoveis.com.br/imovel/casa-sinop-9412')).to be_nil
    end
  end

  # Estes exemplos NÃO stubam o `fetch_imovel` — é ele que está sob teste. Quando a consulta
  # falhava, o `{}` de erro entrava no cache de 6h: uma indisponibilidade de segundos apagava a
  # ficha pelas 6 horas seguintes e o imóvel voltava a ser descrito de memória. É a conv 41803
  # (aluguel afirmado R$ 2.400 num imóvel de R$ 3.200) chegando pelo caminho do cache.
  describe 'cache só guarda o que o servidor confirmou' do
    let(:memoria) { ActiveSupport::Cache::MemoryStore.new }

    def servico_para(content)
      message = create(:message, account: account, inbox: inbox, conversation: conversation,
                                 message_type: :incoming, content: content)
      described_class.new(message: message).tap do |s|
        allow(s).to receive_messages(vista_api_key: 'k', site_domain: 'toziimoveis.com.br',
                                     vista_base_url: 'https://vista.example')
      end
    end

    def responder(code, corpo)
      allow(HTTParty).to receive(:get).and_return(
        instance_double(HTTParty::Response, code: code, parsed_response: corpo)
      )
    end

    before { allow(Rails).to receive(:cache).and_return(memoria) }

    it 'não cacheia a consulta que falhou' do
      responder(503, nil)

      2.times { servico_para('Tenho interesse (Ref: 9412)').note }

      expect(HTTParty).to have_received(:get).twice
    end

    it 'não deixa a falha apagar a ficha das 6h seguintes' do
      responder(503, nil)
      expect(servico_para('Tenho interesse (Ref: 9412)').note).to be_nil

      responder(200, { '1' => imovel })

      expect(servico_para('Tenho interesse (Ref: 9412)').note).to include('código 9412', 'R$ 3.200')
    end

    # Ausência CONFIRMADA é resposta legítima do servidor e vale as 6h: 200 sem o código
    # significa que o acervo não tem aquele imóvel.
    it 'cacheia a ausência que o servidor confirmou' do
      responder(200, { 'total' => 0 })

      2.times { expect(servico_para('Tenho interesse (Ref: 9412)').note).to be_nil }

      expect(HTTParty).to have_received(:get).once
    end

    it 'cacheia o imóvel que o servidor confirmou' do
      responder(200, { '1' => imovel })

      2.times { servico_para('Tenho interesse (Ref: 9412)').note }

      expect(HTTParty).to have_received(:get).once
    end
  end
end
