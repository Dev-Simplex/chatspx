require 'rails_helper'

RSpec.describe Spx::Social::ResponderComentarioComIa do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_instagram, account: account, instagram_id: '17841468839878751') }
  let(:inbox) { channel.inbox }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:publicacao) do
    create(:social_publicacao, account: account, inbox: inbox, legenda: 'Promoção de agosto')
  end
  let(:comentario) do
    create(:social_comentario, account: account, inbox: inbox, publicacao: publicacao,
                               publicacao_external_id: publicacao.external_id,
                               autor_username: 'pauloseze', texto: 'abre domingo?')
  end

  def configurar(config_ia, resto = {})
    base = { 'privada' => true, 'allowlist' => ['pauloseze'] }.merge(resto)
    account.update!(settings: (account.settings || {}).merge('social_reply' => base.merge('ia' => config_ia)))
    account.reload
  end

  def responder_com(texto)
    runner = instance_double(Captain::Assistant::AgentRunnerService, generate_response: texto)
    allow(Captain::Assistant::AgentRunnerService).to receive(:new).and_return(runner)
    runner
  end

  before do
    stub_request(:post, /graph\.instagram\.com/)
      .to_return(status: 200, body: { message_id: 'm-1' }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  # Ausência de configuração significa "não", nunca "adivinhe" — mesmo princípio da allowlist.
  it 'não responde sem configuração de IA' do
    configurar({})

    expect(described_class.new(comentario: comentario).perform).to eq(:desligada)
  end

  it 'não responde sem assistente configurado' do
    configurar('ativa' => true)

    expect(described_class.new(comentario: comentario).perform).to eq(:sem_assistente)
  end

  # A IA passa pelo MESMO portão da resposta manual: no piloto ela não alcança cliente real.
  it 'respeita a allowlist do piloto' do
    configurar({ 'ativa' => true, 'assistant_id' => assistant.id }, 'allowlist' => ['outra_pessoa'])

    expect(described_class.new(comentario: comentario).perform).to eq(:fora_do_piloto)
  end

  it 'não responde comentário da própria conta' do
    configurar('ativa' => true, 'assistant_id' => assistant.id)
    comentario.update!(proprio: true)

    expect(described_class.new(comentario: comentario).perform).to eq(:comentario_da_propria_conta)
  end

  context 'when the gate allows it' do
    before { configurar('ativa' => true, 'assistant_id' => assistant.id) }

    it 'envia o que o assistente devolveu' do
      responder_com('Abre sim, das 8h às 13h')

      resultado = described_class.new(comentario: comentario).perform

      expect(resultado.ok?).to be true
      expect(comentario.reload.respostas_registradas.dig('privada', 'external_id')).to eq('m-1')
    end

    # `[IGNORAR]` é silêncio deliberado em todo o resto do produto, e vale igual aqui.
    it 'não envia nada quando o assistente pede para ignorar' do
      responder_com('[IGNORAR]')

      expect(described_class.new(comentario: comentario).perform).to eq(:sem_resposta)
      expect(comentario.reload.respostas_registradas).to be_empty
    end

    it 'não envia resposta vazia' do
      responder_com('   ')

      expect(described_class.new(comentario: comentario).perform).to eq(:sem_resposta)
    end

    it 'engole falha do modelo sem derrubar nada' do
      allow(Captain::Assistant::AgentRunnerService).to receive(:new).and_raise(StandardError, 'timeout')

      expect(described_class.new(comentario: comentario).perform).to eq(:sem_resposta)
    end

    # Os FATOS vão rotulados; conduta é do assistente, no banco da conta.
    it 'entrega ao assistente o autor, a legenda e o texto do comentário' do
      runner = responder_com('ok')

      described_class.new(comentario: comentario).perform

      expect(runner).to have_received(:generate_response) do |args|
        conteudo = args[:message_history].first[:content]
        expect(conteudo).to include('@pauloseze')
        expect(conteudo).to include('Promoção de agosto')
        expect(conteudo).to include('abre domingo?')
      end
    end

    it 'usa a forma configurada' do
      configurar({ 'ativa' => true, 'assistant_id' => assistant.id, 'forma' => 'publica' }, 'publica' => true)
      responder_com('ok')

      described_class.new(comentario: comentario).perform

      expect(comentario.reload.respostas_registradas.keys).to eq(['publica'])
    end
  end
end
