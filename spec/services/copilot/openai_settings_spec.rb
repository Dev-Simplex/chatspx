require 'rails_helper'

# Conv 30328 (Tozi, 08/09): a cliente respondeu a stories de vídeo e a IA respondeu no
# escuro. O pipeline de vídeo estava deployado e funcionando — o que falhava era a chamada
# de visão, com 401. E o 401 não era chave ruim: era chave AUSENTE. As duas chaves de OpenAI
# da instalação respondiam HTTP 200 quando testadas, mas nenhuma morava nos dois lugares que
# o `api_key` lia, então o header saía com "Bearer " vazio.
RSpec.describe Copilot::OpenaiSettings do
  let(:account) { create(:account) }

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
    it 'survives the config lookup blowing up' do
      allow(InstallationConfig).to receive(:find_by).and_raise(StandardError, 'banco fora')

      expect { described_class.api_key(account) }.not_to raise_error
      expect(described_class.api_key(account)).to be_nil
    end

    it 'works without an account at all' do
      InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').destroy_all
      InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'a-global-do-captain')

      expect(described_class.api_key(nil)).to eq('a-global-do-captain')
    end
  end
end
