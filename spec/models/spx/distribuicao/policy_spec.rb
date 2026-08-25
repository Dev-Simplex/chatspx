require 'rails_helper'

RSpec.describe Spx::Distribuicao::Policy do
  subject(:policy) { build(:distribuicao_policy, account: account, team: team) }

  let(:account) { create(:account) }
  let(:team) { create(:team, account: account) }

  describe 'defaults' do
    # Não há interruptor: política ativa que distribui já repassa. O que existe é EXCLUSÃO por
    # motivo (espelho no Vista), não toggle.
    it 'repassa por padrão' do
      policy.save!
      expect(policy.repassa?).to be(true)
      expect(policy.max_repasses).to eq(2)
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
      policy.update!(ativo: false)
      expect(policy.repassa?).to be(false)
    end

    # A única exclusão, e é por MOTIVO: o card do lead já existe no Vista no nome do corretor
    # e o DELETE de lá responde 401 — não há como desfazer um repasse errado.
    it 'não repassa em time com espelho no Vista' do
      policy.update!(espelho_vista: true)
      expect(policy.repassa?).to be(false)
    end

    it 'não repassa em modo inerte' do
      policy.update!(modo: 'off')
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
