# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TeamSupervisor do
  let!(:account) { create(:account) }
  let!(:team) { create(:team, account: account) }
  let!(:agent) { create(:user, account: account, role: :agent) }

  describe 'associations' do
    it { is_expected.to belong_to(:team) }
    it { is_expected.to belong_to(:user) }
  end

  describe 'validations' do
    it 'is valid for a user of the team account' do
      expect(described_class.new(team: team, user: agent)).to be_valid
    end

    it 'rejects a duplicate supervision for the same team' do
      described_class.create!(team: team, user: agent)

      duplicate = described_class.new(team: team, user: agent)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:user_id]).to be_present
    end

    it 'allows the same user to supervise more than one team' do
      other_team = create(:team, account: account)
      described_class.create!(team: team, user: agent)

      expect(described_class.new(team: other_team, user: agent)).to be_valid
    end

    it 'rejects a user that does not belong to the team account' do
      outsider = create(:user, account: create(:account), role: :agent)

      record = described_class.new(team: team, user: outsider)

      expect(record).not_to be_valid
      expect(record.errors[:user]).to be_present
    end
  end

  describe 'associations on team and user' do
    before { described_class.create!(team: team, user: agent) }

    it 'exposes the supervisors of a team' do
      expect(team.reload.supervisors).to contain_exactly(agent)
    end

    it 'exposes the supervised teams of a user' do
      expect(agent.reload.supervised_teams).to contain_exactly(team)
    end

    # supervisionar não é ser membro (D1): a contagem do time não pode mudar
    it 'does not turn the supervisor into a team member' do
      expect(team.reload.members).to be_empty
      expect(agent.reload.teams).to be_empty
    end
  end

  describe 'database constraints' do
    # apagar o time/usuário nunca pode deixar supervisão órfã. Verificado pela definição
    # da FK e não por um destroy real porque apagar um time neste fork esbarra em outras
    # FKs (funil padrão, canal do chat interno) que nada têm a ver com supervisão.
    it 'cascades the delete of the team and of the user' do
      foreign_keys = ActiveRecord::Base.connection.foreign_keys(:team_supervisors)

      expect(foreign_keys.map { |fk| [fk.to_table, fk.on_delete] }).to contain_exactly(%w[teams].push(:cascade), %w[users].push(:cascade))
    end
  end
end
