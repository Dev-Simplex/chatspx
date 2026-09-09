require 'rails_helper'

# Conv 30328 (Tozi, 08/09): a cliente respondeu a stories de vídeo e a IA respondeu no
# escuro. O pipeline de vídeo estava deployado e funcionando — o que falhava era a chamada
# de visão, com 401. E o 401 não era chave ruim: era chave AUSENTE. As duas chaves de OpenAI
# da instalação respondiam HTTP 200 quando testadas, mas nenhuma morava nos dois lugares que
# o `api_key` lia, então o header saía com "Bearer " vazio.
RSpec.describe Copilot::OpenaiSettings do
  let(:account) { create(:account) }
  # A conta padrao destes exemplos USA o Captain. A global so vale para ela: e a mesma regua
  # do painel de Agentes IA (`has_ai_agents` = `captain_assistants.exists?`).
  let!(:assistente) { create(:captain_assistant, account: account) }

  describe '.api_key' do
    it 'prefers the key set on the account' do
      account.update!(settings: account.settings.merge('openai_api_key' => 'da-conta'))

      expect(described_class.api_key(account)).to eq('da-conta')
    end

    it 'falls back to the environment when the account has none' do
      with_modified_env OPENAI_API_KEY: 'do-env' do
        expect(described_class.api_key(account)).to eq('do-env')
      end
    end

    # O degrau que faltava: sem ele a descrição de mídia morria em silêncio numa instalação
    # inteira, mesmo com a chave configurada e válida.
    it "falls back to the Captain's global key when neither is set" do
      InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').destroy_all
      InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'a-global-do-captain')

      expect(described_class.api_key(account)).to eq('a-global-do-captain')
    end

    it 'keeps the account key ahead of the global one' do
      InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').destroy_all
      InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'a-global-do-captain')
      account.update!(settings: account.settings.merge('openai_api_key' => 'da-conta'))

      expect(described_class.api_key(account)).to eq('da-conta')
    end

    it 'is nil when there is no key anywhere' do
      InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').destroy_all

      expect(described_class.api_key(account)).to be_nil
    end

    it 'treats a blank global key as no key at all' do
      InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').destroy_all
      InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_API_KEY', value: '   ')

      expect(described_class.api_key(account)).to be_nil
    end

    # Quem pergunta se há chave não pode levar exceção de banco na cara.
    #
    # A conta é materializada ANTES do stub de propósito: `create(:account)` passa pelo
    # `Featurable#enable_default_features`, que também consulta InstallationConfig — com o
    # stub já de pé, a exceção vinha da fábrica e o teste media a si mesmo.
    it 'survives the config lookup blowing up' do
      conta = account
      assistente # materializa antes do stub, pelo mesmo motivo da conta
      allow(InstallationConfig).to receive(:find_by).and_raise(StandardError, 'banco fora')

      expect { described_class.api_key(conta) }.not_to raise_error
      expect(described_class.api_key(conta)).to be_nil
    end

    # O buraco que o degrau abriu: conta SEM agente nenhum passava a usar a chave da casa, e
    # com ela a sugestao fantasma — que dispara sozinha ao abrir a conversa, sem clique e sem
    # flag — mandava a mensagem do CLIENTE para a OpenAI. Medido na PRODUCAO em 09/09/2026:
    # contas 5 e 85, zero agentes, 12 chamadas numa hora. A flag `captain_integration*` NAO
    # serve de guarda: as 10 contas da box tem a flag ligada.
    it 'does NOT lend the global key to an account with no AI agent' do
      sem_agente = create(:account)
      InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').destroy_all
      InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'a-global-do-captain')

      expect(described_class.api_key(sem_agente)).to be_nil
    end

    # A chave da propria conta continua valendo mesmo sem agente: quem configurou, pagou.
    it 'still honors an account key when the account has no AI agent' do
      sem_agente = create(:account)
      sem_agente.update!(settings: sem_agente.settings.merge('openai_api_key' => 'da-conta'))

      expect(described_class.api_key(sem_agente)).to eq('da-conta')
    end

    it 'works without an account at all' do
      InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').destroy_all
      InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'a-global-do-captain')

      expect(described_class.api_key(nil)).to eq('a-global-do-captain')
    end
  end
end
