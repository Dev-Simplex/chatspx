require 'rails_helper'

RSpec.describe Reports::MetricSignalsBuilder do
  # Helper p/ achar o sinal de uma métrica no array de saída.
  def signal(signals, metric)
    signals.find { |s| s[:metric] == metric.to_s }
  end

  describe '#build levels per metric' do
    it 'classifies a "good" value on each metric (at/under the green threshold)' do
      summary = {
        avg_first_response_time: 300,   # <= 300 -> good
        avg_resolution_time: 14_400,    # <= 14_400 -> good
        reply_time: 600,                # <= 600 -> good
        resolutions_count: 80, conversations_count: 100 # 80% -> good
      }

      signals = described_class.new(summary: summary).build

      expect(signal(signals, :first_response)[:level]).to eq('good')
      expect(signal(signals, :resolution)[:level]).to eq('good')
      expect(signal(signals, :reply)[:level]).to eq('good')
      expect(signal(signals, :resolution_rate)[:level]).to eq('good')
    end

    it 'classifies a "warn" value on each metric (within the yellow band)' do
      summary = {
        avg_first_response_time: 900,   # <= 900 -> warn
        avg_resolution_time: 86_400,    # <= 86_400 -> warn
        reply_time: 1800,               # <= 1800 -> warn
        resolutions_count: 60, conversations_count: 100 # 60% -> warn
      }

      signals = described_class.new(summary: summary).build

      expect(signal(signals, :first_response)[:level]).to eq('warn')
      expect(signal(signals, :resolution)[:level]).to eq('warn')
      expect(signal(signals, :reply)[:level]).to eq('warn')
      expect(signal(signals, :resolution_rate)[:level]).to eq('warn')
    end

    it 'classifies a "bad" value on each metric (beyond the yellow threshold)' do
      summary = {
        avg_first_response_time: 901,   # > 900 -> bad
        avg_resolution_time: 86_401,    # > 86_400 -> bad
        reply_time: 1801,               # > 1800 -> bad
        resolutions_count: 59, conversations_count: 100 # 59% -> bad
      }

      signals = described_class.new(summary: summary).build

      expect(signal(signals, :first_response)[:level]).to eq('bad')
      expect(signal(signals, :resolution)[:level]).to eq('bad')
      expect(signal(signals, :reply)[:level]).to eq('bad')
      expect(signal(signals, :resolution_rate)[:level]).to eq('bad')
    end
  end

  describe '#build resolution_rate computation' do
    it 'computes the rate as resolutions_count / conversations_count * 100' do
      summary = { resolutions_count: 90, conversations_count: 120 }

      rate = signal(described_class.new(summary: summary).build, :resolution_rate)

      expect(rate[:value]).to eq(75) # 90/120 -> 75%
    end

    it 'protects against division by zero when conversations_count is 0' do
      summary = { resolutions_count: 10, conversations_count: 0 }

      rate = signal(described_class.new(summary: summary).build, :resolution_rate)

      expect(rate[:value]).to eq(0)
      expect(rate[:level]).to eq('bad')
    end
  end

  describe '#build delta_pct' do
    it 'computes the rounded percent variation against previous' do
      summary = { avg_first_response_time: 450 }
      previous = { avg_first_response_time: 600 }

      sig = signal(described_class.new(summary: summary, previous: previous).build, :first_response)

      expect(sig[:delta_pct]).to eq(-25) # (450-600)/600*100
    end

    it 'is nil when previous is absent' do
      sig = signal(described_class.new(summary: { avg_first_response_time: 450 }).build, :first_response)

      expect(sig[:delta_pct]).to be_nil
    end

    it 'is nil when the previous value is zero (no div/0)' do
      summary = { avg_first_response_time: 450 }
      previous = { avg_first_response_time: 0 }

      sig = signal(described_class.new(summary: summary, previous: previous).build, :first_response)

      expect(sig[:delta_pct]).to be_nil
    end
  end

  describe '#build highlight and attention' do
    it 'marks exactly one highlight' do
      summary = {
        avg_first_response_time: 300, avg_resolution_time: 86_401,
        reply_time: 1800, resolutions_count: 70, conversations_count: 100
      }

      signals = described_class.new(summary: summary).build

      expect(signals.count { |s| s[:is_highlight] }).to eq(1)
    end

    it 'marks the worst non-good signal as attention' do
      summary = {
        avg_first_response_time: 300, avg_resolution_time: 86_401, # bad
        reply_time: 600, resolutions_count: 80, conversations_count: 100
      }

      signals = described_class.new(summary: summary).build

      attention = signals.select { |s| s[:is_attention] }
      expect(attention.map { |s| s[:metric] }).to eq(['resolution'])
    end

    it 'marks no attention when every signal is good' do
      summary = {
        avg_first_response_time: 100, avg_resolution_time: 1000,
        reply_time: 100, resolutions_count: 95, conversations_count: 100
      }

      signals = described_class.new(summary: summary).build

      expect(signals.any? { |s| s[:is_attention] }).to be(false)
      expect(signals.count { |s| s[:is_highlight] }).to eq(1)
    end
  end

  describe '#build with custom benchmarks (configurable goals)' do
    it 'changes the levels when stricter benchmarks are passed' do
      summary = { avg_first_response_time: 300, avg_resolution_time: 14_400, reply_time: 600,
                  resolutions_count: 80, conversations_count: 100 }

      stricter = Reports::PdfBenchmarks::BENCHMARKS.merge(
        first_response: { goal: 100, green: 100, yellow: 200, lower_better: true }
      )

      default_sig = signal(described_class.new(summary: summary).build, :first_response)
      custom_sig = signal(described_class.new(summary: summary, benchmarks: stricter).build, :first_response)

      expect(default_sig[:level]).to eq('good')
      expect(custom_sig[:level]).to eq('bad') # 300 > 200 com a meta mais rígida
      expect(custom_sig[:goal]).to eq(100)
    end
  end

  describe '#build graceful degradation' do
    it 'does not raise on an empty summary and returns coherent zero-value signals' do
      signals = described_class.new(summary: {}).build

      expect(signals.size).to eq(4)
      # tempos = 0 -> good; taxa = 0 -> bad
      expect(signal(signals, :first_response)[:level]).to eq('good')
      expect(signal(signals, :resolution_rate)[:level]).to eq('bad')
    end

    it 'accepts string-keyed hashes (indifferent access)' do
      summary = { 'avg_first_response_time' => 450 }

      sig = signal(described_class.new(summary: summary).build, :first_response)

      expect(sig[:value]).to eq(450.0)
    end
  end
end
