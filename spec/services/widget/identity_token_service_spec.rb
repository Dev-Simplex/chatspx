require 'rails_helper'

# Bloco 5.19 — o JWT de identidade, formato ADICIONAL ao HMAC.
#
# Quem assina continua sendo o SERVIDOR DO CLIENTE, com o mesmo segredo do HMAC
# (`channel_web_widgets.hmac_token`). O visitante nunca assina nada: ele so carrega um token que
# recebeu pronto. Isso e deliberado — exigir assinatura do visitante desligaria a coleta do pre-chat.
RSpec.describe Widget::IdentityTokenService do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:secret) { web_widget.hmac_token }

  def encode(payload, key: secret, algorithm: 'HS256')
    JWT.encode(payload, key, algorithm)
  end

  def perform(token)
    described_class.new(token: token, hmac_token: secret).perform
  end

  describe 'a valid token' do
    let(:token) { encode({ sub: 'cliente-42', exp: 1.hour.from_now.to_i }) }

    it 'is verified and carries the subject as the identifier' do
      result = perform(token)

      expect(result).to be_verified
      expect(result.status).to eq(:verified)
      expect(result.identifier).to eq('cliente-42')
    end

    it 'carries only the authenticated attributes of the allowlist' do
      full = encode({ sub: 'cliente-42', exp: 1.hour.from_now.to_i,
                      email: 'maria@exemplo.com.br', name: 'Maria', phone_number: '+5511999999999',
                      avatar_url: 'https://exemplo.com.br/m.png', role: 'admin', account_id: 999 })

      result = perform(full)

      expect(result.attributes).to eq({ 'email' => 'maria@exemplo.com.br', 'name' => 'Maria',
                                        'phone_number' => '+5511999999999',
                                        'avatar_url' => 'https://exemplo.com.br/m.png' })
    end

    it 'ignores an attribute that is not a scalar' do
      result = perform(encode({ sub: 'c1', exp: 1.hour.from_now.to_i, email: { nested: 'x' } }))

      expect(result).to be_verified
      expect(result.attributes).to eq({})
    end
  end

  describe 'a token that does not prove anything' do
    it 'reports :absent for a blank token, without raising' do
      expect(perform(nil).status).to eq(:absent)
      expect(perform('').status).to eq(:absent)
    end

    # O aceite do bloco: expirado degrada para ANONIMO, nunca vira erro.
    it 'reports :expired for an expired token' do
      result = perform(encode({ sub: 'cliente-42', exp: 5.minutes.ago.to_i }))

      expect(result.status).to eq(:expired)
      expect(result).not_to be_verified
      expect(result.identifier).to be_nil
      expect(result.attributes).to eq({})
    end

    it 'refuses a token with no exp — sem validade, um token vazado vale para sempre' do
      expect(perform(encode({ sub: 'cliente-42' })).status).to eq(:invalid)
    end

    it 'refuses a token with no sub — nao se identifica quem nao foi nomeado' do
      expect(perform(encode({ exp: 1.hour.from_now.to_i })).status).to eq(:invalid)
    end

    it 'refuses a token whose sub is blank' do
      expect(perform(encode({ sub: '   ', exp: 1.hour.from_now.to_i })).status).to eq(:invalid)
    end

    it 'refuses a token signed with another secret' do
      expect(perform(encode({ sub: 'c1', exp: 1.hour.from_now.to_i }, key: 'outro-segredo')).status).to eq(:invalid)
    end

    # A armadilha classica de JWT: o atacante escolhe o algoritmo.
    it 'refuses alg: none, even with the right claims' do
      unsigned = JWT.encode({ sub: 'c1', exp: 1.hour.from_now.to_i }, nil, 'none')

      expect(perform(unsigned).status).to eq(:invalid)
    end

    it 'refuses garbage that is not a token at all' do
      expect(perform('nao.e.um.jwt').status).to eq(:invalid)
    end
  end

  describe 'the secret is the channel one, so one inbox cannot sign for another' do
    it 'refuses a token signed with the hmac_token of a different inbox' do
      other_widget = create(:channel_widget, account: account)
      token = encode({ sub: 'c1', exp: 1.hour.from_now.to_i }, key: other_widget.hmac_token)

      expect(perform(token).status).to eq(:invalid)
    end
  end
end
