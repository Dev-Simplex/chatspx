require 'rails_helper'

RSpec.describe V2::Reports::Conversations::MetricBuilder, type: :model do
  subject { described_class.new(account, params) }

  let(:account) { create(:account) }
  # `type` e obrigatorio: `#summary` passou a calcular percentis, e `percentile_for` desce ate
  # `scope`, que faz `params[:type].to_sym`. Sem a chave, `summary` levanta NoMethodError —
  # o controller sempre manda `type`, era o spec que montava um params que producao nao usa.
  let(:params) { { since: '2023-01-01', until: '2024-01-01', type: 'account' } }
  let(:count_builder_instance) { instance_double(V2::Reports::Timeseries::CountReportBuilder, aggregate_value: 42) }
  let(:avg_builder_instance) { instance_double(V2::Reports::Timeseries::AverageReportBuilder, aggregate_value: 42) }

  before do
    allow(V2::Reports::Timeseries::CountReportBuilder).to receive(:new).and_return(count_builder_instance)
    allow(V2::Reports::Timeseries::AverageReportBuilder).to receive(:new).and_return(avg_builder_instance)
  end

  describe '#summary' do
    it 'returns the correct summary values' do
      summary = subject.summary
      expect(summary).to eq(
        {
          conversations_count: 42,
          incoming_messages_count: 42,
          outgoing_messages_count: 42,
          avg_first_response_time: 42,
          avg_first_response_time_after_assignment: 42,
          avg_resolution_time: 42,
          resolutions_count: 42,
          reply_time: 42,
          # percentis e contagens vao ao banco de verdade (nao passam pelos builders dublados);
          # conta recem-criada nao tem reporting_events, entao ambos saem zerados.
          p50_first_response_time: 0,
          p90_first_response_time: 0,
          p50_first_response_time_after_assignment: 0,
          p90_first_response_time_after_assignment: 0,
          first_response_count: 0,
          first_response_after_assignment_count: 0
        }
      )
    end

    it 'creates builders with proper params' do
      subject.summary
      expect(V2::Reports::Timeseries::CountReportBuilder).to have_received(:new).with(account, params.merge(metric: 'conversations_count'))
      expect(V2::Reports::Timeseries::AverageReportBuilder).to have_received(:new).with(account, params.merge(metric: 'avg_first_response_time'))
    end
  end

  describe '#bot_summary' do
    it 'returns a detailed summary of bot-specific conversation metrics' do
      bot_summary = subject.bot_summary
      expect(bot_summary).to eq(
        {
          bot_resolutions_count: 42,
          bot_handoffs_count: 42
        }
      )
    end
  end
end
