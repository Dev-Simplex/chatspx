require 'rails_helper'

RSpec.describe CannedResponse do
  before do
    Current.user = nil
    Current.account = nil
  end

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:created_by).class_name('User').optional }
    it { is_expected.to belong_to(:team).optional }
  end

  describe 'enum visibility' do
    it 'maps everyone/personal/team with the _prefix' do
      expect(described_class.visibilities).to eq('everyone' => 0, 'personal' => 1, 'team' => 2)
    end

    it 'defaults to everyone' do
      expect(described_class.new.visibility).to eq('everyone')
    end
  end

  describe 'team_id validations' do
    let(:account) { create(:account) }
    let(:team) { create(:team, account: account) }

    it 'requires team_id when visibility is team' do
      canned = build(:canned_response, account: account, visibility: :team, team: nil)
      expect(canned).not_to be_valid
      expect(canned.errors[:team_id]).to be_present
    end

    it 'is valid when visibility is team with a team of the same account' do
      canned = build(:canned_response, account: account, visibility: :team, team: team)
      expect(canned).to be_valid
    end

    it 'rejects a team from a different account' do
      other_team = create(:team, account: create(:account))
      canned = build(:canned_response, account: account, visibility: :team, team: other_team)
      expect(canned).not_to be_valid
      expect(canned.errors[:team]).to include('must belong to the same account')
    end

    it 'forbids team_id when visibility is not team' do
      canned = build(:canned_response, account: account, visibility: :everyone, team: team)
      expect(canned).not_to be_valid
      expect(canned.errors[:team_id]).to be_present
    end
  end

  describe '.with_visibility' do
    let(:account) { create(:account) }
    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:agent_1) { create(:user, account: account, role: :agent) }
    let(:agent_2) { create(:user, account: account, role: :agent) }
    let(:team_1) { create(:team, account: account) }
    let(:team_2) { create(:team, account: account) }

    let!(:public_cr) { create(:canned_response, account: account, visibility: :everyone, created_by: admin) }
    let!(:admin_private) { create(:canned_response, account: account, visibility: :personal, created_by: admin) }
    let!(:agent_1_private) { create(:canned_response, account: account, visibility: :personal, created_by: agent_1) }
    let!(:agent_2_private) { create(:canned_response, account: account, visibility: :personal, created_by: agent_2) }
    let!(:team_1_cr) { create(:canned_response, account: account, visibility: :team, team: team_1, created_by: admin) }
    let!(:team_2_cr) { create(:canned_response, account: account, visibility: :team, team: team_2, created_by: admin) }

    before do
      create(:team_member, user: agent_1, team: team_1)
      Current.account = account
    end

    after { Current.account = nil }

    context 'when user is administrator' do
      it 'returns every canned response of the account' do
        expect(described_class.with_visibility(admin)).to match_array(account.canned_responses)
      end
    end

    context 'when user is an agent' do
      it 'returns public, own private and team responses of their teams' do
        result = described_class.with_visibility(agent_1)
        expect(result).to include(public_cr, agent_1_private, team_1_cr)
      end

      it 'does not return private of others nor teams they do not belong to' do
        result = described_class.with_visibility(agent_1)
        expect(result).not_to include(agent_2_private, admin_private, team_2_cr)
      end

      it 'composes with a search-filtered base relation' do
        base = account.canned_responses.where(id: [public_cr.id, agent_2_private.id])
        result = described_class.with_visibility(agent_1, base)
        expect(result).to include(public_cr)
        expect(result).not_to include(agent_2_private, agent_1_private)
      end
    end
  end

  describe 'team destroy cleanup' do
    let(:account) { create(:account) }
    let(:team) { create(:team, account: account) }

    it 'rebases team canned responses to everyone before the team is destroyed' do
      canned = create(:canned_response, account: account, visibility: :team, team: team)

      # Exercise the before_destroy callback directly: a full team.destroy! is blocked in
      # this fork by an unrelated funnels.team_id FK (Team creates a default funnel on create).
      team.send(:rebase_team_canned_responses)

      canned.reload
      expect(canned.visibility).to eq('everyone')
      expect(canned.team_id).to be_nil
    end
  end
end
