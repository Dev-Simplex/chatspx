require 'rails_helper'

RSpec.describe Label do
  after do
    Current.user = nil
    Current.account = nil
  end

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:created_by).class_name('User').optional }
    it { is_expected.to belong_to(:team).optional }
  end

  describe 'enum visibility' do
    it 'defines the three visibility levels with a prefix' do
      expect(described_class.visibilities).to eq('everyone' => 0, 'personal' => 1, 'team' => 2)
    end

    it 'defaults to everyone' do
      label = described_class.new
      expect(label.visibility).to eq('everyone')
      expect(label.visibility_everyone?).to be(true)
    end
  end

  describe 'team_id validations' do
    let(:account) { create(:account) }
    let(:team) { create(:team, account: account) }

    it 'requires team_id when visibility is team' do
      label = build(:label, account: account, visibility: :team, team: nil)
      expect(label).not_to be_valid
      expect(label.errors[:team_id]).to be_present
    end

    it 'is valid when visibility is team with a team of the same account' do
      label = build(:label, account: account, visibility: :team, team: team)
      expect(label).to be_valid
    end

    it 'rejects a team from a different account' do
      other_team = create(:team, account: create(:account))
      label = build(:label, account: account, visibility: :team, team: other_team)
      expect(label).not_to be_valid
      expect(label.errors[:team]).to include('must belong to the same account')
    end

    it 'forbids team_id when visibility is not team' do
      label = build(:label, account: account, visibility: :everyone, team: team)
      expect(label).not_to be_valid
      expect(label.errors[:team_id]).to be_present
    end
  end

  describe '.with_visibility' do
    let(:account) { create(:account) }
    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:agent_1) { create(:user, account: account, role: :agent) }
    let(:agent_2) { create(:user, account: account, role: :agent) }
    let(:team_1) { create(:team, account: account) }
    let(:team_2) { create(:team, account: account) }

    let!(:public_label) { create(:label, account: account, visibility: :everyone, created_by: admin) }
    let!(:admin_private) { create(:label, account: account, visibility: :personal, created_by: admin) }
    let!(:agent_1_private) { create(:label, account: account, visibility: :personal, created_by: agent_1) }
    let!(:agent_2_private) { create(:label, account: account, visibility: :personal, created_by: agent_2) }
    let!(:team_1_label) { create(:label, account: account, visibility: :team, team: team_1, created_by: admin) }
    let!(:team_2_label) { create(:label, account: account, visibility: :team, team: team_2, created_by: admin) }

    before do
      create(:team_member, user: agent_1, team: team_1)
      Current.account = account
    end

    context 'when user is administrator' do
      it 'returns all labels in the account' do
        expect(described_class.with_visibility(admin)).to match_array(account.labels)
      end
    end

    context 'when user is an agent' do
      it 'returns public labels, own private and team labels of their teams' do
        result = described_class.with_visibility(agent_1)
        expect(result).to include(public_label, agent_1_private, team_1_label)
      end

      it 'does not return other agents private labels' do
        result = described_class.with_visibility(agent_1)
        expect(result).not_to include(agent_2_private, admin_private)
      end

      it 'does not return team labels of teams the agent is not a member of' do
        result = described_class.with_visibility(agent_1)
        expect(result).not_to include(team_2_label)
      end
    end
  end

  describe 'team destroy cleanup' do
    let(:account) { create(:account) }
    let(:team) { create(:team, account: account) }

    it 'rebases team labels to everyone before the team is destroyed' do
      label = create(:label, account: account, visibility: :team, team: team)

      # Exercise the before_destroy callback directly: a full team.destroy! is blocked in
      # this fork by an unrelated funnels.team_id FK (Team creates a default funnel on create).
      team.send(:rebase_team_labels)

      label.reload
      expect(label.visibility).to eq('everyone')
      expect(label.team_id).to be_nil
    end
  end

  describe 'title validations' do
    it 'would not let you start title without numbers or letters' do
      label = FactoryBot.build(:label, title: '_12')
      expect(label.valid?).to be false
    end

    it 'would not let you use special characters' do
      label = FactoryBot.build(:label, title: 'jell;;2_12')
      expect(label.valid?).to be false
    end

    it 'would not allow space' do
      label = FactoryBot.build(:label, title: 'heeloo _12')
      expect(label.valid?).to be false
    end

    it 'allows foreign charactes' do
      label = FactoryBot.build(:label, title: '学中文_12')
      expect(label.valid?).to be true
    end

    it 'allows dots, hyphens and underscores' do
      label = FactoryBot.build(:label, title: 'v1.2.3-beta_final')
      expect(label.valid?).to be true
    end

    it 'would not let you start title with a dot' do
      label = FactoryBot.build(:label, title: '.hidden')
      expect(label.valid?).to be false
    end

    it 'converts uppercase letters to lowercase' do
      label = FactoryBot.build(:label, title: 'Hello_World')
      expect(label.valid?).to be true
      expect(label.title).to eq 'hello_world'
    end

    it 'validates uniqueness of label name for account' do
      account = create(:account)
      label = FactoryBot.create(:label, account: account)
      duplicate_label = FactoryBot.build(:label, title: label.title, account: account)
      expect(duplicate_label.valid?).to be false
    end
  end

  describe '.after_update_commit' do
    let(:label) { create(:label) }

    it 'calls update job' do
      expect(Labels::UpdateJob).to receive(:perform_later).with('new-title', label.title, label.account_id)

      label.update(title: 'new-title')
    end

    it 'does not call update job if title is not updated' do
      expect(Labels::UpdateJob).not_to receive(:perform_later)

      label.update(description: 'new-description')
    end
  end
end
