require 'rails_helper'

# Esta lista é de onde o modelo tira o id que passa pro `assign_conversation` — enumerar e
# atribuir são o mesmo par que o handoff da IA já tem, então segue a mesma allowlist.
RSpec.describe Captain::Tools::Copilot::GetTeamInfoService do
  let(:account) { create(:account) }
  let(:user) { create(:user, :administrator, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:service) { described_class.new(assistant, user: user) }

  describe '#execute' do
    context 'when the account has no team' do
      it 'says so' do
        expect(service.execute).to eq('No teams found')
      end
    end

    # Nomes explícitos: a factory numera ("Team 9"/"Team 10") e um nome vira substring do
    # outro, o que faria o `not_to include` passar/falhar por acidente.
    context 'with an allowlist configured' do
      let!(:allowed_team) { create(:team, account: account, name: 'Vendas') }
      let!(:blocked_team) { create(:team, account: account, name: 'Cobranca') }

      before { account.update!(custom_attributes: { 'handoff_allowed_team_ids' => [allowed_team.id] }) }

      it 'does not offer the team that is outside the allowlist' do
        result = service.execute

        expect(result).to include(allowed_team.name)
        expect(result).not_to include(blocked_team.name)
      end

      # Filtrar em silêncio faria o operador julgar carga de trabalho com o quadro pela metade.
      it 'declares how many teams were omitted' do
        expect(service.execute).to include('(1 outside the routing allowlist, not listed)')
      end
    end

    # Conta que nunca configurou a allowlist não muda de comportamento.
    context 'without an allowlist configured' do
      let!(:team_a) { create(:team, account: account, name: 'Vendas') }
      let!(:team_b) { create(:team, account: account, name: 'Cobranca') }

      it 'lists every team of the account' do
        result = service.execute

        expect(result).to include(team_a.name, team_b.name)
      end

      it 'does not mention omissions' do
        expect(service.execute).not_to include('not listed')
      end
    end

    context 'when another account has teams' do
      let!(:team) { create(:team, account: account, name: 'Vendas') }
      let!(:foreign_team) { create(:team, account: create(:account), name: 'Suporte de outra conta') }

      it 'never leaks them' do
        expect(service.execute).to include(team.name)
        expect(service.execute).not_to include(foreign_team.name)
      end
    end
  end

  describe '#active?' do
    it 'is true for an administrator' do
      expect(service.active?).to be true
    end

    it 'is false for a custom role without team_manage' do
      custom_role = create(:custom_role, account: account, permissions: [])
      AccountUser.find_by(user: user, account: account).update(role: :agent, custom_role: custom_role)

      expect(service.active?).to be false
    end
  end
end
