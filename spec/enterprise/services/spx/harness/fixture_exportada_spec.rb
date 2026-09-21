require 'rails_helper'

# Mensagem do banco não é turno do modelo. Entre uma e outra a produção decide se ela entra,
# com que papel e com que texto — e a fixture que ignora isso assevera coisas sobre texto que o
# modelo nunca viu. Estes exemplos fixam o espelho do ResponseBuilderJob.
RSpec.describe Spx::Harness::FixtureExportada do
  def bruto(mensagens:, chamadas: [], ficha: nil, contexto: [])
    { 'origem' => { 'conta' => 6, 'conversa' => 41_803 },
      'relogio' => { 'inicio' => '2026-09-11T17:10:08-04:00', 'fim' => '2026-09-11T17:12:35-04:00' },
      'flags' => {}, 'agentes' => [], 'nomes' => [], 'episodios' => [],
      'contexto_injetado' => contexto, 'ficha_fabricada' => ficha,
      'mensagens' => mensagens, 'chamadas' => chamadas }.compact
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
end
