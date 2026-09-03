require 'rails_helper'

RSpec.describe Reports::PdfDataResolver do
  let(:account) { create(:account) }

  def build_response(score, **attrs)
    conversation = create(:conversation, account: account)
    create(:nps_response, conversation: conversation, account: account, score: score, **attrs)
  end

  describe '#resolve for nps' do
    subject(:data) { described_class.new(account: account, report_type: 'nps', filters: {}).resolve }

    before do
      5.times { build_response(10) } # promotores
      build_response(7)              # passivo
      2.times { build_response(3) }  # detratores
    end

    it 'computes NPS KPIs from trusted responded responses' do
      kpis = data[:kpis]
      expect(kpis[:total]).to eq(8)
      expect(kpis[:promoters]).to eq(5)
      expect(kpis[:passives]).to eq(1)
      expect(kpis[:detractors]).to eq(2)
      # (5 - 2) / 8 * 100 = 37.5 -> 38
      expect(kpis[:nps_score]).to eq(38)
    end

    it 'excludes flagged (suspeitas) responses via the trusted scope' do
      build_response(0, data_quality_flag: 'suspicious')
      expect(data[:kpis][:detractors]).to eq(2)
    end

    it 'returns a full 0..10 distribution ordered high to low' do
      scores = data[:distribution].map { |row| row[:score] }
      expect(scores).to eq((0..10).to_a.reverse)
      ten = data[:distribution].find { |row| row[:score] == 10 }
      expect(ten[:count]).to eq(5)
      expect(ten[:band]).to eq('promoter')
    end

    it 'aggregates NPS per agent' do
      agent = create(:user, account: account, role: :agent)
      conv = create(:conversation, account: account)
      create(:nps_response, conversation: conv, account: account, score: 10, assigned_agent: agent)

      agents = described_class.new(account: account, report_type: 'nps', filters: {}).resolve[:agents]
      mine = agents.find { |a| a[:id] == agent.id }
      expect(mine[:name]).to eq(agent.name)
      expect(mine[:nps_score]).to eq(100)
    end
  end

  it 'raises for an unknown report_type' do
    expect do
      described_class.new(account: account, report_type: 'nope', filters: {}).resolve
    end.to raise_error(ArgumentError)
  end

  describe 'every supported report type' do
    ReportPdfExport::SUPPORTED_REPORT_TYPES.each do |report_type|
      it "resolves #{report_type} without raising and returns a titled hash" do
        # `funnel` e o UNICO tipo que depende de um registro especifico: `funnel_data` faz
        # `@account.funnels.find(@filters[:funnel_id])` e, com filtro vazio, levanta
        # `RecordNotFound: Couldn't find Funnel without an ID`. Os demais resolvem sem filtro.
        # A varredura passava `{}` para todos — premissa que nao vale para este.
        filtros = report_type.to_s == 'funnel' ? { funnel_id: Funnel.create!(account: account, name: 'Funil').id } : {}
        data = described_class.new(account: account, report_type: report_type, filters: filtros).resolve
        expect(data).to include(:title, :period)
        expect(data[:title]).to be_present
      end
    end
  end
end
