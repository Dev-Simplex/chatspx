require 'rails_helper'

# Os caminhos que disparavam SEM assinatura nenhuma: o destino recebia dados de conversa e
# nao tinha como provar que vieram de nos.
RSpec.describe Webhook do
  describe '.signing_secret_for' do
    let(:account) { create(:account) }

    it 'devolve o segredo do webhook registrado com aquela URL' do
      webhook = create(:webhook, account: account, url: 'https://destino.exemplo.com/h',
                                 subscriptions: ['conversation_created'])

      expect(described_class.signing_secret_for(account: account, url: 'https://destino.exemplo.com/h'))
        .to eq(webhook.secret)
    end

    it 'devolve nil para URL que a conta nunca registrou' do
      expect(described_class.signing_secret_for(account: account, url: 'https://desconhecida.exemplo.com/h')).to be_nil
    end

    it 'nao vaza segredo de outra conta' do
      outra = create(:account)
      create(:webhook, account: outra, url: 'https://destino.exemplo.com/h', subscriptions: ['conversation_created'])

      expect(described_class.signing_secret_for(account: account, url: 'https://destino.exemplo.com/h')).to be_nil
    end

    it 'aguenta conta ou url ausente' do
      expect(described_class.signing_secret_for(account: nil, url: 'https://x.test')).to be_nil
      expect(described_class.signing_secret_for(account: account, url: nil)).to be_nil
    end
  end
end
