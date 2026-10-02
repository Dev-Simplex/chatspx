require 'rails_helper'

# N-07: o 5xx de quem entrega o push ganha nova tentativa, uma inscricao por vez.
RSpec.describe Notification::PushNotificationJob do
  let(:notification) { create(:notification) }

  it 'forwards the subscription being retried to the service' do
    service = instance_double(Notification::PushNotificationService, perform: true)
    allow(Notification::PushNotificationService).to receive(:new).and_return(service)

    described_class.perform_now(notification.id, 42)

    expect(Notification::PushNotificationService).to have_received(:new).with(notification: notification, subscription_id: 42)
  end

  it 'schedules another attempt instead of failing on a transient error' do
    allow(Notification::PushNotificationService).to receive(:new)
      .and_raise(Notification::PushNotificationService::TransientError, 'FCM HTTP 503')

    expect { described_class.perform_now(notification.id, 42) }.to have_enqueued_job(described_class).with(notification.id, 42)
  end
end
