require 'rails_helper'

# Bloco 4.17 — o portao de escrita por atributo.
RSpec.describe CustomAttributes::OriginGate do
  let(:account) { create(:account) }

  def definition(key, protegida:, model: 'conversation_attribute')
    create(:custom_attribute_definition, account: account, attribute_key: key,
                                         attribute_model: model, attribute_display_type: 'text',
                                         requires_verified_origin: protegida)
  end

  def gate(verified:, model: :conversation_attribute)
    described_class.new(account: account, attribute_model: model, verified: verified)
  end

  describe 'sessao sem origem verificada' do
    before { definition('cpf', protegida: true) }

    it 'recusa a chave protegida' do
      resultado = gate(verified: false).filter({ 'cpf' => '000' })

      expect(resultado.allowed).to eq({})
      expect(resultado.refused).to eq(['cpf'])
      expect(resultado).to be_refused
    end

    # A recusa e por chave: derrubar a requisicao inteira faria o site do cliente parar de
    # funcionar por causa de um atributo que ele nem sabia estar protegido.
    it 'grava as demais chaves do mesmo payload' do
      definition('carrinho_valor', protegida: false)

      resultado = gate(verified: false).filter({ 'cpf' => '000', 'carrinho_valor' => 4200, 'cupom' => 'BLACK' })

      expect(resultado.allowed).to eq({ 'carrinho_valor' => 4200, 'cupom' => 'BLACK' })
      expect(resultado.refused).to eq(['cpf'])
    end

    it 'registra a tentativa nomeando conta, modelo e chaves' do
      allow(Rails.logger).to receive(:warn)

      gate(verified: false).filter({ 'cpf' => '000' })

      expect(Rails.logger).to have_received(:warn)
        .with("[custom_attributes] escrita recusada por origem nao verificada account_id=#{account.id} " \
              'modelo=conversation_attribute chaves=cpf')
    end

    it 'nao registra nada quando nenhuma chave protegida foi tocada' do
      allow(Rails.logger).to receive(:warn)

      gate(verified: false).filter({ 'carrinho_valor' => 4200 })

      expect(Rails.logger).not_to have_received(:warn)
    end
  end

  describe 'sessao com origem verificada' do
    before { definition('cpf', protegida: true) }

    it 'grava ate a chave protegida' do
      resultado = gate(verified: true).filter({ 'cpf' => '000' })

      expect(resultado.allowed).to eq({ 'cpf' => '000' })
      expect(resultado.refused).to eq([])
    end
  end

  describe 'o portao nao morde onde nao deve' do
    it 'nao protege chave de outro modelo de atributo' do
      definition('cpf', protegida: true, model: 'contact_attribute')

      resultado = gate(verified: false).filter({ 'cpf' => '000' })

      expect(resultado.allowed).to eq({ 'cpf' => '000' })
    end

    it 'nao protege chave de outra conta' do
      outra = create(:account)
      create(:custom_attribute_definition, account: outra, attribute_key: 'cpf',
                                           attribute_model: 'conversation_attribute',
                                           attribute_display_type: 'text', requires_verified_origin: true)

      expect(gate(verified: false).filter({ 'cpf' => '000' }).allowed).to eq({ 'cpf' => '000' })
    end

    # `nil` na coluna e "nao exige", que e o comportamento de hoje — regra A4, sem backfill.
    it 'trata definicao anterior a coluna como nao protegida' do
      definition('cpf', protegida: nil)

      expect(gate(verified: false).filter({ 'cpf' => '000' }).allowed).to eq({ 'cpf' => '000' })
    end

    it 'aguenta payload vazio e nulo' do
      expect(gate(verified: false).filter({}).allowed).to eq({})
      expect(gate(verified: false).filter(nil).allowed).to eq({})
    end
  end
end
