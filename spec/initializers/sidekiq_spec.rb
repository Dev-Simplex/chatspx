require 'rails_helper'

RSpec.describe Sidekiq do
  it 'registers a death handler that reports the final error through the project tracker' do
    config = Sidekiq::Config.new
    allow(described_class).to receive(:configure_server).and_yield(config)
    allow(Rails.application.reloader).to receive(:to_prepare)
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: nil)
    error = RuntimeError.new('Job exhausted its retries')
    allow(ChatwootExceptionTracker).to receive(:new).with(error).and_return(tracker)

    load Rails.root.join('config/initializers/sidekiq.rb')
    expect(config.death_handlers.size).to eq(1)
    config.death_handlers.first.call({ 'retry_count' => 25 }, error)

    expect(tracker).to have_received(:capture_exception).once
  end
end
