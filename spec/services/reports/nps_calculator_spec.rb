require 'rails_helper'

RSpec.describe Reports::NpsCalculator do
  describe '.score' do
    it 'is %promoters - %detractors rounded to a single integer' do
      expect(described_class.score(promoters: 8, detractors: 2, total: 10)).to eq(60)
    end

    it 'rounds in one step (no double-rounding drift)' do
      # (1 - 2) / 3 * 100 = -33.33… => -33  (não -33.34 do arredondamento duplo)
      expect(described_class.score(promoters: 1, detractors: 2, total: 3)).to eq(-33)
    end

    it 'returns 0 for an empty base' do
      expect(described_class.score(promoters: 0, detractors: 0, total: 0)).to eq(0)
    end

    it 'reaches the -100..+100 extremes' do
      expect(described_class.score(promoters: 5, detractors: 0, total: 5)).to eq(100)
      expect(described_class.score(promoters: 0, detractors: 5, total: 5)).to eq(-100)
    end
  end

  describe '.score_from_counts' do
    it 'buckets scores into promoter (9-10), passive (7-8) and detractor (0-6)' do
      counts = { 10 => 3, 9 => 1, 8 => 1, 7 => 1, 6 => 1, 0 => 1 }
      # promotores 9-10 => 4, detratores 0-6 => 2, total 8 => (4-2)/8*100 = 25
      expect(described_class.score_from_counts(counts)).to eq(25)
    end

    it 'is 0 with no responses' do
      expect(described_class.score_from_counts({})).to eq(0)
    end
  end

  describe 'instance metrics' do
    subject(:calc) do
      described_class.new(responded_scope: responded_scope, sent_count: 80, previous_score: 42)
    end

    let(:account) { create(:account) }

    def responded_scope
      account.nps_responses.where(status: :responded).where.not(score: nil).trusted
    end

    before do
      # 30 promotores (score 10) + 10 detratores (score 3) => NPS 50, reliable (N=40)
      create_list(:nps_response, 30, :promoter, account: account, status: :responded)
      create_list(:nps_response, 10, :detractor, account: account, status: :responded)
    end

    it 'computes the integer NPS from the grouped scores' do
      expect(calc.score).to eq(50)
      expect(calc.total).to eq(40)
      expect(calc.promoters).to eq(30)
      expect(calc.detractors).to eq(10)
    end

    it 'computes response_rate over the same cohort denominator' do
      # 40 respondidas / 80 enviadas => 50.0
      expect(calc.response_rate).to eq(50.0)
    end

    it 'clamps response_rate at 100 when responded exceeds sent_count' do
      small = described_class.new(responded_scope: responded_scope, sent_count: 10)
      expect(small.response_rate).to eq(100.0)
    end

    it 'exposes the point delta vs the previous period' do
      expect(calc.delta).to eq(8) # 50 - 42
    end

    it 'has a nil delta when there is no previous score' do
      no_prev = described_class.new(responded_scope: responded_scope, sent_count: 80)
      expect(no_prev.delta).to be_nil
    end

    it 'is reliable at or above MIN_SAMPLE' do
      expect(calc.reliable?).to be(true)
    end

    it 'to_h carries the full contract consumed by the API and PDF' do
      expect(calc.to_h).to include(
        nps_score: 50, total_count: 40, sent_count: 80,
        promoters_count: 30, detractors_count: 10,
        response_rate: 50.0, reliable: true,
        min_sample: described_class::MIN_SAMPLE,
        previous_nps_score: 42, nps_delta: 8
      )
    end
  end

  describe 'sample-size guard' do
    let(:account) { create(:account) }

    it 'is not reliable below MIN_SAMPLE' do
      create_list(:nps_response, 5, :promoter, account: account, status: :responded)
      scope = account.nps_responses.where(status: :responded).where.not(score: nil).trusted
      calc = described_class.new(responded_scope: scope, sent_count: 5)
      expect(calc.total).to eq(5)
      expect(calc.reliable?).to be(false)
    end
  end
end
