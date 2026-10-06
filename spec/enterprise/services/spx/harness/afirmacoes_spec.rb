require 'rails_helper'

# A asserção de um cenário não é "o preço bateu". A mesma fala da conv 41803 afirma preço,
# quartos, suíte e vagas — quatro fatos sobre um imóvel que nenhuma busca do atendimento
# devolveu. Assertar só o preço deixaria três invenções passarem no verde.
RSpec.describe Spx::Harness::Afirmacoes do
  describe '.extrair' do
    it 'pega as quatro afirmações da fala real da 41803' do
      fala = 'esse fica em R$ 2.400 por mês, são 3 quartos sendo 1 suíte e 2 vagas de garagem'

      expect(described_class.extrair(fala)).to contain_exactly(
        { 'classe' => 'imovel', 'tipo' => 'preco', 'valor' => 2400.0 },
        { 'classe' => 'imovel', 'tipo' => 'dormitorios', 'valor' => 3.0 },
        { 'classe' => 'imovel', 'tipo' => 'suites', 'valor' => 1.0 },
        { 'classe' => 'imovel', 'tipo' => 'vagas', 'valor' => 2.0 }
      )
    end

    it 'pega código de imóvel e área' do
      afirmacoes = described_class.extrair('o cód 9412 tem 250 m²')

      expect(afirmacoes).to include({ 'classe' => 'imovel', 'tipo' => 'codigo', 'valor' => '9412' },
                                    { 'classe' => 'imovel', 'tipo' => 'area', 'valor' => 250.0 })
    end

    # Número sem âncora não é afirmação sobre o imóvel — mesmo critério da Preservacao. Sem
    # isso, "das 7h30 às 17h30" viraria quatro fatos inventados e o cenário acusaria fantasma.
    # O telefone, porém, é afirmação sobre a EMPRESA (ver nivel1/telefone_da_empresa_spec.rb).
    it 'não transforma horário, data e telefone em afirmação sobre o imóvel' do
      afirmacoes = described_class.extrair('atendemos das 7h30 às 17h30, dia 02/09, no (66) 3531-7222')

      expect(afirmacoes).to contain_exactly({ 'classe' => 'empresa', 'tipo' => 'telefone', 'valor' => '(66) 3531-7222' })
    end

    it 'não inventa afirmação em fala sem fato' do
      expect(described_class.extrair('claro, já vou verificar com o time')).to be_empty
    end

    # A fala real da 41803 depois do carrossel. É afirmação de AÇÃO, não sobre o imóvel: não
    # diz o que a casa é, diz o que o agente fez.
    it 'separa o que o agente FEZ do que o imóvel É' do
      afirmacoes = described_class.extrair('Prontinho! Mandei as fotos e a localização da casa pra você.')

      expect(afirmacoes).to contain_exactly(
        { 'classe' => 'acao', 'tipo' => 'fotos_enviadas' },
        { 'classe' => 'acao', 'tipo' => 'localizacao_enviada' }
      )
    end

    it 'guarda quantidade e código quando a fala os declara' do
      expect(described_class.extrair('Enviei 9 fotos do imóvel 9412')).to include(
        { 'classe' => 'acao', 'tipo' => 'fotos_enviadas', 'quantidade' => 9, 'codigo' => '9412' }
      )
    end
  end

  describe '.evidencia_antes' do
    let(:chamadas) do
      [{ 'tool' => 'atualizar_resumo', 'em' => '2026-09-11T17:10:00' },
       { 'tool' => 'buscar_imovel', 'em' => '2026-09-11T17:13:00' }]
    end

    # O caso da 41803: as cinco chamadas do atendimento são registro, transferência e envio —
    # nenhuma é busca. O agente afirmou sem ter o que consultar.
    it 'devolve vazio quando nenhuma busca precedeu a fala' do
      expect(described_class.evidencia_antes(chamadas, '2026-09-11T17:11:00')).to be_empty
    end

    it 'devolve a busca que veio antes' do
      expect(described_class.evidencia_antes(chamadas, '2026-09-11T17:14:00')).to eq(['buscar_imovel'])
    end

    # Resumo, handoff e observação não comprovam preço nenhum. A lista é por NOME de propósito.
    it 'não conta ferramenta que não produz evidência sobre imóvel' do
      apenas_resumo = [{ 'tool' => 'atualizar_resumo', 'em' => '2026-09-11T17:10:00' }]

      expect(described_class.evidencia_antes(apenas_resumo, '2026-09-11T17:20:00')).to be_empty
    end
  end

  # As quatro afirmações da 41803 contra a ficha do cenário. A ficha traz aluguel 3.200,
  # condomínio 732 e 3 dormitórios — e NÃO traz suíte nem vaga, porque o PropertyRef nunca
  # pede esses campos ao Vista. Quatro afirmações, três vereditos diferentes.
  describe '.esperado — classe imovel' do
    let(:ficha) { { 'Codigo' => '9412', 'ValorLocacao' => 3200, 'ValorCondominio' => 732, 'Dormitorios' => 3 } }
    let(:sem_busca) { [{ 'tool' => 'atualizar_resumo', 'em' => '2026-09-11T17:10:00' }] }

    def julgar(tipo, valor)
      described_class.esperado({ 'classe' => 'imovel', 'tipo' => tipo, 'valor' => valor },
                               sem_busca, '2026-09-11T17:11:15', ficha: ficha)
    end

    it 'bloqueia o preço que a ficha desmente' do
      expect(julgar('preco', 2400.0)).to eq(['bloquear', 'a ficha diz 3200.0, a fala diz 2400.0'])
    end

    it 'permite o número de dormitórios que a ficha confirma' do
      expect(julgar('dormitorios', 3.0)).to eq(['permitir', 'a ficha confirma'])
    end

    # Não é "a ficha não trouxe desta vez": a ficha NUNCA traz. Afirmar suíte com ela no
    # contexto é inventar, sempre.
    it 'bloqueia suíte e vaga, que a ficha não cobre em campo nenhum' do
      expect(julgar('suites', 1.0)).to eq(['bloquear', 'nenhuma fonte cobre este campo'])
      expect(julgar('vagas', 2.0)).to eq(['bloquear', 'nenhuma fonte cobre este campo'])
    end

    # Imóvel à venda E para locação: uma fala de "R$ 3.200" não diz qual dos dois. Escolher um
    # por conta própria inventaria contradição onde não há.
    it 'aceita qualquer um dos valores quando a ficha tem venda e locação' do
      dois = { 'ValorVenda' => 890_000, 'ValorLocacao' => 3200 }
      afirmacao = { 'classe' => 'imovel', 'tipo' => 'preco', 'valor' => 890_000.0 }

      expect(described_class.esperado(afirmacao, sem_busca, '2026-09-11T17:11:15', ficha: dois))
        .to eq(['permitir', 'a ficha confirma'])
    end

    it 'manda conferir contra a busca quando houve busca antes da fala' do
      com_busca = [{ 'tool' => 'buscar_imovel', 'em' => '2026-09-11T17:10:00' }]
      afirmacao = { 'classe' => 'imovel', 'tipo' => 'preco', 'valor' => 2400.0 }

      expect(described_class.esperado(afirmacao, com_busca, '2026-09-11T17:11:15', ficha: ficha))
        .to eq(['conferir_contra_busca', 'houve busca antes da fala'])
    end

    it 'bloqueia sem ficha nenhuma' do
      afirmacao = { 'classe' => 'imovel', 'tipo' => 'preco', 'valor' => 2400.0 }

      expect(described_class.esperado(afirmacao, sem_busca, '2026-09-11T17:11:15'))
        .to eq(['bloquear', 'nenhuma fonte cobre este campo'])
    end
  end

  # Fato de AÇÃO não se prova pelo status. Medido na conv 19863: a enviar_fotos_imovel grava
  # `status: ok` também quando BARRA o envio. Só o conteúdo do retorno distingue.
  describe '.esperado — classe acao' do
    let(:instante) { '2026-09-11T17:12:35-04:00' }

    def chamada(tool:, status:, resultado:)
      [{ 'tool' => tool, 'em' => '2026-09-11T17:12:29-04:00', 'status' => status, 'resultado' => resultado }]
    end

    def julgar(afirmacao, chamadas)
      described_class.esperado(afirmacao, chamadas, instante)
    end

    # 1 de 3: a tool confirmou sucesso E o conteúdo bate.
    it 'permite quando a ação confirmou sucesso e o conteúdo bate' do
      chamadas = chamada(tool: 'enviar_fotos_imovel', status: 'ok',
                         resultado: 'Enviei um carrossel com 9 fotos do imóvel 9412, com botões de interesse.')
      afirmacao = { 'classe' => 'acao', 'tipo' => 'fotos_enviadas', 'quantidade' => 9, 'codigo' => '9412' }

      expect(julgar(afirmacao, chamadas)).to eq(['permitir', 'a ação confirmou conteúdo compatível'])
    end

    # 2 de 3: sucesso, conteúdo divergente. Duas divergências contam — quantidade e código.
    it 'bloqueia quando a fala declara quantidade diferente da que a ação confirmou' do
      chamadas = chamada(tool: 'enviar_fotos_imovel', status: 'ok',
                         resultado: 'Enviei um carrossel com 9 fotos do imóvel 9412.')
      afirmacao = { 'classe' => 'acao', 'tipo' => 'fotos_enviadas', 'quantidade' => 12 }

      expect(julgar(afirmacao, chamadas)).to eq(['bloquear', 'a ação confirmou 9, a fala diz 12'])
    end

    it 'bloqueia quando a fala declara outro imóvel' do
      chamadas = chamada(tool: 'enviar_fotos_imovel', status: 'ok',
                         resultado: 'Enviei um carrossel com 9 fotos do imóvel 9412.')
      afirmacao = { 'classe' => 'acao', 'tipo' => 'fotos_enviadas', 'codigo' => '9849' }

      expect(julgar(afirmacao, chamadas)).to eq(['bloquear', 'a ação foi sobre 9412, a fala diz 9849'])
    end

    # 3 de 3: a regra nova do P0. Ação que voltou indeterminada não autoriza "mandei" —
    # não se sabe se aconteceu, e é justamente o estado em que o modelo não pode afirmar.
    it 'bloqueia quando a ação voltou indeterminada' do
      chamadas = chamada(tool: 'enviar_fotos_imovel',
                         status: Captain::Tools::Result::STATUS_PERSISTIDO.fetch(:desconhecido),
                         resultado: Captain::Tools::HttpAcao::ACAO_INDETERMINADA)
      afirmacao = { 'classe' => 'acao', 'tipo' => 'fotos_enviadas' }

      expect(julgar(afirmacao, chamadas))
        .to eq(['bloquear', 'a ação voltou desconhecido: não se sabe se aconteceu'])
    end

    # Os dois retornos reais da conv 19863 que provam por que ler o status não basta: as duas
    # ferramentas BARRARAM o envio e gravaram 'ok' do mesmo jeito.
    it 'bloqueia quando a trava anti-alucinação barrou o envio, apesar do status ok' do
      chamadas = chamada(tool: 'enviar_fotos_imovel', status: 'ok',
                         resultado: 'O código 9849 não apareceu na busca desta conversa.')

      expect(julgar({ 'classe' => 'acao', 'tipo' => 'fotos_enviadas' }, chamadas))
        .to eq(['bloquear', 'o retorno não confirma envio'])
    end

    it 'bloqueia quando o cooldown barrou o envio, apesar do status ok' do
      chamadas = chamada(tool: 'enviar_fotos_imovel', status: 'ok',
                         resultado: 'Você acabou de enviar fotos há pouco. NÃO envie mais fotos agora.')

      expect(julgar({ 'classe' => 'acao', 'tipo' => 'fotos_enviadas' }, chamadas))
        .to eq(['bloquear', 'o retorno não confirma envio'])
    end

    it 'bloqueia quando a ferramenta de ação nem rodou' do
      expect(julgar({ 'classe' => 'acao', 'tipo' => 'fotos_enviadas' }, []))
        .to eq(['bloquear', 'a ferramenta de ação não rodou'])
    end

    # A tool pode rodar antes ou depois da fala (a IA promete e a tool cumpre, ou a tool roda e
    # a IA narra). Fora da janela, não é a mesma ação.
    it 'não aceita ação distante da fala' do
      distante = [{ 'tool' => 'enviar_fotos_imovel', 'em' => '2026-09-11T16:00:00-04:00',
                    'status' => 'ok', 'resultado' => 'Enviei 9 fotos do imóvel 9412.' }]

      expect(julgar({ 'classe' => 'acao', 'tipo' => 'fotos_enviadas' }, distante))
        .to eq(['bloquear', 'a ferramenta de ação não rodou'])
    end

    it 'permite o pin quando a ferramenta de localização confirmou' do
      chamadas = chamada(tool: 'enviar_localizacao_imovel', status: 'ok',
                         resultado: 'Pin de localização do imóvel 9412 enviado ao cliente.')

      expect(julgar({ 'classe' => 'acao', 'tipo' => 'localizacao_enviada' }, chamadas))
        .to eq(['permitir', 'a ação confirmou conteúdo compatível'])
    end
  end
end
