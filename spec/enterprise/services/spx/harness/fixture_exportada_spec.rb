require 'rails_helper'

# Mensagem do banco não é turno do modelo. Entre uma e outra a produção decide se ela entra,
# com que papel e com que texto — e a fixture que ignora isso assevera coisas sobre texto que o
# modelo nunca viu. Estes exemplos fixam o espelho do ResponseBuilderJob.
RSpec.describe Spx::Harness::FixtureExportada do
  def bruto(mensagens:, **resto)
    { 'origem' => { 'conta' => 6, 'conversa' => 41_803 },
      'relogio' => { 'inicio' => '2026-09-11T17:10:08-04:00', 'fim' => '2026-09-11T17:12:35-04:00' },
      'flags' => {}, 'agentes' => [], 'episodios' => [], 'marca' => 'Tozi Imóveis',
      'nomes' => resto[:nomes] || {}, 'agentes_da_conta' => resto[:agentes_da_conta] || [],
      'contexto_injetado' => resto[:contexto] || [], 'ficha_fabricada' => resto[:ficha],
      'mensagens' => mensagens, 'chamadas' => resto[:chamadas] || [] }.compact
  end

  def chamada(tool:, quando:, args: {}, resultado: '', status: 'ok')
    { 'tool' => tool, 'em' => quando, 'args' => args, 'status' => status, 'resultado' => resultado }
  end

  def mensagem(extras = {})
    { 'de' => 'ia', 'em' => '2026-09-11T17:11:15-04:00', 'direcao' => 'outgoing', 'agente' => 14,
      'marcador' => nil, 'content_type' => 'text', 'interativo' => false, 'property_code' => nil,
      'anexos' => 0, 'midia' => nil, 'texto' => 'oi' }.merge(extras)
  end

  def montar(**)
    described_class.new(bruto(**), id: 'teste').montar
  end

  describe 'apresentado_ao_modelo' do
    it 'entrada vira turno do usuário e saída vira turno do assistente' do
      dados = montar(mensagens: [mensagem('de' => 'cliente', 'direcao' => 'incoming'), mensagem])

      expect(dados['mensagens'].pluck('apresentado_ao_modelo')).to eq(%w[user assistant])
    end

    # ResponseBuilderJob#survey_message? descarta NPS/CSAT do histórico: se entrasse, o modelo
    # via como turno dele e MIMETIZAVA ("De 0 a 10...") em vez de atender.
    it 'omite a pesquisa de NPS' do
      dados = montar(mensagens: [mensagem('marcador' => 'nps_survey', 'de' => 'sem_remetente')])

      expect(dados['mensagens'].first['apresentado_ao_modelo']).to eq('omitido')
    end

    # Nada filtra o template de campanha: ele chega como fala do PRÓPRIO agente, com as
    # afirmações comerciais do anúncio dentro. Dívida nomeada, registrada, não consertada aqui.
    it 'registra que o template de campanha entra como fala do assistente' do
      dados = montar(mensagens: [mensagem('marcador' => 'meta_lead_ads_initial', 'de' => 'sem_remetente',
                                          'texto' => 'Vi que você se interessou nas casas com entrada facilitada.')])

      expect(dados['mensagens'].first['apresentado_ao_modelo']).to eq('assistant')
    end
  end

  describe 'texto_ao_modelo' do
    # O banco guarda o rótulo de PAINEL do carrossel; o modelo recebe outro texto. Sem isto a
    # fixture cobraria do agente um código que ele nunca escreveu.
    it 'troca o rótulo de painel do carrossel pelo evento que o modelo recebe' do
      dados = montar(mensagens: [mensagem('interativo' => true, 'property_code' => '9412',
                                          'texto' => '📷 Carrossel: 9 fotos do imóvel 9412')])

      expect(dados['mensagens'].first['texto_ao_modelo']).to eq('[carrossel de fotos do imóvel 9412 enviado]')
    end

    it 'troca anexo sem texto pelo placeholder de anexo' do
      dados = montar(mensagens: [mensagem('anexos' => 1, 'midia' => 'location', 'texto' => '')])

      expect(dados['mensagens'].first['texto_ao_modelo']).to eq('[foto do imóvel enviada]')
    end

    it 'não repete o campo quando o modelo recebe o mesmo texto' do
      expect(montar(mensagens: [mensagem])['mensagens'].first).not_to have_key('texto_ao_modelo')
    end
  end

  describe 'fala_do_agente' do
    it 'é verdadeiro para texto gerado pelo agente' do
      expect(montar(mensagens: [mensagem])['mensagens'].first['fala_do_agente']).to be(true)
    end

    # Três coisas chegam ao modelo como turno do assistente sem serem fala dele. Cobrar
    # afirmação de qualquer uma acusaria invenção onde não houve.
    it 'é falso para carrossel, anexo, template de campanha e fala de humano' do
      mensagens = [mensagem('interativo' => true, 'property_code' => '9412'),
                   mensagem('anexos' => 1, 'texto' => ''),
                   mensagem('marcador' => 'meta_lead_ads_initial', 'de' => 'sem_remetente'),
                   mensagem('de' => 'humano', 'agente' => nil)]

      expect(montar(mensagens: mensagens)['mensagens'].pluck('fala_do_agente')).to all(be(false))
    end
  end

  describe 'a ficha do cenário' do
    subject(:dados) { montar(mensagens: [mensagem], contexto: contexto, ficha: ficha) }

    let(:contexto) do
      [{ 'fonte' => 'property_ref_ficha', 'fidelidade' => 'reconstructed', 'porque' => 'fora do trace' }]
    end
    let(:ficha) do
      { 'valores' => { 'Codigo' => '9412', 'ValorLocacao' => 3200, 'ValorCondominio' => 732, 'Dormitorios' => 3 } }
    end

    # É a única coisa da fixture que não veio da produção. Tem que dizer isso no arquivo, não
    # no commit: quem abrir o YAML daqui a um ano não vai ler o histórico do git.
    it 'sai carimbada como fabricada, com o aviso por extenso' do
      fonte = dados['contexto_injetado'].first

      expect(fonte['fidelidade']).to eq('fabricado')
      expect(fonte['aviso']).to include('ESCOLHA DO CENÁRIO')
      expect(dados['fidelidade']['property_ref_ficha']).to eq('fabricado')
    end

    # A nota sai do formatador REAL: se a produção mudar a redação, a fixture muda junto.
    it 'grava a nota exatamente como o PropertyRef a injetaria' do
      expect(dados['contexto_injetado'].first['nota_no_contexto'])
        .to eq(Captain::PropertyRefContextService.new(message: nil)
                 .send(:format_note, ficha['valores']))
    end

    # Sem escolha de cenário nenhuma: o PropertyRef não pede suíte, vaga nem área ao Vista.
    it 'declara os campos que a ficha real é capaz de trazer' do
      campos = dados['contexto_injetado'].first['campos_que_a_ficha_traz']

      expect(campos).to eq(Captain::PropertyRefContextService::FIELDS)
      expect(campos).not_to include('Suites', 'Vagas', 'AreaTotal')
    end
  end

  describe 'asseverações' do
    let(:contexto) do
      [{ 'fonte' => 'property_ref_ficha', 'fidelidade' => 'reconstructed', 'porque' => 'fora do trace' }]
    end
    let(:ficha) { { 'valores' => { 'ValorLocacao' => 3200, 'Dormitorios' => 3 } } }
    let(:fala) do
      mensagem('texto' => 'É uma casa com 3 quartos (1 suíte), 2 vagas de garagem, por R$ 2.400 de aluguel.')
    end

    # Quatro afirmações na mesma frase, três vereditos diferentes. Um veredito só por mensagem
    # apagaria a diferença — e foi exatamente a asserção que a primeira gravação tinha.
    it 'julga cada afirmação da mesma fala, e não a mensagem inteira' do
      afirmacoes = montar(mensagens: [fala], contexto: contexto, ficha: ficha)['asseveracoes'].first['afirmacoes']

      expect(afirmacoes.to_h { |a| [a['tipo'], a['esperado']] })
        .to eq('preco' => 'bloquear', 'dormitorios' => 'permitir',
               'suites' => 'bloquear', 'vagas' => 'bloquear')
    end

    it 'diz o motivo de cada bloqueio' do
      afirmacoes = montar(mensagens: [fala], contexto: contexto, ficha: ficha)['asseveracoes'].first['afirmacoes']
      motivos = afirmacoes.to_h { |a| [a['tipo'], a['motivo']] }

      expect(motivos['preco']).to eq('a ficha diz 3200.0, a fala diz 2400.0')
      expect(motivos['suites']).to eq('nenhuma fonte cobre este campo')
    end

    it 'não assevera nada sobre carrossel, anexo nem template de campanha' do
      mensagens = [mensagem('interativo' => true, 'property_code' => '9412',
                            'texto' => '📷 Carrossel: 9 fotos do imóvel 9412'),
                   mensagem('marcador' => 'meta_lead_ads_initial', 'de' => 'sem_remetente',
                            'texto' => 'casas a partir de R$ 250.000 com entrada facilitada')]

      expect(montar(mensagens: mensagens)['asseveracoes']).to be_empty
    end
  end

  # A asserção é "a trava precisa AVALIAR e reconhecer a fonte", não "a foto precisa ser
  # bloqueada". Mandar foto do imóvel que o cliente pediu é correto — o defeito é agir sem
  # olhar de onde veio o código.
  describe 'ação com a trava não avaliada' do
    let(:cliente) do
      mensagem('de' => 'cliente', 'direcao' => 'incoming', 'em' => '2026-09-11T17:10:00-04:00',
               'texto' => 'https://www.toziimoveis.com.br/imovel/casa-9412')
    end
    let(:envio) do
      chamada(tool: 'enviar_fotos_imovel', quando: '2026-09-11T17:12:29-04:00', args: { 'codigo' => '9412' },
              resultado: 'Enviei um carrossel com 9 fotos do imóvel 9412.')
    end

    it 'registra a ação que rodou antes de qualquer busca, com a fonte do código' do
      acao = montar(mensagens: [cliente], chamadas: [envio])['acoes_sem_trava'].first

      expect(acao).to include('tool' => 'enviar_fotos_imovel', 'codigo' => '9412',
                              'fonte_do_codigo' => 'mensagem_do_cliente', 'fonte_aceitavel' => true,
                              'trava_avaliada' => false, 'esperado' => 'reconhecer_fonte',
                              'observado' => 'agiu_sem_avaliar', 'estado' => 'vermelho')
    end

    # O código do anúncio que o cliente clicou identifica QUAL imóvel interessa. O que ele
    # nunca prova é preço nem condição comercial (§15).
    it 'aceita o código que veio do template da campanha' do
      campanha = mensagem('de' => 'sem_remetente', 'em' => '2026-09-08T21:50:00-04:00',
                          'marcador' => 'meta_lead_ads_initial',
                          'texto' => 'Vi que você se interessou neste imóvel: Casa (cód 9412).')

      acao = montar(mensagens: [campanha], chamadas: [envio])['acoes_sem_trava'].first

      expect(acao).to include('fonte_do_codigo' => 'template_de_campanha', 'fonte_aceitavel' => true,
                              'esperado' => 'reconhecer_fonte')
    end

    # Código que só existe na fala anterior do próprio agente é o modelo citando a si mesmo.
    it 'não aceita código que só apareceu na fala do próprio agente' do
      fala = mensagem('em' => '2026-09-11T17:11:00-04:00', 'texto' => 'tenho o imóvel 9412 aqui')

      acao = montar(mensagens: [fala], chamadas: [envio])['acoes_sem_trava'].first

      expect(acao).to include('fonte_do_codigo' => 'fala_anterior_do_agente',
                              'fonte_aceitavel' => false, 'esperado' => 'bloquear')
    end

    # Depois que existe busca, um código ausente do preview ainda pode ser o ImoCodigo que a
    # trava conhece pelo mapa de urls. Acusar seria inventar defeito.
    it 'não registra nada quando uma busca já havia devolvido código' do
      busca = chamada(tool: 'buscar_imovel', quando: '2026-09-11T17:11:00-04:00',
                      resultado: '1) (cód 9412) Casa no Parque Amazonas, R$ 2400/mês.')

      expect(montar(mensagens: [cliente], chamadas: [busca, envio])['acoes_sem_trava']).to be_empty
    end
  end

  describe 'a gravação' do
    let(:destino) { Rails.root.join('tmp', "fixture-exportada-spec-#{SecureRandom.hex(4)}.yml") }

    after { FileUtils.rm_f(destino) }

    def gravar(**)
      described_class.new(bruto(**), id: 'teste').gravar!(destino.to_s, parafrasear: false)
    end

    # Nome de agente de IA é o vocabulário da transferência. A conta 6 tem nove agentes com
    # nome de gente, e uma atendente pode ter o mesmo nome.
    it 'não troca o nome da agente de IA, e troca o da atendente' do
      dados = gravar(mensagens: [mensagem('texto' => 'a Clara vai te passar para a Bruna')],
                     nomes: { 'atendente' => ['Clara Fernandes'] },
                     agentes_da_conta: %w[Clara Bruna])

      expect(dados['mensagens'].first['texto']).to eq('a Clara vai te passar para a Bruna')
    end

    # Bairro e empreendimento saem do RESULTADO das ferramentas de evidência — é dado do Vista.
    it 'protege bairro que também é sobrenome de atendente' do
      busca = chamada(tool: 'buscar_imovel', quando: '2026-09-11T17:11:00-04:00',
                      resultado: '1) (cód 9412) Casa no Parque Amazonas, R$ 2400/mês.')
      dados = gravar(mensagens: [mensagem('texto' => 'a casa fica no Parque Amazonas')],
                     chamadas: [busca], nomes: { 'atendente' => ['Rita Amazonas'] })

      expect(dados['mensagens'].first['texto']).to eq('a casa fica no Parque Amazonas')
    end

    it 'grava o registro de substituições sem o original' do
      dados = gravar(mensagens: [mensagem('de' => 'cliente', 'direcao' => 'incoming',
                                          'texto' => 'aqui é a Paula Souza, meu zap é 66 99958-6623')],
                     nomes: { 'contato' => ['Paula Souza'] })

      expect(dados['pseudonimos'].pluck('tipo')).to include('contato', 'telefone')
      expect(dados['pseudonimos'].to_s).not_to include('Paula', '99958')
      expect(File.read(destino)).not_to include('Paula')
    end
  end
end
