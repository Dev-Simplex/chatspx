require 'rails_helper'

describe Notification::PushNotificationService do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account: account) }
  let!(:notification) { create(:notification, user: user, account: user.accounts.first) }
  let(:fcm_double) { instance_double(FCM) }
  let(:fcm_service_double) { instance_double(Notification::FcmService, fcm_client: fcm_double) }

  describe '#perform' do
    context 'when the push server returns success' do
      before do
        allow(WebPush).to receive(:payload_send).and_return(true)
        allow(Rails.logger).to receive(:info)
        allow(Notification::FcmService).to receive(:new).and_return(fcm_service_double)
        allow(fcm_double).to receive(:send_v1).and_return({ status_code: 200, body: { name: 'projects/x/messages/1' }.to_json })
        allow(GlobalConfigService).to receive(:load).with('FIREBASE_PROJECT_ID', nil).and_return('test_project_id')
        allow(GlobalConfigService).to receive(:load).with('FIREBASE_CREDENTIALS', nil).and_return('test_credentials')
      end

      it 'sends webpush notifications for webpush subscription' do
        with_modified_env VAPID_PUBLIC_KEY: 'test' do
          create(:notification_subscription, user: notification.user)

          described_class.new(notification: notification).perform
          expect(WebPush).to have_received(:payload_send)
          expect(Notification::FcmService).not_to have_received(:new)
          expect(Rails.logger).to have_received(:info).with("Browser push sent to #{user.email} with title #{notification.push_message_title}")
        end
      end

      it 'sends a fcm notification for firebase subscription' do
        with_modified_env ENABLE_PUSH_RELAY_SERVER: 'false' do
          create(:notification_subscription, user: notification.user, subscription_type: 'fcm')

          described_class.new(notification: notification).perform
          expect(Notification::FcmService).to have_received(:new)
          expect(fcm_double).to have_received(:send_v1)
          expect(WebPush).not_to have_received(:payload_send)
          expect(Rails.logger).to have_received(:info).with("FCM push sent to #{user.email} with title #{notification.push_message_title}")
        end
      end
    end
  end

  context 'when the push server returns error' do
    it 'sends webpush notifications for webpush subscription' do
      with_modified_env VAPID_PUBLIC_KEY: 'test' do
        mock_response = instance_double(Net::HTTPResponse, body: 'Subscription is invalid')
        mock_host = 'fcm.googleapis.com'

        allow(WebPush).to receive(:payload_send).and_raise(WebPush::InvalidSubscription.new(mock_response, mock_host))
        allow(Rails.logger).to receive(:info)

        create(:notification_subscription, :browser_push, user: notification.user)

        expect(Rails.logger).to receive(:info) do |message|
          expect(message).to include('WebPush subscription expired:')
        end

        described_class.new(notification: notification).perform
      end
    end
  end

  # N-07: o FCM HTTP v1 diz o resultado pelo status. Antes, qualquer resposta saia como "FCM push sent".
  describe 'FCM HTTP v1 responses' do
    let!(:subscription) { create(:notification_subscription, user: notification.user, subscription_type: 'fcm') }

    def responde(status)
      allow(fcm_double).to receive(:send_v1).and_return({ status_code: status, body: { error: { status: 'X' } }.to_json })
    end

    before do
      allow(Notification::FcmService).to receive(:new).and_return(fcm_service_double)
      allow(GlobalConfigService).to receive(:load).with('FIREBASE_PROJECT_ID', nil).and_return('test_project_id')
      allow(GlobalConfigService).to receive(:load).with('FIREBASE_CREDENTIALS', nil).and_return('test_credentials')
      allow(Rails.logger).to receive(:info)
    end

    it 'removes the subscription only when the token is gone (404 UNREGISTERED)' do
      responde(404)
      described_class.new(notification: notification).perform

      expect(NotificationSubscription.exists?(subscription.id)).to be(false)
    end

    it 'reports a rejected credential (401) and keeps the subscription' do
      responde(401)
      tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

      described_class.new(notification: notification).perform

      expect(tracker).to have_received(:capture_exception)
      expect(NotificationSubscription.exists?(subscription.id)).to be(true)
      expect(Rails.logger).not_to have_received(:info).with(/FCM push sent/)
    end

    it 'schedules a retry of THAT subscription only when FCM is down (5xx)' do
      responde(503)

      expect { described_class.new(notification: notification).perform }
        .to have_enqueued_job(Notification::PushNotificationJob).with(notification.id, subscription.id)
    end

    it 'raises on the retry itself, so the job retry_on handles backoff and reporting' do
      responde(503)

      expect { described_class.new(notification: notification, subscription_id: subscription.id).perform }
        .to raise_error(described_class::TransientError)
    end
  end
end
