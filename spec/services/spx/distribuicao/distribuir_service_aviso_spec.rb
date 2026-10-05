require 'rails_helper'

# Em modo_posse=designacao ninguém vira `assignee` (a IA segue atendendo), então o aviso nativo
# de atribuição nunca disparava e a pessoa escolhida pelo rodízio não ficava sabendo do lead.
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

  def avisos
    Notification.where(primary_actor: conversation, notification_type: 'conversation_assignment')
  end

  describe 'modo designacao' do
    before { create(:distribuicao_policy, :designacao, account: account, team: team, pool: pool) }

    it 'avisa a pessoa escolhida sem gravar assignee' do
      resultado = described_class.new(conversation).call

      expect(conversation.reload.assignee_id).to be_nil
      expect(avisos.pluck(:user_id)).to eq([resultado.user_id])
    end

    it 'avisa a nova pessoa no repasse por SLA' do
      primeiro = described_class.new(conversation).call

      repasse = described_class.new(conversation, excluir: [primeiro.user_id],
                                                  repasse_n: 1, motivo_forcado: 'repasse_sla').call

      expect(repasse.user_id).not_to eq(primeiro.user_id)
      expect(avisos.where(user_id: repasse.user_id)).to exist
    end

    it 'mantém a designação quando o aviso falha' do
      allow(NotificationBuilder).to receive(:new).and_raise(StandardError, 'fora do ar')

      resultado = described_class.new(conversation).call

      expect(resultado.decidido).to be(true)
      expect(Spx::Distribuicao::Log.designacao_aberta(conversation.id)&.chosen_user_id).to eq(resultado.user_id)
    end
  end

  describe 'modo assignee' do
    before { create(:distribuicao_policy, account: account, team: team, pool: pool) }

    # Quem avisa aqui é o caminho nativo (assignee_changed -> NotificationListener). O Motor não
    # pode somar um segundo aviso ao dele.
    it 'deixa o aviso só para o caminho nativo da atribuição' do
      resultado = described_class.new(conversation).call

      expect(conversation.reload.assignee_id).to eq(resultado.user_id)
      expect(avisos).to be_empty
    end
  end

  describe 'modo fila' do
    before { create(:distribuicao_policy, :fila, account: account, team: team, pool: pool) }

    it 'não avisa ninguém, porque ninguém foi escolhido' do
      described_class.new(conversation).call

      expect(Notification.where(primary_actor: conversation)).to be_empty
    end
  end
end
