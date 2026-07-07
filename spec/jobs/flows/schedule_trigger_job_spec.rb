# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Flows::ScheduleTriggerJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, status: :open) }

  after { Current.reset }

  def enable_engine
    account.update!(internal_attributes: account.internal_attributes.merge('flows_engine_enabled' => true))
  end

  # Schedule flow que adiciona uma etiqueta às conversas ABERTAS que casam com `conditions`.
  # As condições (status open) recortam o fan-out — sem elas o job é no-op seguro.
  def schedule_flow(config, active: true, label: 'scheduled', with_conditions: true)
    conditions = if with_conditions
                   [{ 'attribute_key' => 'status', 'filter_operator' => 'equal_to', 'values' => ['open'], 'query_operator' => nil }]
                 else
                   []
                 end
    create(:flow, account: account, active: active, trigger_type: :schedule,
                  trigger_config: config.merge('conditions' => conditions),
                  definition: {
                    'nodes' => [{ 'id' => 'n1', 'type' => 'action', 'action_name' => 'add_label', 'action_params' => [label] }],
                    'edges' => []
                  })
  end

  describe 'interval mode' do
    it 'fires over matching conversations once the window elapses and stamps last_fired_at' do
      enable_engine
      flow = schedule_flow({ 'mode' => 'interval', 'every' => 1, 'unit' => 'hours' })

      travel_to(2.hours.from_now) { described_class.perform_now }

      expect(conversation.reload.label_list).to include('scheduled')
      expect(flow.reload.trigger_config['last_fired_at']).to be_present
    end

    it 'does not fire before the window elapses' do
      enable_engine
      schedule_flow({ 'mode' => 'interval', 'every' => 1, 'unit' => 'days' })

      described_class.perform_now # criado agora → próxima janela só daqui a 1 dia

      expect(conversation.reload.label_list).not_to include('scheduled')
    end
  end

  describe 'cron mode' do
    it 'fires when the previous cron occurrence is after the baseline' do
      enable_engine
      flow = nil
      travel_to(Time.zone.parse('2026-07-06 08:00:00')) do
        flow = schedule_flow({ 'mode' => 'cron', 'cron' => '0 9 * * *' })
      end

      travel_to(Time.zone.parse('2026-07-07 09:05:00')) { described_class.perform_now }

      expect(conversation.reload.label_list).to include('scheduled')
      expect(flow.reload.trigger_config['last_fired_at']).to be_present
    end

    it 'ignores an invalid cron expression' do
      enable_engine
      schedule_flow({ 'mode' => 'cron', 'cron' => 'not a cron' })

      travel_to(2.days.from_now) { described_class.perform_now }

      expect(conversation.reload.label_list).not_to include('scheduled')
    end
  end

  describe 'idempotency' do
    it 'fires at most once per window even if the job runs twice' do
      enable_engine
      flow = schedule_flow({ 'mode' => 'interval', 'every' => 1, 'unit' => 'hours' })
      allow(Flows::RunnerService).to receive(:new).and_call_original

      travel_to(2.hours.from_now) do
        described_class.perform_now
        described_class.perform_now
      end

      expect(Flows::RunnerService).to have_received(:new).once
      expect(flow.reload.trigger_config['last_fired_at']).to be_present
    end
  end

  describe 'gating' do
    it 'does not fire an inactive flow' do
      enable_engine
      schedule_flow({ 'mode' => 'interval', 'every' => 1, 'unit' => 'hours' }, active: false)

      travel_to(2.hours.from_now) { described_class.perform_now }

      expect(conversation.reload.label_list).not_to include('scheduled')
    end

    it 'does not fire when the flows engine is off for the account' do
      schedule_flow({ 'mode' => 'interval', 'every' => 1, 'unit' => 'hours' }) # engine não habilitado

      travel_to(2.hours.from_now) { described_class.perform_now }

      expect(conversation.reload.label_list).not_to include('scheduled')
    end
  end

  describe 'target without conditions (safe no-op)' do
    it 'claims the window but does not fan out over every conversation' do
      enable_engine
      flow = schedule_flow({ 'mode' => 'interval', 'every' => 1, 'unit' => 'hours' }, with_conditions: false)
      allow(Flows::RunnerService).to receive(:new)

      travel_to(2.hours.from_now) { described_class.perform_now }

      expect(Flows::RunnerService).not_to have_received(:new)
      expect(flow.reload.trigger_config['last_fired_at']).to be_present # janela reservada mesmo no no-op
    end
  end
end
