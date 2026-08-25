require 'rails_helper'

# O que ESTE arquivo protege são as adições ao Motor: o modo fila (pull) e o fato de que, com
# repasse ligado, a designação de modo push passa a NASCER ABERTA — é ela que o SLA mede.
RSpec.describe Spx::Distribuicao::DistribuirService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:team) { create(:team, account: account) }
  let(:corretores) { create_list(:user, 2, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, team: team, status: :open) }
  let(:pool) { corretores.map { |u| { 'user_id' => u.id, 'ativo' => true } } }

  before do
    corretores.each do |user|
      create(:team_member, team: team, user: user)
      create(:inbox_member, inbox: inbox, user: user)
    end
  end

  def ultimo_log
    Spx::Distribuicao::Log.where(conversation_id: conversation.id).order(:id).last
  end

  describe 'modo fila (pull)' do
    before { create(:distribuicao_policy, :fila, account: account, team: team, pool: pool) }

    it 'não escolhe ninguém — a conversa fica sem dono para quem puxar' do
      resultado = described_class.new(conversation).call

      expect(resultado.decidido).to be(false)
      expect(resultado.motivo).to eq('fila')
      expect(conversation.reload.assignee_id).to be_nil
    end

    # A linha aberta é o que dá relógio ao pull: sem ela a espera não tem começo e a fila
    # nunca escalaria.
    it 'abre uma designação sem responsável, para a espera ter começo' do
      described_class.new(conversation).call

      expect(ultimo_log.status).to eq('designado')
      expect(ultimo_log.chosen_user_id).to be_nil
    end

    it 'não deixa duas filas abertas na mesma conversa' do
      described_class.new(conversation).call
      described_class.new(conversation).call

      expect(Spx::Distribuicao::Log.abertas.where(conversation_id: conversation.id).count).to eq(1)
    end
  end

  describe 'modo push' do
    it 'sem repasse, a linha nasce e fecha junto (comportamento de sempre)' do
      create(:distribuicao_policy, account: account, team: team, pool: pool)

      described_class.new(conversation).call

      expect(ultimo_log.status).to eq('assumido')
      expect(ultimo_log.encerrado_em).to be_present
    end

    it 'com repasse, a linha nasce ABERTA — "atribuído e ainda sem primeira resposta"' do
      create(:distribuicao_policy, account: account, team: team, pool: pool)

      described_class.new(conversation).call

      expect(ultimo_log.status).to eq('designado')
      expect(ultimo_log.encerrado_em).to be_nil
      expect(conversation.reload.assignee_id).to be_present
    end
  end

  describe 'reuso pelo repasse' do
    before { create(:distribuicao_policy, account: account, team: team, pool: pool) }

    it 'exclui do pool quem já queimou a vez' do
      resultado = described_class.new(conversation, excluir: [corretores[0].id],
                                                    repasse_n: 1, motivo_forcado: 'repasse_sla').call

      expect(resultado.user_id).to eq(corretores[1].id)
      expect(ultimo_log.repasse_n).to eq(1)
      expect(ultimo_log.motivo).to eq('repasse_sla')
    end

    it 'devolve sem_pool quando todo mundo já queimou a vez' do
      resultado = described_class.new(conversation, excluir: corretores.map(&:id),
                                                    repasse_n: 2, motivo_forcado: 'repasse_sla').call

      expect(resultado.decidido).to be(false)
      expect(resultado.motivo).to eq('sem_pool')
    end
  end

  describe 'modos inertes' do
    it 'off segue no-op' do
      create(:distribuicao_policy, account: account, team: team, modo: 'off', pool: pool)

      expect(described_class.new(conversation).call.decidido).to be(false)
      expect(Spx::Distribuicao::Log.where(conversation_id: conversation.id)).to be_empty
    end
  end
end
