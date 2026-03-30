class Notification::PushNotificationJob < ApplicationJob
  queue_as :default

  def perform(notification_id)
    notification = Notification.find_by(id: notification_id)
    return unless notification

    Notification::PushNotificationService.new(notification: notification).perform
  end
end
