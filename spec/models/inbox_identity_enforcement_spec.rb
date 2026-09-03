require 'rails_helper'

# Bloco 4.15 — os tres estados. O que este arquivo protege acima de tudo e a regra de que
# `hmac_mandatory` nao muda de comportamento: a frota tem clientes integrados nele.
RSpec.describe Inbox do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_widget, account: account) }
  let(:inbox) { channel.inbox }

  describe '#resolved_identity_enforcement' do
    it 'e desativado na inbox que nunca abriu a tela' do
      expect(inbox.identity_enforcement).to be_nil
      expect(inbox.resolved_identity_enforcement).to eq('desativado')
    end

    it 'e obrigatorio quando hmac_mandatory esta ligado, sem nada gravado no jsonb' do
      channel.update!(hmac_mandatory: true)

      expect(inbox.reload.identity_enforcement).to be_nil
      expect(inbox.resolved_identity_enforcement).to eq('obrigatorio')
    end

    it 'le observado do jsonb' do
      inbox.update!(identity_enforcement: 'observado')

      expect(inbox.reload.resolved_identity_enforcement).to eq('observado')
    end

    it 'le obrigatorio do jsonb mesmo com hmac_mandatory desligado' do
      inbox.update!(identity_enforcement: 'obrigatorio')

      expect(inbox.reload.resolved_identity_enforcement).to eq('obrigatorio')
    end

    # A regra que protege a frota: o jsonb pode ENDURECER, nunca afrouxar.
    it 'nao deixa o jsonb afrouxar uma inbox que hoje exige assinatura' do
      channel.update!(hmac_mandatory: true)

      inbox.update!(identity_enforcement: 'desativado')
      expect(inbox.reload.resolved_identity_enforcement).to eq('obrigatorio')

      inbox.update!(identity_enforcement: 'observado')
      expect(inbox.reload.resolved_identity_enforcement).to eq('obrigatorio')
    end

    it 'ignora valor desconhecido em vez de operar num estado inexistente' do
      # Grava por baixo da validacao de proposito: e o que uma linha antiga, ou uma
      # escrita direta no banco, deixaria para tras.
      inbox.update_columns(additional_attributes: { 'identity_enforcement' => 'quase_obrigatorio' }) # rubocop:disable Rails/SkipsModelValidations

      expect(inbox.reload.resolved_identity_enforcement).to eq('desativado')
    end
  end

  describe 'validacao do estado' do
    it 'recusa estado que nao existe, com erro legivel' do
      inbox.identity_enforcement = 'meio_obrigatorio'

      expect(inbox).not_to be_valid
      expect(inbox.errors[:identity_enforcement])
        .to eq(['is not a valid identity enforcement state (accepted values: desativado, observado, obrigatorio)'])
    end

    it 'aceita os tres estados' do
      %w[desativado observado obrigatorio].each do |state|
        inbox.identity_enforcement = state
        expect(inbox).to be_valid
      end
    end

    it 'aceita nil, que e a inbox que nunca abriu a tela' do
      inbox.identity_enforcement = nil

      expect(inbox).to be_valid
    end
  end

  describe 'marca de inicio da observacao' do
    it 'nasce quando o estado entra em observado' do
      expect(inbox.identity_enforcement_observed_since).to be_nil

      inbox.update!(identity_enforcement: 'observado')

      expect(inbox.reload.identity_enforcement_observed_since_time).to be_within(30.seconds).of(Time.zone.now)
    end

    it 'nao se move quando a inbox e salva de novo ja em observado' do
      inbox.update!(identity_enforcement: 'observado')
      marca = inbox.reload.identity_enforcement_observed_since

      inbox.update!(name: 'Outro nome')

      expect(inbox.reload.identity_enforcement_observed_since).to eq(marca)
    end

    it 'nao nasce em desativado nem em obrigatorio' do
      inbox.update!(identity_enforcement: 'obrigatorio')

      expect(inbox.reload.identity_enforcement_observed_since).to be_nil
    end
  end

  describe 'consultas de conveniencia' do
    it 'watching? cobre observado e obrigatorio, e so eles' do
      inbox.update!(identity_enforcement: 'desativado')
      expect(inbox.identity_enforcement_watching?).to be(false)

      inbox.update!(identity_enforcement: 'observado')
      expect(inbox.identity_enforcement_watching?).to be(true)

      inbox.update!(identity_enforcement: 'obrigatorio')
      expect(inbox.identity_enforcement_watching?).to be(true)
    end
  end
end
