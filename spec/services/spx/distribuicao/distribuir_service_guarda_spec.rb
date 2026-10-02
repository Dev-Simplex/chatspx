require 'rails_helper'

# Os dois jeitos de o Motor tirar um lead de quem já estava com ele, medidos na Catatau em
# 15/09/2026: o cliente voltando ao menu chamava o Motor de novo (cinco vendedores queimados em
# cinco minutos) e o lead que alguém já atendia ia parar com outro, porque em vendas se responde
# SEM assumir a conversa e o Motor só enxergava `assignee`.
RSpec.describe Spx::Distribuicao::DistribuirService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:team) { create(:team, account: account) }
  let(:corretores) { create_list(:user, 3, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, team: team, status: :open) }
  let(:pool) { corretores.map { |u| { 'user_id' => u.id, 'ativo' => true } } }

  before do
    corretores.each do |user|
      create(:team_member, team: team, user: user)
      create(:inbox_member, inbox: inbox, user: user)
    end
    create(:distribuicao_policy, account: account, team: team, pool: pool)
  end

  def responder(user)
    create(:message, conversation: conversation, account: account, inbox: inbox,
                     message_type: :outgoing, sender: user, content: 'Boa tarde')
  end

  describe 'lead que já tem designação viva' do
    it 'não é redistribuído quando o Motor é chamado de novo' do
      primeiro = described_class.new(conversation).call

      segundo = described_class.new(conversation).call

      expect(segundo.decidido).to be(false)
      expect(segundo.motivo).to be_in(%w[ja_designada ja_tem_dono])
      expect(conversation.reload.assignee_id).to eq(primeiro.user_id)
    end

    # Escolher outro departamento é motivo legítimo para trocar de dono.
    it 'é redistribuído quando a conversa muda para um time onde o dono não está' do
      described_class.new(conversation).call
      outro_time = create(:team, account: account)
      novo = create(:user, account: account, role: :agent)
      create(:team_member, team: outro_time, user: novo)
      create(:inbox_member, inbox: inbox, user: novo)
      create(:distribuicao_policy, account: account, team: outro_time, pool: [{ 'user_id' => novo.id, 'ativo' => true }])
      conversation.update!(team: outro_time)

      resultado = described_class.new(conversation.reload).call

      expect(resultado.decidido).to be(true)
      expect(resultado.user_id).to eq(novo.id)
    end
  end

  describe 'lead que alguém já está atendendo' do
    # O caso da conversa 194: o Adrian atendia desde as 16h56 sem ter assumido, e o lead foi para
    # o Uilian.
    it 'fica com quem já respondeu ao cliente, mesmo sem a conversa estar atribuída' do
      atendente = corretores.last
      responder(atendente)

      resultado = described_class.new(conversation).call

      expect(resultado.user_id).to eq(atendente.id)
      expect(resultado.motivo).to eq('ja_atendida')
      expect(conversation.reload.assignee_id).to eq(atendente.id)
    end

    # Retorno de cliente não é lead novo: quem fica com ele não pode gastar a vez de ninguém.
    it 'não gasta a vez do rodízio' do
      responder(corretores.last)

      described_class.new(conversation).call

      expect(Spx::Distribuicao::State.find_by(team_id: team.id)&.last_user_id).to be_nil
    end

    it 'ignora resposta de quem não está no pool do time' do
      forasteiro = create(:user, account: account, role: :agent)
      responder(forasteiro)

      resultado = described_class.new(conversation).call

      expect(resultado.motivo).to eq('rodizio')
      expect(corretores.map(&:id)).to include(resultado.user_id)
    end

    # Nota interna não é atendimento: o cliente não viu nada.
    it 'ignora nota privada' do
      create(:message, conversation: conversation, account: account, inbox: inbox,
                       message_type: :outgoing, private: true, sender: corretores.last, content: 'nota')

      resultado = described_class.new(conversation).call

      expect(resultado.motivo).to eq('rodizio')
    end
  end

  # O repasse por SLA existe justamente para tirar o lead de quem não encostou nele: os guards
  # daqui não podem valer ali, senão o lead nunca andaria.
  describe 'repasse por SLA' do
    it 'passa por cima dos guards' do
      atendente = corretores.last
      responder(atendente)
      described_class.new(conversation).call

      resultado = described_class.new(conversation, excluir: [atendente.id], repasse_n: 1, motivo_forcado: 'repasse_sla').call

      expect(resultado.decidido).to be(true)
      expect(resultado.user_id).not_to eq(atendente.id)
    end
  end
end
