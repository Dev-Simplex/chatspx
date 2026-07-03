# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Kanban::Ai::AvailabilityService do
  subject(:service) { described_class.new(account: account) }

  let(:account) { create(:account) }

  it 'is false when the captain_tasks feature is disabled' do
    expect(service.available?).to be(false)
  end

  context 'when captain_tasks is enabled' do
    before { account.enable_features!('captain_tasks') }

    it 'is false when no OpenAI key is configured' do
      allow_any_instance_of(Captain::OpenaiHookService).to receive(:configured?).and_return(false)
      expect(service.available?).to be(false)
    end

    it 'is true when an OpenAI key is configured' do
      allow_any_instance_of(Captain::OpenaiHookService).to receive(:configured?).and_return(true)
      expect(service.available?).to be(true)
    end
  end

  it 'never raises — degrades to false on error' do
    account.enable_features!('captain_tasks')
    allow_any_instance_of(Captain::OpenaiHookService).to receive(:configured?).and_raise(StandardError, 'boom')
    expect(service.available?).to be(false)
  end
end
