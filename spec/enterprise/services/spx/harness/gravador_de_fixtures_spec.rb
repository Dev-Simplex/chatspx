require 'rails_helper'

RSpec.describe Spx::Harness::GravadorDeFixtures do
  let(:account) { create(:account, custom_attributes: { 'captain_tool_context' => true, 'eval_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Ana Paula') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:assistant) { create(:captain_assistant, account: account, config: { 'instructions' => 'seja breve' }) }
  let(:destino) { Rails.root.join('tmp/harness-spec', "#{SecureRandom.hex(4)}.yml").to_s }

  def mensagem(texto, entrada: true, quando: 5.minutes.ago)
    create(:message, account: account, inbox: inbox, conversation: conversation, content: texto,
                     message_type: entrada ? :incoming : :outgoing, created_at: quando)
  end

  def chamada(tool, args, resultado, status: 'ok', quando: 4.minutes.ago)
    Captain::ToolCall.create!(account_id: account.id, conversation_id: conversation.id,
                              captain_assistant_id: assistant.id, tool_name: tool, args: args,
                              result_preview: resultado, status: status, created_at: quando)
  end

  after { FileUtils.rm_f(destino) }

  describe 'a ordem não negociável' do
    # Se a trava falhar, NADA pode ter sido escrito. Um arquivo parcial no worktree é o commit
    # acidental que a regra existe para impedir.
    it 'não escreve arquivo nenhum quando a trava acusa' do
      mensagem('oi')
      chamada('buscar_imovel', { 'bairro' => 'Centro' }, 'ok')
      allow(Spx::Harness::Vazamento).to receive(:conferir!).and_raise(Spx::Harness::Vazamento::Encontrado, 'boom')

      expect { described_class.new(conversation: conversation, id: 'f1').gravar!(destino) }
        .to raise_error(Spx::Harness::Vazamento::Encontrado)
      expect(File).not_to exist(destino)
    end

    it 'grava quando a trava passa' do
      mensagem('quero alugar')
      chamada('buscar_imovel', { 'bairro' => 'Centro' }, '(cód 9908) Casa, R$ 1.200')

      described_class.new(conversation: conversation, id: 'f2').gravar!(destino)

      expect(File).to exist(destino)
      expect(Spx::Harness::Vazamento.varrer(File.read(destino))).to be_empty
    end
  end

  describe 'pseudonimização antes do disco' do
    it 'não deixa telefone, e-mail nem nome do contato chegarem ao arquivo' do
      mensagem('sou a Ana Paula, zap 66 99958-6623, ana@gmail.com')
      chamada('salvar_info_lead', { 'telefone' => '66 99958-6623' }, 'salvo')

      described_class.new(conversation: conversation, id: 'f3').gravar!(destino)
      conteudo = File.read(destino)

      expect(conteudo).not_to include('99958-6623')
      expect(conteudo).not_to include('ana@gmail.com')
      expect(conteudo).not_to include('Ana Paula')
    end
  end

  describe 'o que vai para o versionado' do
    before do
      mensagem('quero alugar no Centro')
      chamada('buscar_imovel', { 'bairro' => 'Centro' }, '(cód 9908) Casa, R$ 1.200')
    end

    # Decisão de 20/09: nem a fala pseudonimizada entra no git — vira paráfrase.
    it 'troca a fala pelo marcador de paráfrase, guardando o digest para rastrear' do
      dados = described_class.new(conversation: conversation, id: 'f4').gravar!(destino)

      expect(dados['mensagens'].first['texto']).to eq(described_class::PARAFRASEAR)
      expect(dados['mensagens'].first['texto_sha']).to match(/\A[0-9a-f]{12}\z/)
    end

    it 'preserva a fala pseudonimizada quando o destino é o corpus local' do
      dados = described_class.new(conversation: conversation, id: 'f5').gravar!(destino, parafrasear: false)

      expect(dados['mensagens'].first['texto']).to include('Centro')
    end

    # O argumento e o retorno da tool são o objeto do teste — esses ficam.
    it 'mantém argumentos e retorno da ferramenta' do
      dados = described_class.new(conversation: conversation, id: 'f6').montar

      expect(dados['chamadas'].first['args']).to eq({ 'bairro' => 'Centro' })
      expect(dados['chamadas'].first['resultado']).to include('cód 9908', 'R$ 1.200')
    end
  end

  describe 'fidelidade' do
    it 'é faithful quando nenhum retorno veio truncado' do
      mensagem('oi')
      chamada('buscar_imovel', {}, 'curto')

      expect(described_class.new(conversation: conversation, id: 'f7').montar['fidelidade']).to eq('faithful')
    end

    # 23% das buscas da conta 6 caem aqui: o preview trunca em 1.500 e o corpo fica incompleto.
    it 'é reconstructed quando algum retorno bateu no teto do preview' do
      mensagem('oi')
      chamada('buscar_imovel', {}, 'x' * Captain::Tools::TraceRecorder::RESULT_PREVIEW_LIMIT)

      dados = described_class.new(conversation: conversation, id: 'f8').montar

      expect(dados['fidelidade']).to eq('reconstructed')
      expect(dados['chamadas'].first['truncado']).to be true
    end

    it 'basta UMA chamada truncada para a fixture inteira deixar de ser fiel' do
      mensagem('oi')
      chamada('faq_lookup', {}, 'curto', quando: 5.minutes.ago)
      chamada('buscar_imovel', {}, 'x' * 1600, quando: 4.minutes.ago)

      expect(described_class.new(conversation: conversation, id: 'f9').montar['fidelidade']).to eq('reconstructed')
    end
  end

  describe 'contexto que a fixture precisa carregar' do
    subject(:dados) { described_class.new(conversation: conversation, id: 'f10').montar }

    before do
      mensagem('oi', quando: Time.zone.parse('2026-09-02 14:31:00'))
      chamada('buscar_imovel', {}, 'ok')
    end

    it 'congela o relógio no instante do atendimento, não no da gravação' do
      expect(dados['relogio']).to start_with('2026-09-02T14:31')
    end

    it 'carrega as flags da conta, que decidem metade do comportamento' do
      expect(dados['conta']['flags']).to include('captain_tool_context' => true, 'eval_enabled' => true)
    end

    # Digest e não o texto: identifica a versão do prompt sem pôr o prompt do cliente no git.
    it 'identifica a versão de prompt e config por digest' do
      expect(dados['assistente']['instructions_digest']).to match(/\A[0-9a-f]{12}\z/)
      expect(dados.to_yaml).not_to include('seja breve')
    end

    it 'registra conta, conversa e a ordem das chamadas' do
      expect(dados['origem']).to include('conta' => account.id, 'conversa' => conversation.display_id)
      expect(dados['chamadas'].first['ordem']).to eq(1)
    end
  end

  describe 'a porta do ledger' do
    before do
      mensagem('oi')
      chamada('buscar_imovel', {}, 'x' * 1600)
    end

    # A branch factguard-shadow nunca rodou, então a tabela não existe em lugar nenhum hoje.
    # O gravador precisa seguir sem ela — e sem fingir fidelidade que não tem.
    it 'segue pelo preview quando a tabela não existe, marcando reconstructed' do
      expect(described_class.new(conversation: conversation, id: 'f11').montar['fidelidade']).to eq('reconstructed')
    end

    it 'não derruba a gravação se a consulta ao ledger falhar' do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?).with(described_class::TABELA_LEDGER)
                                                                     .and_return(true)
      allow(ActiveRecord::Base.connection).to receive(:select_one).and_raise(StandardError, 'sem coluna')

      expect(described_class.new(conversation: conversation, id: 'f12').montar['fidelidade']).to eq('reconstructed')
    end
  end
end
