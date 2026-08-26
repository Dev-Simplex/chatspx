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

  # Suspensão com prazo, entregue pelo PR #67 sem teste. É o que separa "de férias, volta dia X"
  # de "desligado do rodízio": antes disso pausar alguém obrigava um humano a lembrar de desfazer
  # depois, e ninguém lembra — por isso pausa e punição tinham virado a mesma coisa.
  describe '#suspenso?' do
    let(:policy) { build(:distribuicao_policy) }

    def entrada(ate) = { 'user_id' => 1, 'ativo' => true, 'suspenso_ate' => ate }

    it 'esta suspenso durante o prazo' do
      expect(policy.suspenso?(entrada(3.days.from_now.to_date.to_s))).to be(true)
    end

    # "suspenso até 30/08" recebe de novo em 31/08, não em 30/08.
    it 'a data e INCLUSIVA: no ultimo dia ainda esta fora' do
      expect(policy.suspenso?(entrada(Time.zone.today.to_s))).to be(true)
    end

    it 'volta sozinho no dia seguinte, sem ninguem precisar lembrar' do
      expect(policy.suspenso?(entrada(1.day.ago.to_date.to_s))).to be(false)
    end

    it 'entrada sem prazo nao esta suspensa' do
      expect(policy.suspenso?({ 'user_id' => 1 })).to be(false)
      expect(policy.suspenso?(entrada(''))).to be(false)
    end

    # Excluir alguém por campo mal digitado é pior que incluir: incluir custa um lead a mais;
    # excluir faz a pessoa sumir da fila sem ninguém entender por quê.
    it 'data ilegivel NAO suspende' do
      ['30/02/2026', 'amanha', '2026-13-45', 42].each do |lixo|
        expect(policy.suspenso?(entrada(lixo))).to be(false)
      end
    end

    it 'a suspensao tira a pessoa do pool elegivel' do
      policy.pool = [entrada(3.days.from_now.to_date.to_s)]

      expect(policy.pool_entries.select { |e| policy.disponivel?(e) }).to be_empty
    end

    # A tela precisa DIZER por que a pessoa está fora, em vez de só omiti-la da lista.
    it 'diz o motivo da indisponibilidade em vez de so omitir' do
      expect(policy.indisponibilidade(entrada(3.days.from_now.to_date.to_s))).to eq(:suspenso)
      expect(policy.indisponibilidade({ 'user_id' => 1, 'ativo' => false })).to eq(:desativado)
      expect(policy.indisponibilidade(entrada(nil).merge('ativo' => true))).to be_nil
    end
  end
end
