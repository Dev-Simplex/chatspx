require 'rails_helper'

RSpec.describe Captain::Conversation::ToolContextNote do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }

  def ligar!
    account.update!(custom_attributes: account.custom_attributes.merge('captain_tool_context' => true))
    conversation.reload
  end

  def registrar(tool_name, args, resultado, status: 'ok', quando: Time.current)
    Captain::ToolCall.create!(
      account_id: account.id, conversation_id: conversation.id, captain_assistant_id: assistant.id,
      tool_name: tool_name, args: args, result_preview: resultado, status: status, created_at: quando
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

    # Ferramenta que estourou não é fato sobre o acervo — é falha de consulta. Trazer isso
    # como "o que a ferramenta devolveu" faria o agente concluir ausência a partir de erro.
    it 'ignora chamada que terminou em erro' do
      ligar!
      registrar('buscar_imovel', { 'codigo' => '1' }, nil, status: 'error')

      expect(described_class.new(conversation: conversation).text).to be_nil
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
