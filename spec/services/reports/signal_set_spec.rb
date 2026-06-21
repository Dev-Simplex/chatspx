require 'rails_helper'

RSpec.describe Reports::SignalSet do
  def signal(signals, metric)
    signals.find { |s| s[:metric] == metric.to_s }
  end

  describe '#build with custom benchmarks' do
    let(:benchmarks) do
      {
        csat: { goal: 85, green: 85, yellow: 70, lower_better: false },
        nps: { goal: 50, green: 50, yellow: 0, lower_better: false }
      }
    end

    it 'classifies higher-is-better metrics by their thresholds' do
      signals = described_class.new(
        entries: [{ metric: :csat, value: 90 }, { metric: :nps, value: 10 }],
        benchmarks: benchmarks
      ).build

      expect(signal(signals, :csat)[:level]).to eq('good')  # 90 >= 85
      expect(signal(signals, :nps)[:level]).to eq('warn')   # 0 <= 10 < 50
    end

    it 'classifies a negative NPS as bad' do
      signals = described_class.new(entries: [{ metric: :nps, value: -20 }], benchmarks: benchmarks).build

      expect(signal(signals, :nps)[:level]).to eq('bad')
    end

    it 'keeps the raw value and goal in the output' do
      signals = described_class.new(entries: [{ metric: :csat, value: 73 }], benchmarks: benchmarks).build

      expect(signal(signals, :csat)).to include(value: 73, goal: 85, level: 'warn')
    end

    it 'marks the single signal as highlight and as attention when not good' do
      signals = described_class.new(entries: [{ metric: :csat, value: 60 }], benchmarks: benchmarks).build

      expect(signals.first[:is_highlight]).to be(true)
      expect(signals.first[:is_attention]).to be(true)
    end

    it 'does not mark attention when the only signal is good' do
      signals = described_class.new(entries: [{ metric: :csat, value: 95 }], benchmarks: benchmarks).build

      expect(signals.first[:is_highlight]).to be(true)
      expect(signals.first[:is_attention]).to be(false)
    end

    it 'computes delta_pct against prev and nil when prev missing/zero' do
      with_prev = described_class.new(entries: [{ metric: :csat, value: 90, prev: 75 }], benchmarks: benchmarks).build
      no_prev = described_class.new(entries: [{ metric: :csat, value: 90 }], benchmarks: benchmarks).build
      zero_prev = described_class.new(entries: [{ metric: :csat, value: 90, prev: 0 }], benchmarks: benchmarks).build

      expect(signal(with_prev, :csat)[:delta_pct]).to eq(20) # (90-75)/75*100
      expect(signal(no_prev, :csat)[:delta_pct]).to be_nil
      expect(signal(zero_prev, :csat)[:delta_pct]).to be_nil
    end

    it 'skips entries without a benchmark' do
      signals = described_class.new(entries: [{ metric: :unknown_metric, value: 5 }], benchmarks: benchmarks).build

      expect(signals).to be_empty
    end
  end

  describe '#build with multiple signals (highlight/attention selection)' do
    let(:benchmarks) do
      {
        csat: { goal: 85, green: 85, yellow: 70, lower_better: false },
        first_response: { goal: 300, green: 300, yellow: 900, lower_better: true }
      }
    end

    it 'picks the best as highlight and the worst non-good as attention' do
      signals = described_class.new(
        entries: [{ metric: :csat, value: 95 }, { metric: :first_response, value: 1000 }],
        benchmarks: benchmarks
      ).build

      expect(signal(signals, :csat)[:is_highlight]).to be(true)
      expect(signal(signals, :first_response)[:is_attention]).to be(true)
      expect(signals.count { |s| s[:is_highlight] }).to eq(1)
    end
  end
end
