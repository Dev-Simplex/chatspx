require 'rails_helper'

RSpec.describe NpsResponse do
  let(:account) { create(:account) }

  describe 'band predicates and classification' do
    {
      10 => 'promoter', 9 => 'promoter',
      8 => 'passive', 7 => 'passive',
      6 => 'detractor', 3 => 'detractor', 0 => 'detractor'
    }.each do |score, expected_band|
      it "classifies score #{score} as #{expected_band}" do
        response = build(:nps_response, score: score)
        expect(response.classification).to eq(expected_band)
        expect(response.promoter?).to eq(expected_band == 'promoter')
        expect(response.passive?).to eq(expected_band == 'passive')
        expect(response.detractor?).to eq(expected_band == 'detractor')
      end
    end

    it 'has a nil classification when score is nil' do
      expect(build(:nps_response, score: nil).classification).to be_nil
    end
  end

  describe 'band scopes' do
    let!(:promoter) { create(:nps_response, :promoter, account: account, status: :responded) }
    let!(:passive) { create(:nps_response, :passive, account: account, status: :responded) }
    let!(:detractor) { create(:nps_response, :detractor, account: account, status: :responded) }

    it 'buckets by score range' do
      expect(account.nps_responses.promoters).to contain_exactly(promoter)
      expect(account.nps_responses.passives).to contain_exactly(passive)
      expect(account.nps_responses.detractors).to contain_exactly(detractor)
    end
  end

  describe 'data-quality scopes' do
    let!(:clean) { create(:nps_response, account: account, status: :responded, data_quality_flag: nil) }
    let!(:verified) { create(:nps_response, account: account, status: :responded, data_quality_flag: 'verified') }
    let!(:recovered) { create(:nps_response, account: account, status: :responded, data_quality_flag: 'recovered') }
    let!(:suspicious) { create(:nps_response, account: account, status: :responded, data_quality_flag: 'suspicious') }

    it 'trusted includes nil/verified/recovered and excludes anything else' do
      expect(account.nps_responses.trusted).to contain_exactly(clean, verified, recovered)
    end

    it 'flagged is the complement of trusted' do
      expect(account.nps_responses.flagged).to contain_exactly(suspicious)
    end
  end

  describe '#expired?' do
    it 'is false when not sent' do
      expect(build(:nps_response, status: :responded).expired?).to be(false)
    end

    it 'uses the inbox nps_config expiration window (default 72h)' do
      inbox = create(:inbox, account: account)
      response = create(:nps_response, account: account, inbox: inbox, status: :sent, sent_at: 80.hours.ago)
      expect(response.expired?).to be(true)
    end

    it 'is not expired within the window' do
      inbox = create(:inbox, account: account)
      response = create(:nps_response, account: account, inbox: inbox, status: :sent, sent_at: 1.hour.ago)
      expect(response.expired?).to be(false)
    end
  end
end
