require 'rails_helper'
require 'rake'

describe 'spx:onboarding' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account, name: 'Empresa Teste') }
  let(:assistant) do
    create(:captain_assistant, account: account, name: 'Lia',
                               config: { 'product_name' => 'Empresa Teste', 'instructions' => 'Atenda com cuidado.' },
                               behavior: { 'humanizer' => { 'enabled' => true, 'max_chars' => 200 } })
  end
  let(:inbox) { create(:inbox, account: account) }

  around do |example|
    original_application = Rake.application
    Rake.application = Rake::Application.new
    example.run
  ensure
    Rake.application = original_application
  end

  before do
    silence_warnings { load Rails.root.join('lib/tasks/spx_onboarding.rake') }
    Rake::Task.define_task(:environment)
    create(:captain_inbox, captain_assistant: assistant, inbox: inbox)
    InstallationConfig.where(name: SpxOnboarding::CHAVES_GLOBAIS.values).delete_all
  end

  def checar(env = {})
    with_modified_env(env) do
      expect { Rake::Task['spx:onboarding:checar'].invoke(account.id, assistant.id) }.to output.to_stdout
    end
  end

  def linhas(chamar: true)
    SpxOnboarding.checagens(account, assistant.reload, chamar: chamar).map { |icone, titulo, motivo| "#{icone} #{titulo}: #{motivo}" }
  end

  describe 'modelo' do
    it 'falha sem chave do provedor na conta e na instalação' do
      expect(linhas.first).to match(/\A❌ modelo .*sem chave/)
    end

    context 'with chave global' do
      before do
        create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'sk-teste')
        account.update!(captain_models: { 'assistant' => 'gpt-4.1' })
      end

      it 'aprova quando a chamada mínima responde' do
        allow(SpxOnboarding).to receive(:chamar_modelo).and_return(true)

        expect(linhas.first).to eq('✅ modelo gpt-4.1 (da conta, openai): chave global da instalação respondeu a uma chamada mínima')
      end

      it 'falha com o erro do provedor quando a chamada não gera texto' do
        allow(SpxOnboarding).to receive(:chamar_modelo).and_raise(StandardError, 'credit balance is too low')

        expect(linhas.first).to match(/\A❌ modelo gpt-4\.1 .*credit balance is too low/)
      end

      it 'só confere a chave quando a chamada está desligada' do
        expect(SpxOnboarding).not_to receive(:chamar_modelo)

        expect(linhas(chamar: false).first).to include('chave global da instalação presente; chamada não feita')
      end
    end
  end

  it 'mostra a trava de teste e os números liberados' do
    assistant.update!(behavior: assistant.behavior.merge('router' => { 'only_contact_phones' => ['+5566999990000'] }))

    expect(linhas).to include(a_string_matching(/trava de teste por telefone LIGADA: só responde a: \+5566999990000/))
  end

  it 'falha quando o assistente não está em caixa nenhuma' do
    CaptainInbox.where(captain_assistant_id: assistant.id).delete_all

    expect(linhas).to include('❌ caixas: o assistente não está ligado a caixa nenhuma')
  end

  describe 'caixa WAHA' do
    let(:waha) { instance_double(Waha::ApiService) }

    before do
      inbox.update!(waha_session_name: 'sessao-teste')
      allow(Waha::ApiService).to receive(:new).and_return(waha)
    end

    it 'falha quando a sessão não está WORKING' do
      allow(waha).to receive(:get_session).with('sessao-teste').and_return({ 'status' => 'SCAN_QR_CODE' })

      expect(linhas).to include(a_string_matching(/❌ caixa ##{inbox.id} .*sessão WAHA sessao-teste em SCAN_QR_CODE/))
    end

    it 'aprova a sessão conectada e avisa da pendência do status@broadcast' do
      allow(waha).to receive(:get_session).and_return({ 'status' => 'WORKING' })

      expect(linhas).to include(a_string_matching(/✅ caixa ##{inbox.id} .*conectada/),
                                a_string_matching(/status@broadcast .*CHAT-170.*nenhuma entrada em 24h/))
    end

    it 'falha quando stories ainda entram como conversa' do
      allow(waha).to receive(:get_session).and_return({ 'status' => 'WORKING' })
      contato = create(:contact, account: account, identifier: 'status@broadcast')
      conversa = create(:conversation, account: account, inbox: inbox, contact: contato)
      create(:message, account: account, inbox: inbox, conversation: conversa)

      expect(linhas).to include(a_string_matching(/❌ status@broadcast .*1 mensagem\(ns\) de stories nas últimas 24h/))
    end
  end

  it 'falha quando o humanizer está desligado' do
    assistant.update!(behavior: {})

    expect(linhas).to include(a_string_matching(/❌ humanizer: desligado/))
  end

  it 'aponta padrão de exemplo copiável nas instructions sem bloquear' do
    assistant.update!(config: assistant.config.merge('instructions' => 'Pergunte o modelo, por exemplo o ano.'))

    expect(linhas).to include(a_string_matching(/⚠️  instructions: "por exemplo"/))
  end

  it 'imprime o resumo da checagem sem gravar nada' do
    allow(SpxOnboarding).to receive(:chamar_modelo).and_return(true)

    expect { checar('SEM_CHAMADA' => '1') }.not_to(change { [assistant.reload.updated_at, account.reload.updated_at] })
  end

  it 'imprime um esqueleto de instructions com o nome e a empresa' do
    expect { Rake::Task['spx:onboarding:prompt_base'].invoke(account.id, assistant.id) }
      .to output(/Você é Lia, da Empresa Teste\.\nO que a Empresa Teste faz.* vêm das ferramentas/).to_stdout
  end
end
