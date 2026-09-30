require 'rails_helper'

RSpec.describe Captain::Conversation::ToolContextNote do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }

  def ligar!
    account.update!(custom_attributes: account.custom_attributes.merge('captain_tool_context' => true))
    conversation.reload
  end

  def registrar(tool_name, args, resultado, opcoes = {})
    Captain::ToolCall.create!(
      account_id: account.id, conversation_id: conversation.id, captain_assistant_id: assistant.id,
      tool_name: tool_name, args: args, result_preview: resultado,
      status: opcoes.fetch(:status, 'ok'), created_at: opcoes.fetch(:quando, Time.current),
      error: opcoes[:erro]
    )
  end

  describe '#text' do
    it 'devolve nil quando a conta não pediu o contexto' do
      registrar('buscar_imovel', { 'codigo' => '2498' }, 'algum retorno')

      expect(described_class.new(conversation: conversation).text).to be_nil
    end

    it 'devolve nil quando a conta pediu mas nenhuma ferramenta rodou' do
      ligar!

      expect(described_class.new(conversation: conversation).text).to be_nil
    end

    # É o caso da conv 36940: o rótulo estava no retorno da busca e sumiu do contexto dois
    # turnos depois, e a IA afirmou o contrário do que a ferramenta tinha dito.
    it 'traz de volta o retorno com o argumento que o produziu' do
      ligar!
      registrar('buscar_imovel', { 'bairro' => 'Portal da Mata', 'status_tipo' => 'locacao' },
                '1) (cód 2498) Casa no Residencial Deville [AVULSO — fora de condomínio fechado]')

      texto = described_class.new(conversation: conversation).text

      expect(texto).to include('buscar_imovel')
      expect(texto).to include('bairro: "Portal da Mata"')
      expect(texto).to include('[AVULSO — fora de condomínio fechado]')
    end

    it 'lista em ordem cronológica, da mais antiga para a mais recente' do
      ligar!
      registrar('buscar_imovel', { 'codigo' => '1' }, 'primeira', quando: 3.minutes.ago)
      registrar('enviar_fotos_imovel', { 'codigo' => '2' }, 'segunda', quando: 1.minute.ago)

      texto = described_class.new(conversation: conversation).text

      expect(texto.index('primeira')).to be < texto.index('segunda')
    end

    # Sem teto, uma conversa longa empurraria o turno do cliente para longe no contexto.
    it 'mantém apenas as últimas chamadas, e mantém as MAIS RECENTES' do
      ligar!
      (1..(described_class::LIMITE_CHAMADAS + 2)).each do |i|
        registrar('buscar_imovel', { 'n' => i.to_s }, "retorno #{i}", quando: (20 - i).minutes.ago)
      end

      texto = described_class.new(conversation: conversation).text

      expect(texto.scan('buscar_imovel').size).to eq(described_class::LIMITE_CHAMADAS)
      expect(texto).to include("retorno #{described_class::LIMITE_CHAMADAS + 2}")
      expect(texto).not_to include('retorno 1 ')
    end

    it 'trunca retorno longo em vez de despejar o preview inteiro' do
      ligar!
      registrar('buscar_imovel', { 'codigo' => '1' }, 'x' * 2_000)

      texto = described_class.new(conversation: conversation).text

      expect(texto).to include('…')
      expect(texto.length).to be < 2_000
    end

    # INVERTIDO em 20/09. Este teste afirmava que a chamada com erro era IGNORADA, com a
    # justificativa de que trazê-la faria o agente concluir ausência a partir de erro. Medido na
    # auditoria: omiti-la é pior. A chamada some, o modelo lê a lacuna como "nunca consultei" e
    # completa de memória — a ausência que ele conclui passa a ser invisível no trace. O certo
    # não é esconder a falha: é rotulá-la como falha.
    it 'traz a chamada que falhou, rotulada como não confirmada' do
      ligar!
      registrar('buscar_imovel', { 'codigo' => '1' }, nil, status: 'error')

      texto = described_class.new(conversation: conversation).text

      expect(texto).to include('buscar_imovel')
      expect(texto).to include('NÃO CONFIRMOU')
    end

    it 'trata desconhecido como não confirmado, e usa o texto da própria ferramenta como motivo' do
      ligar!
      registrar('buscar_cep', { 'cep' => '78550' }, 'A consulta foi respondida, mas veio sem conteúdo.',
                status: 'desconhecido')

      texto = described_class.new(conversation: conversation).text

      expect(texto).to include('NÃO CONFIRMOU')
      expect(texto).to include('veio sem conteúdo')
    end

    it 'explica no cabeçalho o que a marca de falha significa' do
      ligar!
      registrar('buscar_imovel', { 'codigo' => '1' }, nil, status: 'error')

      expect(described_class.new(conversation: conversation).text).to include('não é ausência do dado')
    end

    # Regressão: sem falha nenhuma a nota tem que sair exatamente como saía antes deste PR —
    # é o que mantém o harness de conduta comparável entre antes e depois.
    it 'não muda o cabeçalho quando não houve falha' do
      ligar!
      registrar('buscar_imovel', { 'codigo' => '1' }, 'retorno bom')

      texto = described_class.new(conversation: conversation).text

      expect(texto).to start_with(described_class::CABECALHO)
      expect(texto).not_to include(described_class::AVISO_FALHA)
    end

    # vazio_completo e parcial são CONSULTAS QUE DERAM CERTO: entram como fato, não como falha.
    it 'trata vazio_completo e parcial como fato consultado' do
      ligar!
      registrar('buscar_imovel', { 'bairro' => 'Centro' }, 'Nenhum imóvel no critério', status: 'vazio_completo')
      registrar('buscar_imovel', { 'bairro' => 'Jardim' }, 'lista possivelmente incompleta', status: 'parcial')

      texto = described_class.new(conversation: conversation).text

      expect(texto).to include('devolveu: Nenhum imóvel no critério')
      expect(texto).to include('devolveu: lista possivelmente incompleta')
      expect(texto).not_to include('NÃO CONFIRMOU')
    end

    # Mostrar as duas faria o modelo dizer que a consulta falhou tendo o dado na mão.
    it 'omite a falha que uma consulta posterior da MESMA ferramenta resolveu' do
      ligar!
      registrar('buscar_imovel', { 'codigo' => '1' }, nil, status: 'error', quando: 3.minutes.ago)
      registrar('buscar_imovel', { 'codigo' => '1' }, 'Casa no Centro, R$ 1.200', quando: 1.minute.ago)

      texto = described_class.new(conversation: conversation).text

      expect(texto).to include('R$ 1.200')
      expect(texto).not_to include('NÃO CONFIRMOU')
    end

    it 'mantém a falha quando a ferramenta que voltou a funcionar foi OUTRA' do
      ligar!
      registrar('buscar_imovel', { 'codigo' => '1' }, nil, status: 'error', quando: 3.minutes.ago)
      registrar('buscar_unidades', {}, 'Unidade Centro', quando: 1.minute.ago)

      expect(described_class.new(conversation: conversation).text).to include('NÃO CONFIRMOU')
    end

    # O cabeçalho também contém a marca (é ele que a explica), então contar a marca solta
    # somaria o aviso às linhas. Aqui só as linhas de chamada entram na conta.
    def linhas_de_falha(texto)
      texto.to_s.lines.count { |l| l.start_with?('·') && l.include?('NÃO CONFIRMOU') }
    end

    # Uma rajada de timeout não pode empurrar pra fora da nota o preço que a busca trouxe antes.
    it 'colapsa falhas repetidas da mesma ferramenta e não consome o orçamento dos fatos' do
      ligar!
      registrar('buscar_imovel', { 'codigo' => 'bom' }, 'Casa no Centro, R$ 1.200', quando: 30.minutes.ago)
      8.times { |i| registrar('consultar_chave_imovel', { 'n' => i.to_s }, nil, status: 'error', quando: i.minutes.ago) }

      texto = described_class.new(conversation: conversation).text

      expect(texto).to include('R$ 1.200')
      expect(linhas_de_falha(texto)).to eq(1)
    end

    it 'limita o número de ferramentas distintas em falha' do
      ligar!
      (described_class::LIMITE_FALHAS + 2).times do |i|
        registrar("ferramenta_#{i}", {}, nil, status: 'error', quando: i.minutes.ago)
      end

      texto = described_class.new(conversation: conversation).text

      expect(linhas_de_falha(texto)).to eq(described_class::LIMITE_FALHAS)
    end

    # 255 é o teto que o ApplicationRecord impõe a coluna string sem validador próprio, e é por
    # isso que o recorder já grava truncado em 200. O corte da nota é menor ainda.
    it 'trunca o motivo da falha para não deslocar fato bom' do
      ligar!
      registrar('buscar_imovel', {}, nil, status: 'error', erro: 'y' * 250)

      texto = described_class.new(conversation: conversation).text

      expect(texto).to include('…')
      expect(texto).to include('y' * described_class::LIMITE_MOTIVO)
      expect(texto).not_to include('y' * (described_class::LIMITE_MOTIVO + 1))
    end

    # Com lock_to_single_conversation o fio do contato é perpétuo: sem o corte, busca de
    # meses atrás voltaria ao contexto como se fosse deste atendimento.
    it 'respeita a fronteira do atendimento atual' do
      ligar!
      registrar('buscar_imovel', { 'codigo' => 'velho' }, 'de outro atendimento', quando: 10.days.ago)
      registrar('buscar_imovel', { 'codigo' => 'novo' }, 'deste atendimento', quando: 1.minute.ago)

      texto = described_class.new(conversation: conversation, desde: 1.hour.ago).text

      expect(texto).to include('deste atendimento')
      expect(texto).not_to include('de outro atendimento')
    end

    it 'não deixa falha de leitura derrubar o turno' do
      ligar!
      registrar('buscar_imovel', { 'codigo' => '1' }, 'retorno')
      allow(Captain::ToolCall).to receive(:for_conversation).and_raise(StandardError, 'boom')

      expect(described_class.new(conversation: conversation).text).to be_nil
    end
  end

  describe '.enabled_for?' do
    it 'é falso por padrão — conta que não pediu não muda de comportamento' do
      expect(described_class.enabled_for?(account)).to be false
    end

    it 'é verdadeiro quando a conta liga a chave' do
      ligar!

      expect(described_class.enabled_for?(account.reload)).to be true
    end
  end
end
