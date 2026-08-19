require 'rails_helper'

RSpec.describe Spx::Distribuicao::Policy do
  subject(:policy) { build(:distribuicao_policy, account: account, team: team) }

  let(:account) { create(:account) }
  let(:team) { create(:team, account: account) }

  describe 'defaults' do
    # O contrato mais importante do pacote: quem já roda hoje não muda de comportamento ao
    # subir esta versão. O repasse e o gatilho novo nascem DESLIGADOS.
    it 'nasce sem repasse automático e sem gatilho sem IA' do
      policy.save!
      expect(policy.repasse_automatico).to be(false)
      expect(policy.gatilho_sem_ia).to be(false)
      expect(policy.repassa?).to be(false)
    end
  end

  describe 'validações' do
    it { expect(build(:distribuicao_policy, account: account, team: team, modo: 'fila')).to be_valid }
    it { expect(build(:distribuicao_policy, account: account, team: team, modo: 'inexistente')).not_to be_valid }
    it { expect(build(:distribuicao_policy, account: account, team: team, sla_assumir_minutos: 0)).not_to be_valid }
    it { expect(build(:distribuicao_policy, account: account, team: team, max_repasses: -1)).not_to be_valid }
  end

  describe '#distribui?' do
    it 'age em rodizio e fila' do
      expect(build(:distribuicao_policy, modo: 'rodizio').distribui?).to be(true)
      expect(build(:distribuicao_policy, modo: 'fila').distribui?).to be(true)
    end

    it 'é inerte em online e off' do
      expect(build(:distribuicao_policy, modo: 'online').distribui?).to be(false)
      expect(build(:distribuicao_policy, modo: 'off').distribui?).to be(false)
    end
  end

  describe '#repassa?' do
    it 'exige a política ativa — desativar o time desliga o repasse junto' do
      policy.update!(repasse_automatico: true, ativo: false)
      expect(policy.repassa?).to be(false)
    end
  end

  describe '#esgotou_repasses?' do
    it 'zero significa sem teto' do
      policy.max_repasses = 0
      expect(policy.esgotou_repasses?(99)).to be(false)
    end

    it 'estoura ao atingir o teto' do
      policy.max_repasses = 2
      expect(policy.esgotou_repasses?(1)).to be(false)
      expect(policy.esgotou_repasses?(2)).to be(true)
    end
  end
end
