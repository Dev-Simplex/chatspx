require 'rails_helper'

# "Supervisor" no Console de Super Admin é ADMINISTRADOR + linhas em team_supervisors:
# quase tudo que um admin faz, menos as seis configurações de plataforma. O que este
# spec protege é isso não virar um terceiro papel no banco — `administrator?` precisa
# continuar true, senão as checagens espalhadas pelo código caem.
RSpec.describe AccountUser do
  let!(:account) { create(:account) }
  let!(:team_a) { create(:team, account: account) }
  let!(:team_b) { create(:team, account: account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:account_user) { user.account_users.find_by(account_id: account.id) }

  describe 'console_role' do
    it 'grava administrador no banco quando o console escolhe supervisor' do
      account_user.console_role = 'supervisor'
      account_user.supervised_team_ids = [team_a.id]
      account_user.save!

      expect(account_user.reload.role).to eq('administrator')
      expect(account_user).to be_administrator
    end

    it 'devolve supervisor quando é administrador que supervisiona time' do
      account_user.update!(role: :administrator)
      create(:team_supervisor, team: team_a, user: user)

      expect(account_user.reload.console_role).to eq('supervisor')
    end

    it 'devolve o papel do enum quando não supervisiona nada' do
      expect(account_user.console_role).to eq('agent')
    end

    # O agente que supervisiona é outro perfil e continua existindo — a tela de
    # Agentes do dashboard o chama de Supervisor. Aqui ele aparece como `agent`,
    # com os times no campo ao lado.
    it 'não chama agente que supervisiona de supervisor' do
      create(:team_supervisor, team: team_a, user: user)

      expect(account_user.reload.console_role).to eq('agent')
    end

    it 'oferece os três valores ao console sem mexer no enum' do
      expect(described_class::CONSOLE_ROLES).to eq(%w[agent administrator supervisor])
      expect(described_class.roles.keys).to eq(%w[agent administrator])
    end
  end

  describe 'supervised_team_ids' do
    it 'cria e remove a supervisão conforme o que o formulário mandou' do
      account_user.update!(supervised_team_ids: [team_a.id, team_b.id])
      expect(account_user.reload.supervised_team_ids).to contain_exactly(team_a.id, team_b.id)

      account_user.update!(supervised_team_ids: [team_b.id])
      expect(account_user.reload.supervised_team_ids).to contain_exactly(team_b.id)

      account_user.update!(supervised_team_ids: [])
      expect(account_user.reload.supervised_team_ids).to be_empty
    end

    it 'ignora time de outra conta' do
      outra = create(:team, account: create(:account))
      account_user.update!(supervised_team_ids: [team_a.id, outra.id])

      expect(account_user.reload.supervised_team_ids).to contain_exactly(team_a.id)
    end

    # Sem isto, escolher "supervisor" no formulário da página do usuário — onde a conta
    # só é conhecida no submit e não há lista de times — seria um controle que não faz nada.
    it 'supervisiona todos os times da conta quando o console não pôde escolher' do
      account_user.console_role = 'supervisor'
      account_user.save!

      expect(account_user.reload.supervised_team_ids).to contain_exactly(team_a.id, team_b.id)
    end

    it 'preserva a supervisão que já existia em vez de expandir' do
      account_user.update!(supervised_team_ids: [team_a.id])

      recarregado = described_class.find(account_user.id)
      recarregado.console_role = 'supervisor'
      recarregado.save!

      expect(recarregado.reload.supervised_team_ids).to contain_exactly(team_a.id)
    end

    # Campo AUSENTE ≠ campo VAZIO. Desmarcar tudo no seletor e mesmo assim conceder a
    # conta inteira seria conceder o oposto do que o admin fez na tela.
    it 'recusa supervisor com o seletor de times esvaziado, em vez de conceder tudo' do
      account_user.console_role = 'supervisor'
      account_user.supervised_team_ids = ['']

      expect(account_user.save).to be(false)
      expect(account_user.errors[:supervised_team_ids]).to be_present
      expect(account_user.reload.supervised_team_ids).to be_empty
    end

    it 'deixa esvaziar o seletor quando o papel não é supervisor' do
      account_user.update!(supervised_team_ids: [team_a.id])

      recarregado = described_class.find(account_user.id)
      recarregado.console_role = 'agent'
      recarregado.supervised_team_ids = ['']

      expect(recarregado.save).to be(true)
      expect(recarregado.reload.supervised_team_ids).to be_empty
    end

    it 'não encosta na supervisão num save que não mandou o campo' do
      create(:team_supervisor, team: team_a, user: user)
      account_user.update!(availability: :busy)

      expect(account_user.reload.supervised_team_ids).to contain_exactly(team_a.id)
    end
  end

  # O writer é o ponto único que faz "supervisor" valer em TODA superfície que
  # atribui papel. Antes, qualquer uma levantava ArgumentError e virava 500.
  describe 'role= aceitando supervisor' do
    it 'não levanta ArgumentError' do
      expect { account_user.update!(role: 'supervisor') }.not_to raise_error
    end

    it 'grava administrador e supervisiona os times da conta' do
      account_user.update!(role: 'supervisor')

      expect(account_user.reload.role).to eq('administrator')
      expect(account_user).to be_administrator
      expect(account_user.supervised_team_ids).to contain_exactly(team_a.id, team_b.id)
    end

    it 'respeita os times informados junto' do
      account_user.update!(role: 'supervisor', supervised_team_ids: [team_b.id])

      expect(account_user.reload.supervised_team_ids).to contain_exactly(team_b.id)
    end

    it 'não mexe no comportamento de agent e administrator' do
      account_user.update!(role: 'administrator')
      expect(account_user.reload).to be_administrator
      expect(account_user.supervised_team_ids).to be_empty

      account_user.update!(role: 'agent')
      expect(account_user.reload).to be_agent
    end

    it 'recusa papel inexistente como sempre' do
      expect { account_user.update!(role: 'chefe') }.to raise_error(ArgumentError)
    end
  end

  describe 'permissions' do
    it 'soma team_supervisor ao papel do enum' do
      account_user.update!(supervised_team_ids: [team_a.id])

      expect(account_user.reload.permissions).to contain_exactly('agent', 'team_supervisor')
    end

    it 'soma team_supervisor ao administrador que supervisiona' do
      account_user.update!(console_role: 'supervisor', supervised_team_ids: [team_a.id])

      expect(account_user.reload.permissions).to contain_exactly('administrator', 'team_supervisor')
    end
  end
end
