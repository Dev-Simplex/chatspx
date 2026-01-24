require 'rails_helper'

RSpec.describe NpsResponse do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:account_id) }
    it { is_expected.to validate_presence_of(:conversation_id) }
    it { is_expected.to validate_presence_of(:contact_id) }
    it { is_expected.to validate_presence_of(:inbox_id) }
    it { is_expected.to validate_uniqueness_of(:conversation_id) }

    it 'validates that the score can only be in range 0-10' do
      nps_response = build(:nps_response, score: 11)
      expect(nps_response.valid?).to be false
    end

    it 'allows nil score' do
      nps_response = build(:nps_response, score: nil)
      expect(nps_response.valid?).to be true
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:conversation) }
    it { is_expected.to belong_to(:contact) }
    it { is_expected.to belong_to(:inbox) }
    it { is_expected.to belong_to(:assigned_agent).optional }
  end

  describe 'scopes' do
    let(:account) { create(:account) }
    let(:conversation) { create(:conversation, account: account) }
    let(:contact) { conversation.contact }
    let(:inbox) { conversation.inbox }

    before do
      create(:nps_response, account: account, conversation: conversation, contact: contact, inbox: inbox, score: 9, status: :responded)
      create(:nps_response, account: account, conversation: create(:conversation, account: account), contact: contact, inbox: inbox, score: 7, status: :responded)
      create(:nps_response, account: account, conversation: create(:conversation, account: account), contact: contact, inbox: inbox, score: 5, status: :responded)
    end

    it 'filters promoters' do
      expect(described_class.promoters.count).to eq(1)
    end

    it 'filters passives' do
      expect(described_class.passives.count).to eq(1)
    end

    it 'filters detractors' do
      expect(described_class.detractors.count).to eq(1)
    end
  end

  describe 'methods' do
    let(:nps_response) { build(:nps_response) }

    describe '#promoter?' do
      it 'returns true for score 9-10' do
        nps_response.score = 9
        expect(nps_response.promoter?).to be true

        nps_response.score = 10
        expect(nps_response.promoter?).to be true
      end

      it 'returns false for other scores' do
        nps_response.score = 8
        expect(nps_response.promoter?).to be false
      end
    end

    describe '#passive?' do
      it 'returns true for score 7-8' do
        nps_response.score = 7
        expect(nps_response.passive?).to be true

        nps_response.score = 8
        expect(nps_response.passive?).to be true
      end
    end

    describe '#detractor?' do
      it 'returns true for score 0-6' do
        nps_response.score = 0
        expect(nps_response.detractor?).to be true

        nps_response.score = 6
        expect(nps_response.detractor?).to be true
      end
    end

    describe '#classification' do
      it 'returns promoter for score 9-10' do
        nps_response.score = 9
        expect(nps_response.classification).to eq('promoter')
      end

      it 'returns passive for score 7-8' do
        nps_response.score = 7
        expect(nps_response.classification).to eq('passive')
      end

      it 'returns detractor for score 0-6' do
        nps_response.score = 5
        expect(nps_response.classification).to eq('detractor')
      end
    end
  end

  describe 'validates_factory' do
    it 'creates valid nps_response object' do
      nps_response = create(:nps_response)
      expect(nps_response.valid?).to be true
    end
  end
end
