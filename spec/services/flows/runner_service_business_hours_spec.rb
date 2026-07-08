# frozen_string_literal: true

require 'rails_helper'

# Cobre APENAS o wait com `business_hours: true` atravessando o RunnerService (o cálculo puro
# vive em Flows::BusinessHours). Arquivo separado do runner_service_spec.rb para não regredir
# aquela suíte.
RSpec.describe Flows::RunnerService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, timezone: 'UTC', working_hours_enabled: true) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  after { Current.reset }

  def wait_node(business_hours:, value: 5, unit: 'minutes')
    { 'id' => 'w1', 'type' => 'wait', 'wait' => { 'value' => value, 'unit' => unit, 'business_hours' => business_hours } }
  end

  def flow_with(wait)
    create(:flow, account: account, definition: {
             'nodes' => [wait, { 'id' => 'n2', 'type' => 'action', 'action_name' => 'add_label', 'action_params' => ['after'] }],
             'edges' => [{ 'from' => 'w1', 'to' => 'n2' }]
           })
  end

  describe 'wait node with business_hours flag' do
    it 'pushes wait_until to the next business opening when the raw wait lands off-hours' do
      travel_to(Time.zone.parse('2026-07-11 15:00 UTC')) do # Saturday
        flow = flow_with(wait_node(business_hours: true))
        described_class.new(flow: flow, conversation: conversation).perform
        # 5 min from Saturday 15:00 is still off-hours → pushed to Monday 09:00.
        expect(FlowRun.last.wait_until).to eq(Time.zone.parse('2026-07-13 09:00 UTC'))
      end
    end

    it 'keeps the raw wait_until when the flag is off (behaves as today)' do
      travel_to(Time.zone.parse('2026-07-11 15:00 UTC')) do
        flow = flow_with(wait_node(business_hours: false))
        described_class.new(flow: flow, conversation: conversation).perform
        expect(FlowRun.last.wait_until).to be_within(1.minute).of(5.minutes.from_now)
      end
    end

    it 'is a no-op when the inbox has no working hours enabled' do
      inbox.update!(working_hours_enabled: false)
      travel_to(Time.zone.parse('2026-07-11 15:00 UTC')) do
        flow = flow_with(wait_node(business_hours: true))
        described_class.new(flow: flow, conversation: conversation).perform
        expect(FlowRun.last.wait_until).to be_within(1.minute).of(5.minutes.from_now)
      end
    end

    it 'does not push when the wait already lands inside business hours' do
      travel_to(Time.zone.parse('2026-07-13 10:00 UTC')) do # Monday mid-morning
        flow = flow_with(wait_node(business_hours: true))
        described_class.new(flow: flow, conversation: conversation).perform
        expect(FlowRun.last.wait_until).to be_within(1.minute).of(5.minutes.from_now)
      end
    end
  end
end
